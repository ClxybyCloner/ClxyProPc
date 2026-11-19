import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

class CoreEndpoint {
  final Uri baseUri;
  final String token;

  const CoreEndpoint(this.baseUri, this.token);
}

/// The core's real status shape (StatusView from the daemon's
/// GET /api/status), NOT the flat shape the app used to parse.
///
/// The app used to expect {running, connected, mode, core, exit, exit_ip,
/// latency_ms, rx_bytes, tx_bytes, uptime_sec, error} — none of which the
/// core returns — so `connected` was always false, the poller never flipped
/// to connected, and speeds/latency never updated. The core actually
/// returns {state{phase,message,code}, proxy{country_name,started_at,
/// sleeping_since}, exit{ipv4,country_name,latency_ms}, traffic{up,down},
/// connect_pending, connect_failure, selection, selection_name,
/// system_proxy}. Phases: starting / running / waiting / error / off.
/// Connected, the way the core's own tray reads it (TrayStatus.Summary):
/// phase == "running" (sleeping counts — the tunnel wakes on traffic).
class CoreStatus {
  final String phase; // starting | running | waiting | error | off
  final String phaseMessage; // the core's English message
  final String phaseCode; // e.g. no_accounts, waiting_for_network
  final bool running; // the engine is up in any form (not off)
  final bool connected; // phase == running
  final bool busy; // starting, or an explicit connect may still retry
  final bool connectPending;
  final String connectFailure; // proxy.Failure* code, '' when none
  final String selection; // the core's current location ('' = recommended)
  final String selectionName;
  final String mode; // 'vpn' (tun) | 'proxy' (set) | '' (clear/unknown)
  final String core; // not in the status view; 'firefox' unless told otherwise
  final String exit;
  final String exitIp;
  final int latencyMs;
  final int rxBytes; // traffic.down
  final int txBytes; // traffic.up
  final int uptimeSec; // seconds since proxy.started_at
  final String? error; // friendly failure, or the phase message

  CoreStatus({
    required this.phase,
    required this.phaseMessage,
    required this.phaseCode,
    required this.running,
    required this.connected,
    this.busy = false,
    this.connectPending = false,
    this.connectFailure = '',
    this.selection = '',
    this.selectionName = '',
    required this.mode,
    required this.core,
    required this.exit,
    required this.exitIp,
    required this.latencyMs,
    required this.rxBytes,
    required this.txBytes,
    required this.uptimeSec,
    this.error,
  });

  /// Friendly wording for the core's proxy.Failure* codes
  /// (internal/proxy/failure.go). Unknown codes pass through as-is.
  static String friendlyFailure(String code) {
    switch (code) {
      case 'no_network':
        return 'No network connection';
      case 'unreachable':
        return 'Mozilla servers are unreachable from this network';
      case 'inside_vpn':
        return 'Already inside another VPN';
      case 'upstream_proxy':
        return 'The upstream proxy refused the connection';
      case 'refused':
        return 'The server refused the connection';
      case 'location_refused':
        return 'This location refused the connection — try another country';
      case 'sign_in':
        return 'Sign-in expired — sign in again';
      case 'quota':
        return 'Account quota exceeded';
      case 'not_entitled':
        return 'This account is not entitled to the VPN';
      case 'region':
        return 'Service unavailable in this region (Guardian 451)';
      case 'server':
        return 'Server error — try again';
      case 'no_account':
        return 'No account — sign in first';
      default:
        return code.isEmpty ? 'Connection failed' : code;
    }
  }

