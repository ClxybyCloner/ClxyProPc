import 'dart:io';

import 'package:archive/archive.dart';
import 'package:http/http.dart' as http;

/// Self-updater for the portable Windows build.
///
/// The running app cannot overwrite its own files (Windows locks the running
/// exe and its DLLs), so the update works in three steps:
///   1. Download the release zip and extract it to a staging folder in %TEMP%.
///   2. Write a small batch file next to the exe. It waits for the app and
///      the core to exit, copies the staged files over the app folder, and
///      relaunches the app. It never deletes the app folder itself, so
///      user-data\ (settings, session, core data) is untouched.
///   3. Stop the core, launch the batch detached, and exit.
///
/// This file is pure Dart (no Flutter import) so its download/extract/script
/// logic can be exercised with plain `dart`.
class AppUpdater {
  /// Name of the helper batch file, written next to the running exe.
  static const String scriptName = 'clxy-update.bat';

  /// Builds the updater batch script. [stageDir] is the folder the zip was
  /// extracted into (it contains the top-level `ClxyPro` folder, or the app
  /// files directly when the zip has no top folder).
  static String buildUpdaterScript({required String stageDir}) {
    return '''
@echo off
rem ClxyPro self-updater. Written by the app, run once, deletes itself.
rem Waits for the app and the core to exit, copies the staged files over
rem the app folder, relaunches. The app folder itself is never deleted,
rem so user-data\\ stays untouched.
set "APP_DIR=%~dp0"
set "STAGE=$stageDir"
if exist "%STAGE%\\ClxyPro\\ClxyPro.exe" (set "SRC=%STAGE%\\ClxyPro") else (set "SRC=%STAGE%")
:wait_app
tasklist /FI "IMAGENAME eq ClxyPro.exe" 2>nul | find /I "ClxyPro.exe" >nul
if not errorlevel 1 (timeout /t 1 /nobreak >nul & goto wait_app)
:wait_core
tasklist /FI "IMAGENAME eq clxy-vpn-core.exe" 2>nul | find /I "clxy-vpn-core.exe" >nul
if not errorlevel 1 (timeout /t 1 /nobreak >nul & goto wait_core)
set TRIES=0
:copy
xcopy /E /Y /R /Q "%SRC%\\*" "%APP_DIR%" >nul
if not errorlevel 1 goto copied
set /A TRIES+=1
if %TRIES% LSS 3 (timeout /t 2 /nobreak >nul & goto copy)
:copied
rmdir /S /Q "%STAGE%"
del /F /Q "%STAGE%.zip" 2>nul
start "" "%APP_DIR%ClxyPro.exe"
(goto) 2>nul & del "%~f0"
''';
  }

  /// Streams [url] to [destPath], reporting 0..1 progress (null when the
  /// server gives no content length). Throws on HTTP errors or truncation.
  static Future<File> downloadZip(
    String url,
    String destPath,
    void Function(double?, String) onProgress,
  ) async {
    final client = http.Client();
    try {
      final req = http.Request('GET', Uri.parse(url));
      final res = await client.send(req).timeout(const Duration(seconds: 30));
      if (res.statusCode != 200) {
        throw Exception('Download failed (HTTP ${res.statusCode})');
      }
      final total = res.contentLength ?? -1;
      final file = File(destPath);
      final sink = file.openWrite();
      var received = 0;
      await for (final chunk in res.stream) {
        sink.add(chunk);
        received += chunk.length;
        onProgress(
          total > 0 ? received / total : null,
          'Downloading… ${(received / 1048576).toStringAsFixed(1)} MB',
        );
      }
      await sink.close();
      if (total > 0 && received != total) {
        throw Exception('Download incomplete ($received of $total bytes)');
      }
      return file;
    } finally {
      client.close();
    }
  }

  /// Extracts [zipFile] into [destDir] and returns the directory holding the
  /// new app files (the `ClxyPro` subfolder when the zip has a top folder,
  /// otherwise [destDir] itself). Throws when ClxyPro.exe is not found.
  static Directory extractZip(File zipFile, String destDir) {
    final bytes = zipFile.readAsBytesSync();
    final archive = ZipDecoder().decodeBytes(bytes);
    final dest = Directory(destDir);
    if (dest.existsSync()) dest.deleteSync(recursive: true);
    dest.createSync(recursive: true);
    for (final file in archive) {
      final name = file.name.replaceAll('/', Platform.pathSeparator);
      // Never let a zip entry escape the staging folder.
      final parts = name.split(Platform.pathSeparator);
      if (parts.contains('..') || name.startsWith(Platform.pathSeparator)) {
        continue;
      }
      final out = File('${dest.path}${Platform.pathSeparator}$name');
      if (file.isFile) {
        out.parent.createSync(recursive: true);
        out.writeAsBytesSync(file.content as List<int>);
      } else {
        Directory(out.path).createSync(recursive: true);
      }
    }
    final nested = Directory('${dest.path}${Platform.pathSeparator}ClxyPro');
    if (File('${nested.path}${Platform.pathSeparator}ClxyPro.exe')
        .existsSync()) {
      return nested;
    }
    if (File('${dest.path}${Platform.pathSeparator}ClxyPro.exe').existsSync()) {
      return dest;
    }
    throw Exception('Downloaded zip has no ClxyPro.exe');
  }

  /// Downloads and stages the update, writes the updater script, then hands
  /// over: [onBeforeExit] must disconnect and stop the core; the app then
  /// exits and the script finishes the install and relaunches. Never returns
  /// on success (the process exits); throws on any failure before handover.
  static Future<void> install({
    required String version,
    required String downloadUrl,
    required Future<void> Function() onBeforeExit,
    required void Function(double?, String) onProgress,
  }) async {
    if (downloadUrl.isEmpty) {
      throw Exception('No download link for v$version');
    }
    final sep = Platform.pathSeparator;
    final temp = Directory.systemTemp.path;
    final stageDir = '$temp${sep}ClxyPro-update-$version';
    final zipPath = '$stageDir.zip';
    final exeDir = File(Platform.resolvedExecutable).parent.path;

    onProgress(0, 'Downloading v$version…');
    final zipFile = await downloadZip(downloadUrl, zipPath, onProgress);

    onProgress(null, 'Extracting…');
    extractZip(zipFile, stageDir);

    final script = File('$exeDir$sep$scriptName');
    script.writeAsStringSync(buildUpdaterScript(stageDir: stageDir));

    onProgress(null, 'Restarting ClxyPro…');
    await onBeforeExit();
    await Process.start(
      'cmd.exe',
      ['/c', 'start', '/min', '', script.path, stageDir],
      mode: ProcessStartMode.detached,
    );
    exit(0);
  }
}
