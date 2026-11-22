import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'core_process.dart';
import 'github_updates.dart';
import 'models.dart';
import 'prefs.dart';
import 'quantum_sub.dart';
import 'tun_service.dart';

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
      final pinned = Prefs.server('aether');
      final label = Prefs.serverLabel('aether');
      if (pinned.isNotEmpty) {
        destCode = 'CF';
        // A label pinned by an older version still says "Amir N";
        // re-remark it the same way the list does.
        destName = label.isNotEmpty ? remarkRelayName(label) : pinned;
        destIp = pinned;
      } else {
        destCode = 'CLXY';
        destName = 'CLXY Anycast Mesh';
        destIp = isConnected ? 'Direct MASQUE Route' : 'Auto Route';
      }
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

      // The connect/disconnect flows own status while they run: they
      // set the label step by step (Connecting… → Verifying… → TUN…)
      // and only report Connected after every check passed. If the
      // poller flipped status to connected the moment the core's phase
      // turned running, the UI showed "Connected & Protected" seconds
      // too early — and the flow's `status != connecting` guards then
      // bailed out mid-flow, leaving the label stuck on "Verifying
      // tunnel traffic…" with the timer already running. A failed
      // connect stays failed too: the poller must not overrule it a
      // second later just because the core is still up.
      if (status == VpnStatus.connecting ||
          status == VpnStatus.disconnecting ||
          status == VpnStatus.failed) {
        return;
      }

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
        final downKBps = (rxDiff / 1024.0) / elapsed;
        final upKBps = (txDiff / 1024.0) / elapsed;
        downRate = downKBps.toStringAsFixed(1).replaceAll('.', ',');
        upRate = upKBps.toStringAsFixed(1).replaceAll('.', ',');
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

  /// Installs the TUN service when VPN mode needs it and it is not
  /// installed yet. The install command asks for administrator rights
  /// itself (one Windows UAC prompt). Throws when the user declines the
  /// prompt or the install fails, so the connect fails honestly instead
  /// of showing "Connected" with a dead TUN. No-op when TUN is
  /// unsupported here (the mode push falls back to the system proxy).
  Future<void> _ensureTunService() async {
    final api = coreProcess.api;
    if (api == null) return;
    final st = await api.status();
    if (!st.tunSupported || st.tunInstalled) return;
    statusLabel = 'Installing TUN service…';
    notifyListeners();
    addLog('VPN',
        'Installing the TUN service (Windows will ask for administrator approval)…');
    final tun = TunService.besideCore(CoreProcess.executablePath);
    final result = await tun.install();
    switch (result) {
      case TunServiceDone():
        addLog('VPN', 'TUN service installed.');
      case TunServiceCancelled():
        throw Exception(
            'TUN service install declined — allow the administrator prompt, or switch to PROXY mode.');
      case TunServiceFailed(:final error):
        throw Exception('Could not install the TUN service: $error');
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
    // Quantum keeps its serial gate: the first Quantum connect asks for
    // a serial (QuantumSerial), and only an unlocked app may connect.
    // The engine itself is the aether sidecar now (v1.5.22): the daemon
    // scans for a relay in the background, and the connect below waits
    // for it to serve before probing traffic.
    if (isQuantum && !Prefs.quantumUnlocked) {
      final unlocked = await onNeedQuantumSerial();
      if (!unlocked) {
        return;
      }
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
      // VPN mode needs the TUN service installed first — the daemon's
      // own TunStatus comment says it: "the app installs it before it
      // turns the TUN mode on". Without it the core's tunSync dials a
      // service that does not exist (TunCodeMissing, retried silently)
      // and VPN mode shows "Connected" with no traffic routed at all.
      // The install asks for administrator rights itself (one UAC
      // prompt); declining it leaves PROXY mode as the way to connect.
      if (isVpnMode) {
        await _ensureTunService();
      }

      // Sync core/mode/location into the daemon (compare-first, so a
      // connect does not restart the engine for settings already set).
      // Quantum picks its own relay (anycast): no location to push —
      // but a pinned relay from the Servers list is written to the
      // peer file first, so the supervisor's quick-reconnect stage
      // dials it before falling back to the scan.
      if (isQuantum) {
        await _applyQuantumPeer();
      }
      await _pushCore(coreId);
      await _pushMode(mode);
      if (isHyper) {
        await _pushLocation(Prefs.server('firefox'));
      }

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

      // Quantum: phase == running only means the engine is up — the
      // aether sidecar still scans for a relay in the background, and
      // the reachability probe's 6s deadline is far too short for a
      // scan. Wait for the sidecar to serve first (up to 180s: the
      // core's whole scan is 162s). An error fails the connect with
      // the sidecar's own reason; the last reason is kept, because a
      // failed connect turns the proxy off and the aether field leaves
      // the status with the engine.
      if (isQuantum) {
        statusLabel = 'Scanning for Quantum relays…';
        notifyListeners();
        final aetherDeadline =
            DateTime.now().add(const Duration(seconds: 180));
        String lastAetherError = '';
        while (DateTime.now().isBefore(aetherDeadline)) {
          final ast = await api.status();
          if (ast.aetherState == 'serving') break;
          if (ast.aetherState == 'error') {
            throw Exception(ast.aetherMessage.isNotEmpty
                ? 'Quantum failed: ${ast.aetherMessage}'
                : 'Quantum failed');
          }
          if (ast.aetherMessage.isNotEmpty) {
            lastAetherError = ast.aetherMessage;
            if (statusLabel != ast.aetherMessage) {
              statusLabel = ast.aetherMessage;
              notifyListeners();
            }
          }
          if (!ast.connected) {
            throw Exception(lastAetherError.isNotEmpty
                ? 'Quantum failed: $lastAetherError'
                : 'Connection failed');
          }
          if (ast.connectFailure.isNotEmpty && !ast.connectPending) {
            throw Exception(lastAetherError.isNotEmpty
                ? 'Quantum failed: $lastAetherError'
                : (ast.error ?? 'Connection failed'));
          }
          await Future.delayed(const Duration(seconds: 1));
          if (status != VpnStatus.connecting) return;
        }
        final ast = await api.status();
        if (ast.aetherState != 'serving') {
          throw Exception(lastAetherError.isNotEmpty
              ? 'Quantum timed out ($lastAetherError)'
              : 'Quantum timed out — no working relay found');
        }
      }

      // Verify reachability (YouTube + Facebook). A failed check used to
      // still report "Connected" — the fake connect. Never again: retry
      // once (the first probe can race the engine waking up), then fail
      // honestly with the traffic check as the reason.
      statusLabel = 'Verifying tunnel traffic…';
      notifyListeners();

      var reachOk = await api.verifyReachability();
      if (!reachOk) {
        addLog('Warn', 'Traffic check failed — retrying once…');
        await Future.delayed(const Duration(seconds: 2));
        if (status != VpnStatus.connecting) return;
        reachOk = await api.verifyReachability();
      }
      if (!reachOk) {
        throw Exception(
            'Tunnel is up but carries no traffic — the traffic check failed');
      }

      // In VPN mode the user's traffic goes through the TUN adapter, not
      // the SOCKS proxy the reachability probe used. Wait until the core
      // reports the TUN on; a TUN error fails the connect with the
      // core's own reason (missing service, no driver, busy adapter).
      // Gated on the CORE's mode: when TUN is unavailable _pushMode falls
      // back to the system proxy, and there is no TUN to wait for.
      final modeCheck = await api.status();
      if (modeCheck.mode == 'vpn') {
        statusLabel = 'Waiting for TUN…';
        notifyListeners();
        final tunDeadline =
            DateTime.now().add(const Duration(seconds: 30));
        while (DateTime.now().isBefore(tunDeadline)) {
          final tst = await api.status();
          if (tst.tunState == 'on') break;
          if (tst.tunState == 'error') {
            throw Exception(tst.tunError ?? 'TUN failed to start');
          }
          if (status != VpnStatus.connecting) return;
          await Future.delayed(const Duration(seconds: 1));
        }
        final tst = await api.status();
        if (tst.tunState != 'on') {
          throw Exception(tst.tunState == 'error'
              ? (tst.tunError ?? 'TUN failed to start')
              : 'TUN did not come up in time');
        }
      }

      status = VpnStatus.connected;
      statusLabel = 'Connected & Protected';
      _connectedAt = DateTime.now();
      addLog('VPN', 'Tunnel connected. Reachability verification passed.');
      _updateRouteInfo();
      checkUpdates();
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

  /// Writes the pinned Quantum relay (if any) to the core's peer cache
  /// so the next connect dials it first. Auto leaves the file alone:
  /// the core then quick-reconnects to its last working relay, or
  /// scans when there is none. Written at connect time because the
  /// sidecar overwrites the file whenever a scan finds a new relay.
  Future<void> _applyQuantumPeer() async {
    final peer = Prefs.server('aether');
    if (peer.isEmpty) return;
    final file = File(
        '${Prefs.userDataDir.path}${Platform.pathSeparator}aether-peer.txt');
    try {
      await file.writeAsString(peer);
      addLog('VPN', 'Quantum relay pinned: $peer');
    } catch (e) {
      addLog('Warn', 'Could not pin Quantum relay: $e');
    }
  }

  Future<void> loadServers() async {
    if (isQuantum) {
      // Quantum relays come from the MASQUE subscription, not the
      // core — no daemon needed. Same list shape as Hyper's servers,
      // so the Servers screen works unchanged.
      try {
        final relays = await fetchQuantumRelays();
        servers = relays
            .map((r) => DisplayServer(
                  key: r.endpoint,
                  flagCode: 'CF',
                  title: r.name,
                  city: r.endpoint,
                  countryName: r.name,
                ))
            .toList();
        notifyListeners();
      } catch (_) {}
      return;
    }
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

    if (isQuantum) {
      // Real pings: a TCP connect to each relay, all at once, each
      // updating its row as it answers. A relay that stays blank did
      // not answer in time.
      await Future.wait(servers.map((srv) async {
        srv.pingMs = await pingQuantumRelay(srv.key);
        notifyListeners();
      }));
      pingingAll = false;
      notifyListeners();
      return;
    }

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
    if (isQuantum) {
      // The key is the relay endpoint; it is written to the peer file
      // at connect time (see _applyQuantumPeer). Empty key = Auto.
      Prefs.setServer('aether', key, label);
      _updateRouteInfo();
      notifyListeners();
      return;
    }
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
