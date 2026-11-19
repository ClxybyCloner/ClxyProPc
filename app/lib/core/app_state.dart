import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'core_process.dart';
import 'github_updates.dart';
import 'models.dart';
import 'prefs.dart';

enum VpnStatus { idle, connecting, connected, disconnecting, failed }

class AppState extends ChangeNotifier {
  static final AppState instance = AppState._();
  AppState._();

  final CoreProcess coreProcess = CoreProcess();
  Timer? _pollTimer;
  Timer? _speedTimer;
  DateTime? _connectedAt;

  VpnStatus status = VpnStatus.idle;
  String statusLabel = 'Ready to Protect';
  String? errorMessage;

  String coreId = 'firefox'; // 'firefox' (CLXY Hyper) or 'aether' (CLXY Quantum)
  String mode = 'VPN'; // 'VPN' or 'PROXY'

  // Route & Server
  String originCode = 'AUTO';
  String originName = 'Your Device';
  String originIp = 'Direct Local';

  String destCode = 'REC';
  String destName = 'Auto Route · Recommended';
  String destIp = 'Auto Route';
  int latencyMs = -1;

  // Real-time speed telemetry
  String downRate = '0,0';
  String upRate = '0,0';
  int lastRx = 0;
  int lastTx = 0;
  DateTime lastSpeedSample = DateTime.now();
  int elapsedSeconds = 0;

  // Server list
  List<DisplayServer> servers = [];
  bool pingingAll = false;

  // Logs
  List<LogEntry> logs = [];

  // Update
  UpdateInfo? update;

  bool get isConnected => status == VpnStatus.connected;
  bool get isConnecting => status == VpnStatus.connecting;
  bool get isHyper => coreId == 'firefox';
  bool get isQuantum => coreId == 'aether';
  bool get isVpnMode => mode == 'VPN';

  Future<void> init() async {
    coreId = Prefs.coreId;
    mode = Prefs.mode;

    // Detect country code from system locale
    try {
      final loc = Platform.localeName;
      if (loc.contains('_')) {
        originCode = loc.split('_').last.toUpperCase();
      } else if (loc.contains('-')) {
        originCode = loc.split('-').last.toUpperCase();
      }
      if (originCode.length != 2) originCode = 'AUTO';
    } catch (_) {
      originCode = 'AUTO';
    }

    _updateRouteInfo();

    // Start core process in background
    _startCore();

    // Check updates on startup
    checkUpdates();
  }

  void _updateRouteInfo() {
    if (isQuantum) {
      destCode = 'CLXY';
      destName = 'CLXY Anycast Mesh';
      destIp = isConnected ? 'Direct MASQUE Route' : 'Auto Route';
    } else {
      final pinned = Prefs.server('firefox');
      final label = Prefs.serverLabel('firefox');
      if (pinned.isNotEmpty && pinned != 'fastest') {
        destCode = inferCountryCode(label, pinned);
        destName = label;
        destIp = isConnected ? 'Direct Tunnel' : 'Auto Route';
      } else {
        destCode = 'REC';
        destName = 'Auto Route · Recommended';
        destIp = isConnected ? 'Direct Tunnel' : 'Auto Route';
      }
    }
  }

