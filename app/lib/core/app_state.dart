import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'core_api.dart';
import 'core_process.dart';
import 'github_updates.dart';
import 'models.dart';
import 'prefs.dart';
import 'psiphon_exit.dart';
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

  /// True while the window is hidden in the tray (close-to-tray). The home
  /// animations mute via TickerMode and the pollers slow down; the status
  /// poll keeps running at 10s so the tray icon still follows the
  /// connection, and core-log polling stops (no logs are visible while
  /// hidden). The elapsed timer is computed from _connectedAt inside the
  /// status poll, so it needs no separate handling.
  bool windowHidden = false;

  /// True while the core was parked on purpose (idle in the tray, v1.5.37).
  /// Stops the _startCore retry loop from waking it behind our back; cleared
  /// when the window shows again or a connect needs the core.
  bool _corePaused = false;

  void setWindowHidden(bool hidden) {
    if (windowHidden == hidden) return;
    windowHidden = hidden;
    _startPolling(); // rebuilds the status timer at the right interval
    if (hidden) {
      _coreLogTimer?.cancel();
      _coreLogTimer = null;
      _parkCoreIfIdle();
    } else {
      _startCoreLogPolling();
      // The core parks itself while the app sits idle in the tray
      // (v1.5.37): wake it now so the Servers list and status are live.
      if (_corePaused) {
        _corePaused = false;
        _startCore();
      }
    }
    notifyListeners();
  }

  /// Parks the core while the app sits idle in the tray: with no tunnel up
  /// it does nothing but hold RAM, so it stops and restarts on show or on
  /// connect. Only when hidden — with the window open the Servers tab
  /// needs the core's location list. Never parks a live tunnel: only
  /// idle/failed states park (a connect/disconnect in flight keeps it).
  void _parkCoreIfIdle() {
    if (!windowHidden) return;
    if (status != VpnStatus.idle && status != VpnStatus.failed) return;
    _corePaused = true;
    if (coreProcess.isRunning) {
      coreProcess.stop();
      addLog('System', 'Core parked (idle in tray).');
    }
  }

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

    // The origin flag is the device's real location (its public IP),
    // NOT the system locale: a device set to English (US) in Iran
    // showed the US flag. Looked up once, before any tunnel is up,
    // so it sees the real IP; fire-and-forget so a slow lookup never
    // delays the core start.
    _detectOriginCountry();

    _updateRouteInfo();

    // Start core process in background
    _startCore();

    // Check updates on startup
    checkUpdates();
  }

  /// Detects the origin country from the device's public IP via
  /// Cloudflare's trace endpoint (`loc=IR`). Runs once at startup,
  /// before any tunnel is up. On any failure (offline, blocked) the
  /// origin stays 'AUTO' (generic icon) — a wrong flag is worse
  /// than no flag, so the system locale is never used here.
  Future<void> _detectOriginCountry() async {
    try {
      final client = HttpClient();
      try {
        final req = await client
            .getUrl(Uri.parse('https://www.cloudflare.com/cdn-cgi/trace'))
            .timeout(const Duration(seconds: 5));
        final res = await req.close().timeout(const Duration(seconds: 5));
        if (res.statusCode == 200) {
          final body = await res.transform(utf8.decoder).join();
          final loc = RegExp(r'^loc=([A-Za-z]{2})$', multiLine: true)
              .firstMatch(body)
              ?.group(1)
              ?.toUpperCase();
          if (loc != null && loc.length == 2) {
            originCode = loc;
            notifyListeners();
          }
        }
      } finally {
        client.close();
      }
    } catch (_) {}
  }

  /// Re-reads the route box from the current settings (called when the
  /// exit toggle or region changes, so the box shows the exit at once).
  void refreshRouteInfo() {
    _updateRouteInfo();
    notifyListeners();
  }

  void _updateRouteInfo() {
    if (isQuantum) {
      // Exit on: the destination is the exit, not the relay. The chosen
      // region is the contract (its name shows); for Fastest/auto the
      // probe's place is the fallback and lands via the poller.
      if (Prefs.exitEnabled) {
        final region = Prefs.exitRegion;
        if (region.isNotEmpty) {
          destCode = region;
          destName = PsiphonExit.regionName(region);
        } else {
          destCode = 'GLOBAL';
          destName = 'Psiphon exit · Fastest (auto)';
        }
        return;
      }
      final pinned = Prefs.server('aether');
      final label = Prefs.serverLabel('aether');
      if (pinned.isNotEmpty) {
        // 'CLXY', not 'CF': the flag widget renders any two-letter
        // code as a real flag emoji now, and CF would be the Central
        // African Republic. The relay is part of the CLXY mesh; the
        // name below still says which relay it is.
        destCode = 'CLXY';
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
    // Parked on purpose (idle in the tray, v1.5.37): stay off until the
    // window shows or a connect wakes us — including a retry timer
    // scheduled before the park.
    if (_corePaused) return;
    addLog('System', 'Starting ClxyPro Core sidecar…');
    final api = await coreProcess.startAndConnect();
    if (api != null) {
      addLog('System', 'Connected to local core daemon.');
      // A new daemon process restarts its log ids at 1: re-read from
      // the start, or the new process's first lines would be skipped.
      _lastCoreLogId = 0;
      _startCoreLogPolling();
      // Push the app's saved core/mode/location into the daemon so the
      // core matches what the UI shows after a restart.
      await _syncCoreSettings();
      _startPolling();
      loadServers();
    } else {
      addLog('Warn',
          'Core sidecar not available: ${coreProcess.lastError ?? 'unknown reason'}. Retrying…');
      // Retry in 3 seconds — unless the core was parked on purpose
      // meanwhile (idle in the tray): a parked core stays off.
      if (!_corePaused) Timer(const Duration(seconds: 3), _startCore);
    }
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(
        Duration(seconds: windowHidden ? 10 : 1), (timer) async {
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
          // Hyper only: the core's exit is the Firefox exit node.
          // On Quantum the destination is the pinned relay (set above
          // by _updateRouteInfo) — the Firefox exit must never
          // overwrite it, or a MASQUE connection shows "Germany".
          if (!isQuantum) {
            if (st.exit.isNotEmpty) destName = st.exit;
            if (st.exitIp.isNotEmpty) destIp = st.exitIp;
          }
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

        // Quantum + exit: the destination is the exit. The probe
        // answers after the connect, so this runs on every poll while
        // connected, not just at the transition.
        if (status == VpnStatus.connected && isQuantum && Prefs.exitEnabled) {
          _updateExitDestination(st);
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
    // Drop the old engine's list at once: a slow or failed load must
    // never leave the other engine's servers on screen.
    servers = [];
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
    required Future<bool> Function(bool forHyper) onNeedSerial,
  }) async {
    if (status == VpnStatus.connected || status == VpnStatus.connecting) {
      await disconnect();
    } else {
      await connect(onNeedSerial: onNeedSerial);
    }
  }

  Future<void> connect({
    required Future<bool> Function(bool forHyper) onNeedSerial,
  }) async {
    // Serial gate (v1.5.31): the first connect of each engine asks for a
    // serial (QuantumSerial), and only an unlocked engine may connect.
    // The flags are separate: a Quantum unlock does not unlock Hyper,
    // and vice versa. The engine itself is the aether sidecar now
    // (v1.5.22): the daemon scans for a relay in the background, and
    // the connect below waits for it to serve before probing traffic.
    if (isQuantum && !Prefs.quantumUnlocked) {
      final unlocked = await onNeedSerial(false);
      if (!unlocked) {
        return;
      }
    } else if (isHyper && !Prefs.hyperUnlocked) {
      final unlocked = await onNeedSerial(true);
      if (!unlocked) {
        return;
      }
    }

    status = VpnStatus.connecting;
    statusLabel = 'Connecting…';
    errorMessage = null;
    notifyListeners();

    addLog('VPN', 'Initiating connection (Core: $coreId, Mode: $mode)…');

    // The core parks itself while the app sits idle in the tray (v1.5.37):
    // wake it before connecting — a tray quick-connect starts from a
    // parked core. _startCore re-syncs settings and reloads servers.
    if (coreProcess.api == null) {
      _corePaused = false;
      await _startCore();
    }

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
        await _applyExitRegion();
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
          // The exit failing is the connect failing (Android's
          // PSIPHON_FAILED): Quantum itself connected, but the user
          // turned the exit on and it did not come up — never report
          // Connected with plain Quantum's Tehran IP instead.
          if (ast.psiphonError.isNotEmpty) {
            throw Exception(PsiphonExit.failedMessage);
          }
          if (ast.aetherState == 'serving') {
            // The exit starts right after aether serves: wait for it
            // too when it is on.
            if (!Prefs.exitEnabled || ast.psiphonRunning) break;
            if (statusLabel != 'Starting the Psiphon exit…') {
              statusLabel = 'Starting the Psiphon exit…';
              notifyListeners();
            }
          } else if (ast.aetherState == 'error') {
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
        if (ast.psiphonError.isNotEmpty) {
          throw Exception(PsiphonExit.failedMessage);
        }
        if (ast.aetherState != 'serving') {
          throw Exception(lastAetherError.isNotEmpty
              ? 'Quantum timed out ($lastAetherError)'
              : 'Quantum timed out — no working relay found');
        }
        if (Prefs.exitEnabled && !ast.psiphonRunning) {
          throw Exception(PsiphonExit.failedMessage);
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
    // A disconnect from the tray leaves the app hidden and idle: park
    // the core too, like closing the window does (v1.5.37).
    _parkCoreIfIdle();
    notifyListeners();
  }

  /// Writes the pinned Quantum relay (if any) to the core's peer cache
  /// so the next connect dials it first. Auto leaves the file alone:
  /// the core then quick-reconnects to its last working relay, or
  /// scans when there is none. Written at connect time because the
  /// sidecar overwrites the file whenever a scan finds a new relay.
  /// Sends the Psiphon exit the app wants to the core (POST
  /// /api/psiphon) before power-on, so the engine starts the exit with
  /// the right region once the MASQUE stage serves. A failure here is
  /// only logged: the core keeps its last setting, and the connect
  /// fails later with the exit's own error if the setting never landed.
  Future<void> _applyExitRegion() async {
    final api = coreProcess.api;
    if (api == null) return;
    try {
      await api.setPsiphon(
        enabled: Prefs.exitEnabled,
        region: Prefs.exitRegion,
      );
      if (Prefs.exitEnabled) {
        addLog('VPN',
            'Psiphon exit on (${Prefs.exitRegion.isEmpty ? 'Fastest' : Prefs.exitRegion})');
      }
    } catch (e) {
      addLog('Warn', 'Could not set the Psiphon exit on the core: $e');
    }
  }

  /// The exit's destination for the route box, from the core's probe.
  /// The chosen region is the contract (its name shows); the probe's
  /// place is only the fallback for Fastest/auto.
  void _updateExitDestination(CoreStatus st) {
    final region = Prefs.exitRegion;
    if (region.isNotEmpty) {
      destCode = region;
      destName = PsiphonExit.regionName(region);
    } else if (st.psiphonEgressCode.isNotEmpty) {
      destCode = st.psiphonEgressCode;
      destName = st.psiphonEgressPlace.isNotEmpty
          ? st.psiphonEgressPlace
          : 'Psiphon exit · Fastest (auto)';
    } else {
      destCode = 'GLOBAL';
      destName = 'Psiphon exit · Fastest (auto)';
    }
    if (st.psiphonEgressIp.isNotEmpty) destIp = st.psiphonEgressIp;
  }

  Future<void> _applyQuantumPeer() async {
    var peer = Prefs.server('aether');
    if (peer.isEmpty && servers.isNotEmpty) {
      // No relay pinned (fresh install, or the user never picked one
      // in the Servers screen): ping every relay in parallel and pin
      // the fastest, like Android does before connect. Without a peer
      // the core burns its whole 75s HTTP/2 scan, then the 75s HTTP/3
      // one — a two-minute first connect on a network where the
      // fastest relay answers in milliseconds.
      final results = await Future.wait(
        servers.map((s) async => (
              key: s.key,
              label: s.title,
              ms: await pingQuantumRelay(s.key),
            )),
      );
      final reachable = results.where((r) => r.ms >= 0).toList()
        ..sort((a, b) => a.ms.compareTo(b.ms));
      if (reachable.isNotEmpty) {
        final best = reachable.first;
        Prefs.setServer('aether', best.key, best.label);
        peer = best.key;
        addLog('VPN',
            'Quantum relay auto-pinned: ${best.label} (${best.ms}ms)');
      }
    }
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
    // A load started for one engine must never publish its list after
    // the user switched to the other engine (the Quantum fetch takes
    // seconds; a late arrival used to overwrite Hyper's list).
    final engine = coreId;
    if (isQuantum) {
      // Quantum relays come from the MASQUE subscription, not the
      // core — no daemon needed. Same list shape as Hyper's servers,
      // so the Servers screen works unchanged.
      try {
        final relays = await fetchQuantumRelays();
        if (coreId != engine) return;
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
      if (coreId != engine) return;
      servers = mapList(list);
      notifyListeners();
      if (servers.isEmpty) {
        // The core fetches the list from Mozilla on first use; if that
        // fetch was still running, the list is cached by now — retry once.
        await Future.delayed(const Duration(seconds: 5));
        if (coreId != engine) return;
        if (servers.isNotEmpty) return;
        final retry = await api.fetchServers();
        if (coreId != engine) return;
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

    final engine = coreId;
    if (isQuantum) {
      // Real pings: a TCP connect to each relay, all at once, each
      // updating its row as it answers. A relay that stays blank did
      // not answer in time.
      await Future.wait(servers.map((srv) async {
        final ms = await pingQuantumRelay(srv.key);
        if (coreId != engine) return;
        srv.pingMs = ms;
        notifyListeners();
      }));
      pingingAll = false;
      notifyListeners();
      return;
    }

    for (final srv in servers) {
      if (coreId != engine) break;
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

  // --- Core daemon logs -------------------------------------------------
  // The app's own addLog lines are only the headlines ("Starting…",
  // "Quantum relay pinned: …"). The scan stages, the aether sidecar
  // lines and the exit's own lines live in the core daemon, which
  // serves them at GET /api/logs. Without this poll the Logs tab
  // could never explain a slow connect — it showed two lines and
  // stopped. Runs on its own timer (not the status poller, which
  // pauses while connecting — exactly when the detail matters most).
  int _lastCoreLogId = 0;
  bool _fetchingCoreLogs = false;
  Timer? _coreLogTimer;

  void _startCoreLogPolling() {
    _coreLogTimer?.cancel();
    _coreLogTimer = Timer.periodic(const Duration(seconds: 2), (_) async {
      final api = coreProcess.api;
      if (api == null || _fetchingCoreLogs) return;
      _fetchingCoreLogs = true;
      try {
        final entries = await api.fetchLogs(after: _lastCoreLogId);
        if (entries.isEmpty) return;
        var maxId = _lastCoreLogId;
        for (final e in entries) {
          final id = e['id'] as int? ?? 0;
          if (id > maxId) maxId = id;
          final msg = e['message'] as String? ?? '';
          if (msg.isEmpty) continue;
          // Core INFO lines are system detail: show them under the
          // SYSTEM filter (the tab's fixed filter list has no CORE).
          final raw = (e['level'] as String? ?? 'INFO').toUpperCase();
          final level = raw == 'INFO' ? 'System' : raw;
          logs.insert(
            0,
            LogEntry(
              timestamp:
                  DateTime.tryParse(e['time'] as String? ?? '') ??
                      DateTime.now(),
              level: level,
              message: msg,
            ),
          );
        }
        _lastCoreLogId = maxId;
        if (logs.length > 500) logs.removeRange(500, logs.length);
        notifyListeners();
      } finally {
        _fetchingCoreLogs = false;
      }
    });
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