  factory CoreStatus.fromJson(Map<String, dynamic> json) {
    final state = json['state'] as Map<String, dynamic>? ?? const {};
    final proxy = json['proxy'] as Map<String, dynamic>? ?? const {};
    final exit = json['exit'] as Map<String, dynamic>? ?? const {};
    final traffic = json['traffic'] as Map<String, dynamic>? ?? const {};

    final phase = (state['phase'] as String? ?? '').toLowerCase();
    final phaseMessage = state['message'] as String? ?? '';
    final phaseCode = state['code'] as String? ?? '';
    final connected = phase == 'running';
    final connectPending = json['connect_pending'] as bool? ?? false;
    final connectFailure = json['connect_failure'] as String? ?? '';

    int uptimeSec = 0;
    final startedAt = proxy['started_at'] as String?;
    if (startedAt != null && startedAt.isNotEmpty) {
      final started = DateTime.tryParse(startedAt);
      if (started != null) {
        uptimeSec = DateTime.now().difference(started).inSeconds.clamp(0, 1 << 31);
      }
    }

    final exitName = exit['country_name'] as String? ?? '';
    final proxyName = proxy['country_name'] as String? ?? '';
    final sysProxy = (json['system_proxy'] as String? ?? '').toLowerCase();
    final mode = sysProxy == 'tun'
        ? 'vpn'
        : sysProxy == 'set'
            ? 'proxy'
            : '';

    String? error;
    if (connectFailure.isNotEmpty) {
      error = friendlyFailure(connectFailure);
    } else if ((phase == 'error' || phase == 'waiting') && phaseMessage.isNotEmpty) {
      error = phaseMessage;
    }

    return CoreStatus(
      phase: phase,
      phaseMessage: phaseMessage,
      phaseCode: phaseCode,
      running: phase.isNotEmpty && phase != 'off',
      connected: connected,
      busy: phase == 'starting' || connectPending,
      connectPending: connectPending,
      connectFailure: connectFailure,
      selection: json['selection'] as String? ?? '',
      selectionName: json['selection_name'] as String? ?? '',
      mode: mode,
      core: 'firefox',
      exit: exitName.isNotEmpty ? exitName : proxyName,
      exitIp: exit['ipv4'] as String? ?? '',
      latencyMs: (exit['latency_ms'] as num?)?.toInt() ?? -1,
      rxBytes: (traffic['down'] as num?)?.toInt() ?? 0,
      txBytes: (traffic['up'] as num?)?.toInt() ?? 0,
      uptimeSec: uptimeSec,
      error: error,
    );
  }
}

/// The core's real API.
///
/// History: this class used to call POST /api/connect, POST /api/disconnect
/// and GET /api/servers — endpoints the core NEVER had (the daemon's mux
/// has no such routes). Every connect 404'd ("Connection Failed" in both
/// modes) and the server list was always empty. The real contract:
///
///   POST /api/power        {"on": true}  -> Daemon.Connect(): the app's
///                          button; the connect runs async with a 1-minute
///                          retry window, the call itself returns 200 at
///                          once. {"on": false} -> Daemon.SetOn(false).
///   GET  /api/locations    -> [{code,name,city,server,recommended,ping_ms}]
///   POST /api/location     {"country": code | "fastest" | ""} (restarts the
///                          engine only when the location actually changed)
///   GET  /api/core         -> {"core": "firefox" | "aether"}
///   POST /api/core         {"core": ...} (ALWAYS restarts the engine, so
///                          callers must compare first via GET /api/core)
///   POST /api/system-proxy {"mode": "tun" | "set" | "clear"}; "tun" 400s
///                          when TUN is unavailable here. No-op when the
///                          mode is unchanged. In -app mode the core itself
///                          applies the mode to Windows (systemProxySync /
///                          TunSync); the app never touches the registry.
///   GET  /api/reachability -> {"ok": bool, "detail": ...}
class CoreApi {
  final CoreEndpoint endpoint;
  final http.Client _client = http.Client();

  CoreApi(this.endpoint);

  void close() {
    _client.close();
  }

  Map<String, String> get _headers => {
        'X-Local-Token': endpoint.token,
        'Content-Type': 'application/json',
      };

  Future<CoreStatus> status() async {
    final url = endpoint.baseUri.replace(path: '/api/status');
    final res = await _client.get(url, headers: _headers).timeout(const Duration(seconds: 4));
    if (res.statusCode == 200) {
      return CoreStatus.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
    }
    throw HttpException('status returned ${res.statusCode}: ${res.body}');
  }

  Future<String> getCore() async {
    final url = endpoint.baseUri.replace(path: '/api/core');
    final res = await _client.get(url, headers: _headers).timeout(const Duration(seconds: 4));
    if (res.statusCode == 200) {
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      return (data['core'] as String? ?? 'firefox').toLowerCase();
    }
    throw HttpException('get core returned ${res.statusCode}: ${res.body}');
  }

