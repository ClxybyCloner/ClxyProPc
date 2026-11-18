import 'dart:convert';
import 'dart:io';

class Prefs {
  static late Directory userDataDir;
  static late File settingsFile;
  static late File sessionFile;

  static Map<String, dynamic> _data = {};

  static Future<void> init([Directory? customDir]) async {
    if (customDir != null) {
      userDataDir = customDir;
    } else {
      final exePath = Platform.resolvedExecutable;
      final exeDir = File(exePath).parent;
      userDataDir = Directory('${exeDir.path}${Platform.pathSeparator}user-data');
    }

    if (!userDataDir.existsSync()) {
      userDataDir.createSync(recursive: true);
    }

    settingsFile = File('${userDataDir.path}${Platform.pathSeparator}settings.json');
    sessionFile = File('${userDataDir.path}${Platform.pathSeparator}session.txt');

    if (settingsFile.existsSync()) {
      try {
        final content = settingsFile.readAsStringSync();
        if (content.isNotEmpty) {
          _data = jsonDecode(content) as Map<String, dynamic>;
        }
      } catch (_) {
        _data = {};
      }
    } else {
      _data = {};
    }
  }

  static void _save() {
    try {
      settingsFile.writeAsStringSync(jsonEncode(_data));
    } catch (_) {}
  }

  // --- Getters & Setters ---

  static String get mode => _data['mode'] as String? ?? 'VPN';
  static set mode(String value) {
    _data['mode'] = value;
    _save();
  }

  static String get coreId => _data['coreId'] as String? ?? 'firefox';
  static set coreId(String value) {
    _data['coreId'] = value;
    _save();
  }

  static int get socksPort => _data['socksPort'] as int? ?? 1080;
  static set socksPort(int value) {
    _data['socksPort'] = value.clamp(1024, 65535);
    _save();
  }

  static int get httpPort => _data['httpPort'] as int? ?? 8080;
  static set httpPort(int value) {
    _data['httpPort'] = value.clamp(1024, 65535);
    _save();
  }

  static bool get shareLan => _data['shareLan'] as bool? ?? false;
  static set shareLan(bool value) {
    _data['shareLan'] = value;
    _save();
  }

  static bool get connectSound => _data['connectSound'] as bool? ?? true;
  static set connectSound(bool value) {
    _data['connectSound'] = value;
    _save();
  }

  static bool get autoRetry => _data['autoRetry'] as bool? ?? true;
  static set autoRetry(bool value) {
    _data['autoRetry'] = value;
    _save();
  }

  static bool get quantumUnlocked => _data['quantumUnlocked'] as bool? ?? false;
  static set quantumUnlocked(bool value) {
    _data['quantumUnlocked'] = value;
    _save();
  }

  static String get dnsProvider => _data['dnsProvider'] as String? ?? 'cloudflare';
  static set dnsProvider(String value) {
    _data['dnsProvider'] = value;
    _save();
  }

  static String get customDns => _data['customDns'] as String? ?? '';
  static set customDns(String value) {
    _data['customDns'] = value;
    _save();
  }

  static int get mtu => _data['mtu'] as int? ?? 1500;
  static set mtu(int value) {
    _data['mtu'] = value;
    _save();
  }

  static bool get bypassLan => _data['bypassLan'] as bool? ?? true;
  static set bypassLan(bool value) {
    _data['bypassLan'] = value;
    _save();
  }

  static bool get bypassDomestic => _data['bypassDomestic'] as bool? ?? false;
  static set bypassDomestic(bool value) {
    _data['bypassDomestic'] = value;
    _save();
  }

  static bool get blockAds => _data['blockAds'] as bool? ?? false;
  static set blockAds(bool value) {
    _data['blockAds'] = value;
    _save();
  }

  static String get tlsFragmentMode => _data['tlsFragmentMode'] as String? ?? 'off';
  static set tlsFragmentMode(String value) {
    _data['tlsFragmentMode'] = value;
    _save();
  }

  static bool get showSpeedInNotification => _data['showSpeedInNotification'] as bool? ?? true;
  static set showSpeedInNotification(bool value) {
    _data['showSpeedInNotification'] = value;
    _save();
  }

  static String get language => _data['language'] as String? ?? 'en';
  static set language(String value) {
    _data['language'] = value;
    _save();
  }

  static bool get autoStart => _data['autoStart'] as bool? ?? false;
  static set autoStart(bool value) {
    _data['autoStart'] = value;
    _save();
  }

  static bool get closeToTray => _data['closeToTray'] as bool? ?? true;
  static set closeToTray(bool value) {
    _data['closeToTray'] = value;
    _save();
  }

  static List<String> get vpnExcludedApps {
    final list = _data['vpnExcludedApps'];
    if (list is List) {
      return list.map((e) => e.toString()).toList();
    }
    return [];
  }
  static set vpnExcludedApps(List<String> value) {
    _data['vpnExcludedApps'] = value;
    _save();
  }

  static String get lastNotifiedUpdate => _data['lastNotifiedUpdate'] as String? ?? '';
  static set lastNotifiedUpdate(String value) {
    _data['lastNotifiedUpdate'] = value;
    _save();
  }

  static String server(String coreId) => _data['server_$coreId'] as String? ?? '';
  static String serverLabel(String coreId) => _data['serverLabel_$coreId'] as String? ?? '';
  static void setServer(String coreId, String key, String label) {
    _data['server_$coreId'] = key;
    _data['serverLabel_$coreId'] = label;
    _save();
  }

  // FxA Session
  static String get sessionToken {
    if (sessionFile.existsSync()) {
      return sessionFile.readAsStringSync().trim();
    }
    return _data['sessionToken'] as String? ?? '';
  }

  static set sessionToken(String token) {
    _data['sessionToken'] = token;
    _save();
    try {
      sessionFile.writeAsStringSync(token);
    } catch (_) {}
  }

  static String get sessionEmail => _data['sessionEmail'] as String? ?? '';
  static set sessionEmail(String email) {
    _data['sessionEmail'] = email;
    _save();
  }

  static String get sessionQuota => _data['sessionQuota'] as String? ?? '';
  static set sessionQuota(String quota) {
    _data['sessionQuota'] = quota;
    _save();
  }

  static void clearSession() {
    _data.remove('sessionToken');
    _data.remove('sessionEmail');
    _data.remove('sessionQuota');
    _save();
    if (sessionFile.existsSync()) {
      try {
        sessionFile.deleteSync();
      } catch (_) {}
    }
  }

  static String get socksAddress => '127.0.0.1:$socksPort';
  static String get httpAddress => '127.0.0.1:$httpPort';
}
