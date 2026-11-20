import 'dart:async';
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
/// The download is owned by this class, not by any screen: closing the
/// update dialog never cancels it, and reopening the dialog re-attaches
/// to the live progress. A partial zip from an interrupted attempt resumes
/// with HTTP Range instead of starting over.
///
/// This file is pure Dart (no Flutter import) so its download/extract/script
/// logic can be exercised with plain `dart`.
class AppUpdater {
  /// Name of the helper batch file, written next to the running exe.
  static const String scriptName = 'clxy-update.bat';

  /// Snapshot of one version's update download. The UI reads the current
  /// snapshot with [downloadState] and listens to [downloadStream].
  static final _downloadStates = <String, UpdateDownloadState>{};
  static final _downloadFutures = <String, Future<File>>{};
  static final _downloadController =
      StreamController<UpdateDownloadState>.broadcast();

  static Stream<UpdateDownloadState> get downloadStream =>
      _downloadController.stream;

  static UpdateDownloadState? downloadState(String version) =>
      _downloadStates[version];

  static String zipPathFor(String version) =>
      '${Directory.systemTemp.path}${Platform.pathSeparator}ClxyPro-update-$version.zip';

  static String stageDirFor(String version) =>
      '${Directory.systemTemp.path}${Platform.pathSeparator}ClxyPro-update-$version';

  static void _emit(UpdateDownloadState state) {
    _downloadStates[state.version] = state;
    if (!_downloadController.isClosed) _downloadController.add(state);
  }

  /// Downloads [version]'s zip in the background (or joins the download
  /// already running for it). Safe to call from any screen; the download
  /// continues if the caller goes away. A zip already downloaded for this
  /// version is returned without downloading again.
  static Future<File> ensureDownloaded({
    required String version,
    required String downloadUrl,
  }) {
    final existing = _downloadFutures[version];
    if (existing != null) return existing;
    final done = _downloadStates[version];
    if (done != null && done.downloaded) {
      final zip = File(zipPathFor(version));
      if (zip.existsSync()) return Future.value(zip);
      _downloadStates.remove(version);
    }
    final future = _download(version, downloadUrl);
    _downloadFutures[version] = future;
    return future;
  }

  static Future<File> _download(String version, String downloadUrl) async {
    if (downloadUrl.isEmpty) {
      throw Exception('No download link for v$version');
    }
    _emit(UpdateDownloadState(
        version: version, progress: 0, status: 'Downloading v$version…'));
    try {
      final zip = await downloadZip(
        downloadUrl,
        zipPathFor(version),
        (progress, status) => _emit(UpdateDownloadState(
            version: version, progress: progress, status: status)),
      );
      _emit(UpdateDownloadState(
          version: version,
          progress: 1,
          status: 'Download complete — ready to install.',
          downloaded: true));
      return zip;
    } catch (e) {
      _downloadFutures.remove(version);
      _emit(UpdateDownloadState(
        version: version,
        status: 'Download failed',
        error: e.toString().replaceFirst('Exception: ', ''),
      ));
      rethrow;
    }
  }

  /// Installs a zip already fetched by [ensureDownloaded]: extracts it,
  /// writes the updater script, then hands over: [onBeforeExit] must
  /// disconnect and stop the core; the app then exits and the script
  /// finishes the install and relaunches. Never returns on success;
  /// throws (and reports the error in the download state) on failure.
  static Future<void> installDownloaded({
    required String version,
    required Future<void> Function() onBeforeExit,
  }) async {
    final zipFile = File(zipPathFor(version));
    if (!zipFile.existsSync()) {
      _downloadStates.remove(version);
      _downloadFutures.remove(version);
      throw Exception('The downloaded update is gone — download it again.');
    }
    final stageDir = stageDirFor(version);
    final sep = Platform.pathSeparator;
    final exeDir = File(Platform.resolvedExecutable).parent.path;
    try {
      _emit(UpdateDownloadState(
          version: version, status: 'Extracting…', installing: true));
      extractZip(zipFile, stageDir);

      final script = File('$exeDir$sep$scriptName');
      script.writeAsStringSync(buildUpdaterScript(stageDir: stageDir));

      _emit(UpdateDownloadState(
          version: version, status: 'Restarting ClxyPro…', installing: true));
      await onBeforeExit();
      await Process.start(
        'cmd.exe',
        ['/c', 'start', '/min', '', script.path, stageDir],
        mode: ProcessStartMode.detached,
      );
      exit(0);
    } catch (e) {
      _emit(UpdateDownloadState(
        version: version,
        status: 'Install failed',
        error: e.toString().replaceFirst('Exception: ', ''),
        downloaded: true,
      ));
      rethrow;
    }
  }

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
  /// server gives no content length). Resumes a partial file with HTTP
  /// Range instead of starting over; a file that is already complete is
  /// returned untouched. Throws on HTTP errors or truncation — the partial
  /// file stays, so the next attempt resumes where this one stopped.
  static Future<File> downloadZip(
    String url,
    String destPath,
    void Function(double?, String) onProgress,
  ) async {
    final client = http.Client();
    try {
      final file = File(destPath);
      var existing = 0;
      if (await file.exists()) existing = await file.length();
      final req = http.Request('GET', Uri.parse(url));
      if (existing > 0) req.headers['Range'] = 'bytes=$existing-';
      final res = await client.send(req).timeout(const Duration(seconds: 30));
      if (res.statusCode == 416) {
        // The range is past the end of the file: it is already complete.
        return file;
      }
      if (res.statusCode != 200 && res.statusCode != 206) {
        throw Exception('Download failed (HTTP ${res.statusCode})');
      }
      // 206 with a Range means the server resumes; 200 means it ignored
      // the Range, so the partial file is discarded and we start over.
      final resumed = res.statusCode == 206 && existing > 0;
      var total = res.contentLength ?? -1;
      if (resumed && total > 0) total += existing;
      final sink =
          file.openWrite(mode: resumed ? FileMode.append : FileMode.write);
      var received = resumed ? existing : 0;
      try {
        await for (final chunk in res.stream) {
          sink.add(chunk);
          received += chunk.length;
          onProgress(
            total > 0 ? received / total : null,
            'Downloading… ${(received / 1048576).toStringAsFixed(1)} MB',
          );
        }
      } finally {
        await sink.close();
      }
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

}

/// Snapshot of one version's update download, for the UI. The download
/// itself lives in [AppUpdater]; this is only the state the dialog shows.
class UpdateDownloadState {
  final String version;
  final double? progress;
  final String status;
  final String? error;
  final bool downloaded;
  final bool installing;

  const UpdateDownloadState({
    required this.version,
    this.progress,
    required this.status,
    this.error,
    this.downloaded = false,
    this.installing = false,
  });

  /// Downloading (not yet done, failed, or installing).
  bool get isDownloading => error == null && !downloaded && !installing;
}
