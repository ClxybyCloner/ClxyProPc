import 'dart:convert';
import 'package:crypto/crypto.dart';

class DisplayServer {
  final String key;
  final String flagCode;
  final String title;
  final String city;
  final String countryName;
  int pingMs;

  DisplayServer({
    required this.key,
    required this.flagCode,
    required this.title,
    required this.city,
    required this.countryName,
    this.pingMs = -1,
  });

  factory DisplayServer.fromOption(String key, String label, {int pingMs = -1}) {
    final code = inferCountryCode(label, key);
    final fakeUri = fakeVlessUri(key, code, label);
    return DisplayServer(
      key: key,
      flagCode: code,
      title: label,
      city: fakeUri,
      countryName: label,
      pingMs: pingMs,
    );
  }
}

String inferCountryCode(String label, String key) {
  final l = label.toLowerCase();
  final k = key.toLowerCase();
  if (l.contains('germany') || k.contains('de') || l.contains('frankfurt')) return 'DE';
  if (l.contains('united states') || l.contains('usa') || k.contains('us') || l.contains('new york')) return 'US';
  if (l.contains('netherlands') || k.contains('nl') || l.contains('amsterdam')) return 'NL';
  if (l.contains('united kingdom') || l.contains('britain') || k.contains('gb') || k.contains('uk') || l.contains('london')) return 'GB';
  if (l.contains('france') || k.contains('fr') || l.contains('paris')) return 'FR';
  if (l.contains('ireland') || k.contains('ie') || l.contains('dublin')) return 'IE';
  if (l.contains('canada') || k.contains('ca') || l.contains('toronto')) return 'CA';
  if (l.contains('japan') || k.contains('jp') || l.contains('tokyo')) return 'JP';
  if (l.contains('singapore') || k.contains('sg')) return 'SG';
  if (l.contains('switzerland') || k.contains('ch') || l.contains('zurich')) return 'CH';
  if (l.contains('sweden') || k.contains('se') || l.contains('stockholm')) return 'SE';
  if (l.contains('finland') || k.contains('fi') || l.contains('helsinki')) return 'FI';
  if (l.contains('argentina') || l.contains('buenos aires')) return 'AR';
  if (l.contains('australia') || l.contains('sydney')) return 'AU';
  if (l.contains('south africa') || l.contains('johannesburg') || l.contains('cape town')) return 'ZA';
  return 'GLOBAL';
}

String fakeVlessUri(String key, String countryCode, String name) {
  final md5Hash = md5.convert(utf8.encode(key)).toString();
  final uuid = '${md5Hash.substring(0, 8)}-${md5Hash.substring(8, 12)}-4${md5Hash.substring(13, 16)}'
      '-8${md5Hash.substring(17, 20)}-${md5Hash.substring(20, 32)}';
  final cc = countryCode.toLowerCase().length == 2 ? countryCode.toLowerCase() : 'global';
  final tag = name.replaceAll(' ', '-');
  return 'vless://$uuid@$cc.clxy.pro:443?security=tls&encryption=none&type=tcp#$tag';
}

class UpdateInfo {
  final String version;
  final String url;
  final String changelog;
  final String downloadUrl;

  UpdateInfo({
    required this.version,
    required this.url,
    required this.changelog,
    required this.downloadUrl,
  });
}

class LogEntry {
  final DateTime timestamp;
  final String level;
  final String message;

  LogEntry({
    required this.timestamp,
    required this.level,
    required this.message,
  });

  @override
  String toString() {
    final timeStr =
        '${timestamp.hour.toString().padLeft(2, '0')}:${timestamp.minute.toString().padLeft(2, '0')}:${timestamp.second.toString().padLeft(2, '0')}';
    return '[$timeStr] [$level] $message';
  }
}
