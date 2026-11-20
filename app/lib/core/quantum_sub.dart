import 'dart:convert';
import 'dart:io';

import 'prefs.dart';

/// A MASQUE relay from the Quantum subscription: a display name and the
/// endpoint aether's `--peer` takes (host:port). The sub's WARP keys are
/// never used — aether dials with its own identity; only the relay
/// address comes from the sub.
class QuantumRelay {
  final String name;
  final String endpoint;

  const QuantumRelay({required this.name, required this.endpoint});
}

/// The subscription the relay list is fetched from (base64 list of
/// masque:// URIs, one per line). Fetched at runtime so the list stays
/// fresh; the last good copy is cached in user-data, and the bundled
/// list below covers a first run with no network.
const String quantumSubUrl =
    'https://amir-sub.ashkanfadaeii.workers.dev/sub';

/// Endpoints from the live sub (2026-11-21), deduped by endpoint, in
/// sub order. Only used when the sub cannot be fetched and no cache
/// exists yet.
const List<QuantumRelay> bundledQuantumRelays = [
  QuantumRelay(name: 'Amir 1', endpoint: '162.159.199.2:8095'),
  QuantumRelay(name: 'Amir 2', endpoint: '162.159.198.2:8095'),
  QuantumRelay(name: 'Amir 3', endpoint: '[2a14:7583:f764:64::a29f:c702]:8095'),
  QuantumRelay(name: 'Amir 4', endpoint: '[2a14:7583:f764:64::a29f:c602]:8095'),
  QuantumRelay(name: 'Amir 5', endpoint: 'us.v6.free.bestcf.eu.cc:8095'),
  QuantumRelay(name: 'Amir 6', endpoint: '[2606:4700:104::2]:8095'),
  QuantumRelay(name: 'Amir 7', endpoint: '[2606:4700:103::2]:8095'),
  QuantumRelay(name: 'Amir 10', endpoint: 'masque1.bestcf.eu.cc:443'),
  QuantumRelay(name: 'Amir 11', endpoint: 'masque2.bestcf.eu.cc:443'),
  QuantumRelay(name: 'Amir 14', endpoint: 'us.v6.free.bestcf.eu.cc:443'),
  QuantumRelay(name: 'Amir 15', endpoint: '[2602:fc59:b0:64::a29f:c601]:443'),
  QuantumRelay(name: 'Amir 16', endpoint: '162.159.198.160:443'),
  QuantumRelay(name: 'Amir 17', endpoint: '162.159.198.245:4443'),
  QuantumRelay(name: 'Amir 18', endpoint: '162.159.198.41:500'),
  QuantumRelay(name: 'Amir 19', endpoint: '162.159.198.96:4443'),
  QuantumRelay(name: 'Amir 20', endpoint: '162.159.198.171:500'),
];

/// Fetches the relay list: live sub first, cached copy on failure,
/// bundled list when nothing else exists.
Future<List<QuantumRelay>> fetchQuantumRelays() async {
  final cache = File(
      '${Prefs.userDataDir.path}${Platform.pathSeparator}quantum-sub.txt');
  try {
    final client = HttpClient();
    try {
      final req = await client
          .getUrl(Uri.parse(quantumSubUrl))
          .timeout(const Duration(seconds: 10));
      final res = await req.close().timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) {
        final raw = await res.transform(utf8.decoder).join();
        final relays = parseQuantumSub(raw);
        if (relays.isNotEmpty) {
          try {
            await cache.writeAsString(raw);
          } catch (_) {}
          return relays;
        }
      }
    } finally {
      client.close();
    }
  } catch (_) {}
  try {
    if (await cache.exists()) {
      final relays = parseQuantumSub(await cache.readAsString());
      if (relays.isNotEmpty) return relays;
    }
  } catch (_) {}
  return List<QuantumRelay>.from(bundledQuantumRelays);
}

/// Parses a base64 subscription body into relays, deduped by endpoint
/// (first name wins). Only the endpoint and the display name are kept.
List<QuantumRelay> parseQuantumSub(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return [];
  String decoded;
  try {
    var b64 = trimmed.replaceAll('-', '+').replaceAll('_', '/');
    b64 += '=' * ((4 - b64.length % 4) % 4);
    decoded = utf8.decode(base64.decode(b64));
  } catch (_) {
    return [];
  }
  final seen = <String>{};
  final relays = <QuantumRelay>[];
  for (final line in decoded.split('\n')) {
    final l = line.trim();
    if (!l.startsWith('masque://')) continue;
    final at = l.indexOf('@');
    if (at < 0) continue;
    final q = l.indexOf('?', at);
    final hash = l.indexOf('#', at);
    final end = q >= 0 ? q : (hash >= 0 ? hash : l.length);
    final endpoint = l.substring(at + 1, end).trim();
    if (endpoint.isEmpty || !seen.add(endpoint)) continue;
    var name = endpoint;
    if (hash >= 0 && hash + 1 < l.length) {
      try {
        name = Uri.decodeComponent(l.substring(hash + 1)).trim();
      } catch (_) {}
      if (name.isEmpty) name = endpoint;
    }
    relays.add(QuantumRelay(name: name, endpoint: endpoint));
  }
  return relays;
}

/// Splits an endpoint into (host, port). Handles IPv4/hostname
/// (host:port) and bracketed IPv6 ([::1]:port). Returns null when the
/// endpoint does not parse.
({String host, int port})? splitEndpoint(String endpoint) {
  final e = endpoint.trim();
  if (e.startsWith('[')) {
    final close = e.indexOf(']');
    if (close < 0) return null;
    final host = e.substring(1, close);
    final rest = e.substring(close + 1);
    if (!rest.startsWith(':')) return null;
    final port = int.tryParse(rest.substring(1));
    if (port == null) return null;
    return (host: host, port: port);
  }
  final colon = e.lastIndexOf(':');
  if (colon <= 0) return null;
  final port = int.tryParse(e.substring(colon + 1));
  if (port == null) return null;
  return (host: e.substring(0, colon), port: port);
}

/// Real TCP ping: time to open a socket to the relay, in ms, or -1 when
/// the relay does not answer in time.
Future<int> pingQuantumRelay(String endpoint,
    {int timeoutMs = 2000}) async {
  final parsed = splitEndpoint(endpoint);
  if (parsed == null) return -1;
  final sw = Stopwatch()..start();
  try {
    final socket = await Socket.connect(parsed.host, parsed.port,
        timeout: Duration(milliseconds: timeoutMs));
    socket.destroy();
    return sw.elapsedMilliseconds;
  } catch (_) {
    return -1;
  }
}
