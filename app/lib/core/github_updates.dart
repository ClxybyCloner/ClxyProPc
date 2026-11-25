import 'dart:convert';
import 'package:http/http.dart' as http;
import 'models.dart';

class GithubUpdates {
  static const String currentVersion = '1.5.29';
  static const String repoOwner = 'ClxybyCloner';
  static const String repoName = 'ClxyProPc';

  static DateTime? _lastCheck;
  static UpdateInfo? _cachedUpdate;

  static Future<UpdateInfo?> check({bool force = false}) async {
    final now = DateTime.now();
    if (!force && _lastCheck != null && now.difference(_lastCheck!).inMinutes < 15) {
      return _cachedUpdate;
    }
    _lastCheck = now;

    try {
      final url = Uri.parse('https://api.github.com/repos/$repoOwner/$repoName/releases/latest');
      final res = await http.get(url, headers: {
        'Accept': 'application/vnd.github.v3+json',
        'User-Agent': 'ClxyPro-Windows/$currentVersion',
      }).timeout(const Duration(seconds: 8));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final tag = (data['tag_name'] as String? ?? '').replaceFirst('v', '').trim();
        final body = data['body'] as String? ?? '';
        final htmlUrl = data['html_url'] as String? ?? '';
        final downloadUrl = _windowsZipUrl(data, tag);

        if (_isNewer(tag, currentVersion)) {
          _cachedUpdate = UpdateInfo(
            version: tag,
            url: htmlUrl,
            changelog: body,
            downloadUrl: downloadUrl,
          );
          return _cachedUpdate;
        }
      }
    } catch (_) {}
    _cachedUpdate = null;
    return null;
  }

  /// The portable zip asset of the release, falling back to the standard
  /// release-download URL when the API response lists no matching asset.
  static String _windowsZipUrl(Map<String, dynamic> data, String tag) {
    final assets = data['assets'];
    if (assets is List) {
      for (final a in assets) {
        if (a is Map<String, dynamic>) {
          final name = a['name'] as String? ?? '';
          final url = a['browser_download_url'] as String? ?? '';
          if (name.endsWith('-Windows-x64.zip') && url.isNotEmpty) return url;
        }
      }
    }
    return 'https://github.com/$repoOwner/$repoName/releases/download/v$tag/ClxyPro-$tag-Windows-x64.zip';
  }

  static bool _isNewer(String latest, String current) {
    if (latest.isEmpty || current.isEmpty) return false;
    final lParts = latest.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    final cParts = current.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    for (int i = 0; i < 3; i++) {
      final l = i < lParts.length ? lParts[i] : 0;
      final c = i < cParts.length ? cParts[i] : 0;
      if (l > c) return true;
      if (l < c) return false;
    }
    return false;
  }
}
