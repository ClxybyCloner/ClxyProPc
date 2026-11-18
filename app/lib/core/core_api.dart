import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

class CoreEndpoint {
  final Uri baseUri;
  final String token;

  const CoreEndpoint(this.baseUri, this.token);
}

class CoreStatus {
  final bool running;
  final bool connected;
  final bool busy;
  final String mode; // 'vpn' or 'proxy'
  final String core; // 'firefox' or 'aether'
  final String exit;
  final String exitIp;
  final int latencyMs;
  final int rxBytes;
  final int txBytes;
  final int uptimeSec;
  final String? error;

  CoreStatus({
    required this.running,
    required this.connected,
    this.busy = false,
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

  factory CoreStatus.fromJson(Map<String, dynamic> json) {
    return CoreStatus(
      running: json['running'] as bool? ?? false,
      connected: json['connected'] as bool? ?? false,
      busy: json['busy'] as bool? ?? false,
      mode: (json['mode'] as String? ?? 'vpn').toLowerCase(),
      core: (json['core'] as String? ?? 'firefox').toLowerCase(),
      exit: json['exit'] as String? ?? '',
      exitIp: json['exit_ip'] as String? ?? json['ip'] as String? ?? '',
      latencyMs: json['latency_ms'] as int? ?? json['latency'] as int? ?? -1,
      rxBytes: json['rx_bytes'] as int? ?? json['rx'] as int? ?? 0,
      txBytes: json['tx_bytes'] as int? ?? json['tx'] as int? ?? 0,
      uptimeSec: json['uptime_sec'] as int? ?? json['uptime'] as int? ?? 0,
      error: json['error'] as String?,
    );
  }
}

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

  Future<void> connect({
    required String mode,
    required String core,
    String server = '',
  }) async {
    final url = endpoint.baseUri.replace(path: '/api/connect');
    final body = jsonEncode({
      'mode': mode.toLowerCase(),
      'core': core.toLowerCase(),
      'server': server,
    });
    final res = await _client.post(url, headers: _headers, body: body).timeout(const Duration(seconds: 10));
    if (res.statusCode != 200 && res.statusCode != 204) {
      throw HttpException('connect returned ${res.statusCode}: ${res.body}');
    }
  }

  Future<void> disconnect() async {
    final url = endpoint.baseUri.replace(path: '/api/disconnect');
    final res = await _client.post(url, headers: _headers).timeout(const Duration(seconds: 6));
    if (res.statusCode != 200 && res.statusCode != 204) {
      throw HttpException('disconnect returned ${res.statusCode}: ${res.body}');
    }
  }

  Future<List<Map<String, dynamic>>> fetchServers(String core) async {
    final url = endpoint.baseUri.replace(
      path: '/api/servers',
      queryParameters: {'core': core.toLowerCase()},
    );
    final res = await _client.get(url, headers: _headers).timeout(const Duration(seconds: 8));
    if (res.statusCode == 200) {
      final list = jsonDecode(res.body);
      if (list is List) {
        return list.map((e) => e as Map<String, dynamic>).toList();
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