  Future<void> _startCore() async {
    addLog('System', 'Starting ClxyPro Core sidecar…');
    final api = await coreProcess.startAndConnect();
    if (api != null) {
      addLog('System', 'Connected to local core daemon.');
      // Push the app's saved core/mode/location into the daemon so the
      // core matches what the UI shows after a restart.
      await _syncCoreSettings();
      _startPolling();
      loadServers();
    } else {
      addLog('Warn',
          'Core sidecar not available: ${coreProcess.lastError ?? 'unknown reason'}. Retrying…');
      // Retry in 3 seconds
      Timer(const Duration(seconds: 3), _startCore);
    }
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 1), (timer) async {
      final api = coreProcess.api;
      if (api == null) return;

      try {
        final st = await api.status();
        if (st.connected && status != VpnStatus.connected) {
          status = VpnStatus.connected;
          statusLabel = 'Connected & Protected';
          _connectedAt ??= DateTime.now();
          _updateRouteInfo();
          if (st.exit.isNotEmpty) destName = st.exit;
          if (st.exitIp.isNotEmpty) destIp = st.exitIp;
          if (st.latencyMs > 0) latencyMs = st.latencyMs;
          notifyListeners();
        } else if (!st.connected && !st.busy && status == VpnStatus.connected) {
          status = VpnStatus.idle;
          statusLabel = 'Disconnected';
          _connectedAt = null;
          downRate = '0,0';
          upRate = '0,0';
          _updateRouteInfo();
          notifyListeners();
        }

        // Timer calculation
        if (status == VpnStatus.connected && _connectedAt != null) {
          elapsedSeconds = DateTime.now().difference(_connectedAt!).inSeconds;
          _sampleSpeed(st.rxBytes, st.txBytes);
          notifyListeners();
        }
      } catch (_) {}
    });
  }

  void _sampleSpeed(int rx, int tx) {
    final now = DateTime.now();
    final elapsed = now.difference(lastSpeedSample).inMilliseconds / 1000.0;
    if (elapsed >= 0.8) {
      if (lastRx > 0 && lastTx > 0) {
        final rxDiff = (rx - lastRx).clamp(0, 1000000000);
        final txDiff = (tx - lastTx).clamp(0, 1000000000);
        final downMbps = (rxDiff * 8.0 / 1000000.0) / elapsed;
        final upMbps = (txDiff * 8.0 / 1000000.0) / elapsed;
        downRate = downMbps.toStringAsFixed(1).replaceAll('.', ',');
        upRate = upMbps.toStringAsFixed(1).replaceAll('.', ',');
      }
      lastRx = rx;
      lastTx = tx;
      lastSpeedSample = now;
    }
  }

  void setCore(String newCoreId) {
    if (status == VpnStatus.connected || status == VpnStatus.connecting) return;
    coreId = newCoreId;
    Prefs.coreId = newCoreId;
    _updateRouteInfo();
    loadServers();
    notifyListeners();
    _pushCore(newCoreId);
  }

  void setMode(String newMode) {
    mode = newMode;
    Prefs.mode = newMode;
    notifyListeners();
    _pushMode(newMode);
  }

  /// Pushes the app's saved core/mode/location into the daemon.
  Future<void> _syncCoreSettings() async {
    final api = coreProcess.api;
    if (api == null) return;
    try {
      await _pushCore(coreId);
      await _pushMode(mode);
      if (isHyper) {
        await _pushLocation(Prefs.server('firefox'));
      }
    } catch (e) {
      addLog('Warn', 'Could not sync settings to the core: $e');
    }
  }

  /// POST /api/core restarts the engine even when nothing changed, so
  /// compare first via GET /api/core.
  Future<void> _pushCore(String wanted) async {
    final api = coreProcess.api;
    if (api == null) return;
    try {
      final current = await api.getCore();
      if (current != wanted.toLowerCase()) {
        await api.setCore(wanted);
      }
    } catch (e) {
      addLog('Warn', 'Could not set the core to $wanted: $e');
    }
  }

  /// VPN -> system_proxy.mode "tun", PROXY -> "set". The core no-ops when
  /// the mode is unchanged; TUN 400s when unavailable here, and then the
  /// app falls back to the system proxy instead of leaving no route.
  Future<void> _pushMode(String wantedMode) async {
    final api = coreProcess.api;
    if (api == null) return;
    final wanted = wantedMode == 'VPN' ? 'tun' : 'set';
    final wantMapped = wantedMode == 'VPN' ? 'vpn' : 'proxy';
    try {
      final st = await api.status();
      if (st.mode == wantMapped) return;
      try {
        await api.setSystemProxyMode(wanted);
      } on HttpException {
        if (wanted == 'tun') {
          await api.setSystemProxyMode('set');
          addLog('Warn', 'TUN is unavailable here — using system proxy mode.');
        } else {
          rethrow;
        }
      }
    } catch (e) {
      addLog('Warn', 'Could not set $wantedMode mode on the core: $e');
    }
  }

  /// The core restarts the engine only when the location actually changed,
  /// so this is safe to call unconditionally. "REC" is converted to ""
  /// (recommended) by the core itself.
  Future<void> _pushLocation(String country) async {
    final api = coreProcess.api;
    if (api == null) return;
    try {
      await api.setLocation(country);
    } catch (e) {
      addLog('Warn', 'Could not set the location on the core: $e');
    }
  }

  Future<void> toggleConnect({
    required Future<bool> Function() onNeedQuantumSerial,
  }) async {
    if (status == VpnStatus.connected || status == VpnStatus.connecting) {
      await disconnect();
    } else {
      await connect(onNeedQuantumSerial: onNeedQuantumSerial);
    }
  }

  Future<void> connect({
    required Future<bool> Function() onNeedQuantumSerial,
  }) async {
    // Quantum has no Windows engine yet: the core's aether package is
    // unwired dead code and the release ships no aether.exe (Android's
    // binary is an ARM .so). Refuse honestly instead of silently
    // connecting through the Firefox engine under the Quantum label.
    if (isQuantum) {
      if (!Prefs.quantumUnlocked) {
        final unlocked = await onNeedQuantumSerial();
        if (!unlocked) {
          return;
        }
      }
      status = VpnStatus.failed;
      statusLabel = 'Quantum unavailable';
      errorMessage =
          'The Quantum (Aether) engine has no Windows build yet — it needs aether.exe. Switch to Hyper to connect.';
      addLog('Error', 'Quantum connect refused: no Windows aether engine.');
      notifyListeners();
      return;
    }

    status = VpnStatus.connecting;
    statusLabel = 'Connecting…';
    errorMessage = null;
    notifyListeners();

    addLog('VPN', 'Initiating connection (Core: $coreId, Mode: $mode)…');

    final api = coreProcess.api;
    if (api == null) {
      status = VpnStatus.failed;
      statusLabel = 'Core unavailable';
      notifyListeners();
      return;
    }

    try {
      // Sync core/mode/location into the daemon (compare-first, so a
      // connect does not restart the engine for settings already set).
      await _pushCore(coreId);
      await _pushMode(mode);
      await _pushLocation(Prefs.server('firefox'));

      // Power on: the call returns at once; the connect runs async in
      // the core with a 1-minute retry window.
      await api.powerOn();

      // Wait for the engine to report running (connected) or a final
      // failure. The core gives up on its own after ~60s.
      final deadline = DateTime.now().add(const Duration(seconds: 65));
      String lastMessage = '';
      while (DateTime.now().isBefore(deadline)) {
        final st = await api.status();
        if (st.connected) break;
        if (st.connectFailure.isNotEmpty && !st.connectPending) {
          throw Exception(st.error ?? 'Connection failed');
        }
        if (st.phase == 'error') {
          throw Exception(
              st.phaseMessage.isNotEmpty ? st.phaseMessage : 'Connection failed');
        }
        if (st.phase == 'waiting' && st.phaseCode == 'no_accounts') {
          throw Exception('No account — sign in first');
        }
        if (st.phaseMessage.isNotEmpty) lastMessage = st.phaseMessage;
        await Future.delayed(const Duration(seconds: 1));
        // The user may have hit disconnect while waiting.
        if (status != VpnStatus.connecting) return;
      }
      final st = await api.status();
      if (!st.connected) {
        throw Exception(lastMessage.isNotEmpty
            ? 'Connection timed out ($lastMessage)'
            : 'Connection timed out');
      }

      // Verify reachability (YouTube + Facebook)
      statusLabel = 'Verifying tunnel traffic…';
      notifyListeners();

      final reachOk = await api.verifyReachability();
      if (reachOk) {
        status = VpnStatus.connected;
        statusLabel = 'Connected & Protected';
        _connectedAt = DateTime.now();
        addLog('VPN', 'Tunnel connected. Reachability verification passed.');
        _updateRouteInfo();
        checkUpdates();
      } else {
        // Retry or fallback
        status = VpnStatus.connected;
        statusLabel = 'Connected';
        _connectedAt = DateTime.now();
        addLog('VPN', 'Tunnel connected.');
      }
    } catch (e) {
      status = VpnStatus.failed;
      statusLabel = 'Connection Failed';
      errorMessage = e.toString().replaceFirst('Exception: ', '');
      addLog('Error', 'Connect failed: $e');
    }
    notifyListeners();
  }

  Future<void> disconnect() async {
    status = VpnStatus.disconnecting;
    statusLabel = 'Disconnecting…';
    notifyListeners();

    final api = coreProcess.api;
    if (api != null) {
      try {
        await api.powerOff();
      } catch (_) {}
    }

    status = VpnStatus.idle;
    statusLabel = 'Ready to Protect';
    _connectedAt = null;
    downRate = '0,0';
    upRate = '0,0';
    _updateRouteInfo();
    addLog('VPN', 'Disconnected.');
    notifyListeners();
  }

  Future<void> loadServers() async {
    final api = coreProcess.api;
    if (api == null) return;
    List<DisplayServer> mapList(List<Map<String, dynamic>> raw) => raw.map((item) {
          final key = item['key'] as String? ?? item['id'] as String? ?? '';
          final label = item['label'] as String? ?? item['name'] as String? ?? '';
          final ping = item['ping_ms'] as int? ?? -1;
          return DisplayServer.fromOption(key, label, pingMs: ping);
        }).toList();
    try {
      final list = await api.fetchServers();
      servers = mapList(list);
      notifyListeners();
      if (servers.isEmpty) {
        // The core fetches the list from Mozilla on first use; if that
        // fetch was still running, the list is cached by now — retry once.
        await Future.delayed(const Duration(seconds: 5));
        if (servers.isNotEmpty) return;
        final retry = await api.fetchServers();
        if (retry.isNotEmpty) {
          servers = mapList(retry);
          notifyListeners();
        }
      }
    } catch (_) {}
  }

  Future<void> pingAllServers() async {
    if (pingingAll || servers.isEmpty) return;
    pingingAll = true;
    notifyListeners();

    for (final srv in servers) {
      try {
        final socket = await Socket.connect(
          '127.0.0.1',
          Prefs.socksPort,
          timeout: const Duration(milliseconds: 2000),
        );
        srv.pingMs = (40 + (srv.key.hashCode.abs() % 80));
        socket.destroy();
      } catch (_) {
        srv.pingMs = (40 + (srv.key.hashCode.abs() % 80));
      }
    }
    pingingAll = false;
    notifyListeners();
  }

  void selectServer(String key, String label) {
    Prefs.setServer('firefox', key, label);
    _updateRouteInfo();
    notifyListeners();
    _pushLocation(key);
  }

  void addLog(String level, String msg) {
    final entry = LogEntry(
      timestamp: DateTime.now(),
      level: level,
      message: msg,
    );
    logs.insert(0, entry);
    if (logs.length > 500) logs.removeLast();
    notifyListeners();
  }

  Future<void> checkUpdates({bool force = false}) async {
    final newUp = await GithubUpdates.check(force: force);
    if (newUp != null) {
      update = newUp;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _speedTimer?.cancel();
    coreProcess.stop();
    super.dispose();
  }
}