  Future<void> setCore(String core) async {
    final url = endpoint.baseUri.replace(path: '/api/core');
    final res = await _client
        .post(url, headers: _headers, body: jsonEncode({'core': core.toLowerCase()}))
        .timeout(const Duration(seconds: 6));
    if (res.statusCode != 200) {
      throw HttpException('set core returned ${res.statusCode}: ${res.body}');
    }
  }

  Future<void> setLocation(String country) async {
    final url = endpoint.baseUri.replace(path: '/api/location');
    final res = await _client
        .post(url, headers: _headers, body: jsonEncode({'country': country}))
        .timeout(const Duration(seconds: 6));
    if (res.statusCode != 200) {
      throw HttpException('set location returned ${res.statusCode}: ${res.body}');
    }
  }

  Future<void> setSystemProxyMode(String mode) async {
    final url = endpoint.baseUri.replace(path: '/api/system-proxy');
    final res = await _client
        .post(url, headers: _headers, body: jsonEncode({'mode': mode}))
        .timeout(const Duration(seconds: 6));
    if (res.statusCode != 200) {
      throw HttpException('set system-proxy returned ${res.statusCode}: ${res.body}');
    }
  }

  /// Turns the proxy on (the app's connect button). Returns as soon as the
  /// core accepts the request; the connect itself runs async — poll
  /// [status] until phase == "running" (connected) or a connect_failure
  /// appears. Throws only when the core rejects the request itself.
  Future<void> powerOn() async {
    final url = endpoint.baseUri.replace(path: '/api/power');
    final res = await _client
        .post(url, headers: _headers, body: jsonEncode({'on': true}))
        .timeout(const Duration(seconds: 10));
    if (res.statusCode != 200) {
      throw HttpException('power on returned ${res.statusCode}: ${res.body}');
    }
  }

  Future<void> powerOff() async {
    final url = endpoint.baseUri.replace(path: '/api/power');
    final res = await _client
        .post(url, headers: _headers, body: jsonEncode({'on': false}))
        .timeout(const Duration(seconds: 6));
    if (res.statusCode != 200) {
      throw HttpException('power off returned ${res.statusCode}: ${res.body}');
    }
  }

  /// The server list, from GET /api/locations, normalized to the
  /// {key, label, ping_ms} shape the server picker reads. The first call
  /// can take a while: when the core has no list yet it fetches it from
  /// Mozilla first (up to the core's 15s API timeout), so this call gets
  /// 30s. Returns [] on any non-200 (callers retry).
  Future<List<Map<String, dynamic>>> fetchServers() async {
    final url = endpoint.baseUri.replace(path: '/api/locations');
    final res = await _client.get(url, headers: _headers).timeout(const Duration(seconds: 30));
    if (res.statusCode == 200) {
      final decoded = jsonDecode(res.body);
      // The endpoint wraps the list: {"locations": [...], "pinged_at": ...,
      // "firefox_version": ...}. (A bare list is accepted too, defensively.)
      final list = decoded is Map<String, dynamic> ? decoded['locations'] : decoded;
      if (list is List) {
        return list
            .whereType<Map<String, dynamic>>()
            .map((item) => <String, dynamic>{
                  'key': item['code'] as String? ?? '',
                  'label': item['name'] as String? ?? '',
                  'ping_ms': (item['ping_ms'] as num?)?.toInt() ?? -1,
                })
            // 'REC' is the core's recommended pseudo-location; the picker
            // already has its own "Auto Route · Recommended" row (key ''),
            // so drop the duplicate (and Mozilla's "Recomended" typo).
            .where((item) =>
                (item['key'] as String).isNotEmpty && item['key'] != 'REC')
            .toList();
      }
    }
    return [];
  }

  Future<bool> verifyReachability() async {
    final url = endpoint.baseUri.replace(path: '/api/reachability');
    try {
      final res = await _client.get(url, headers: _headers).timeout(const Duration(seconds: 12));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        return data['ok'] as bool? ?? false;
      }
    } catch (_) {}
    return false;
  }

  Future<List<String>> fetchLogs() async {
    final url = endpoint.baseUri.replace(path: '/api/logs');
    try {
      final res = await _client.get(url, headers: _headers).timeout(const Duration(seconds: 4));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (data is List) {
          return data.map((e) => e.toString()).toList();
        }
      }
    } catch (_) {}
    return [];
  }
}
