import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'core_api.dart';
import 'prefs.dart';

class CoreProcess {
  Process? _process;
  bool _running = false;
  CoreApi? _api;

  /// Why the last start attempt failed, in words the user can act on.
  /// Null while the core is connected or no attempt has failed yet.
  String? _lastError;
  String? get lastError => _lastError;

  // The core's own failure report: the first stderr line of a failed -app
  // run is "app-error: <code> <detail>" (see core/internal/desktop/app.go).
  String? _appError;
  int? _exitCode;
  // Last stderr lines, for failures without an app-error line.
  final List<String> _stderrTail = [];

  bool get isRunning => _running;
  CoreApi? get api => _api;

  static String get executablePath {
    final sep = Platform.pathSeparator;
    final exeDir = File(Platform.resolvedExecutable).parent.path;
    final path = '$exeDir${sep}core${sep}clxy-vpn-core.exe';
    if (File(path).existsSync()) return path;
    // Fallback if running from root during test
    final localPath = '..${sep}core${sep}cmd${sep}clxy-vpn-core${sep}clxy-vpn-core.exe';
    if (File(localPath).existsSync()) return localPath;
    return path;
  }

  String? _readToken(File tokenFile) {
    try {
      if (!tokenFile.existsSync()) return null;
      final token = tokenFile.readAsStringSync().trim();
      return token.isEmpty ? null : token;
    } catch (_) {
      return null;
    }
  }

  Future<CoreApi?> startAndConnect() async {
    if (_api != null) return _api;
    final dataDir = Prefs.userDataDir.path;
    final tokenFile = File('$dataDir${Platform.pathSeparator}local-api.token');
    // The daemon writes a fresh random token on every start, only once it
    // owns the dashboard address — so a token that predates this attempt
    // belongs to a dead run, not to the core we are starting.
    final previousToken = _readToken(tokenFile);

    final exe = executablePath;
    if (!File(exe).existsSync()) {
      _lastError =
          'Core file is missing. Your antivirus may have removed it — check its quarantine and restore core/clxy-vpn-core.exe, then restart the app.';
      return null;
    }

    if (_process == null || !_running) {
      try {
        final proc = await Process.start(
          exe,
          ['-app', '-data-dir', dataDir],
          mode: ProcessStartMode.normal,
        );
        _process = proc;
        _running = true;
        _appError = null;
        _exitCode = null;
        _stderrTail.clear();
        proc.stderr
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .listen((line) {
          final trimmed = line.trim();
          if (trimmed.isEmpty) return;
          if (trimmed.startsWith('app-error: ')) {
            _appError ??= trimmed.substring('app-error: '.length);
          } else {
            _stderrTail.add(trimmed);
            if (_stderrTail.length > 5) _stderrTail.removeAt(0);
          }
        });
        proc.exitCode.then((code) {
          // Only the current process may clear the state: an older spawn
          // that exits late must not drop a live connection.
          if (identical(_process, proc)) {
            _running = false;
            _process = null;
            _api = null;
            _exitCode = code;
          }
        });
      } catch (e) {
        _running = false;
        _process = null;
        _lastError = 'Could not start the core: $e';
        return null;
      }
    }

    // Poll for a fresh token up to 10 seconds. A retry while the core is
    // still starting reuses the running process instead of spawning
    // another copy (which would just exit as already_running).
    for (int i = 0; i < 20; i++) {
      await Future.delayed(const Duration(milliseconds: 500));
      final token = _readToken(tokenFile);
      if (token != null && token != previousToken) {
        final endpoint = CoreEndpoint(Uri.parse('http://127.0.0.1:10820'), token);
        _api = CoreApi(endpoint);
        _lastError = null;
        return _api;
      }
      if (!_running) {
        // The core died while starting; give its stderr a moment to arrive,
        // then read its own report of why.
        await Future.delayed(const Duration(milliseconds: 300));
        return _apiFromDeadCore(token);
      }
    }
    _lastError =
        'Core is taking too long to start. It may still be loading — please wait a moment and retry.';
    return null;
  }

  /// The spawned core exited before publishing a token. When another copy
  /// already serves the folder, the token on disk is that copy's live one,
  /// so the app can still connect to it; every other failure is reported.
  CoreApi? _apiFromDeadCore(String? token) {
    final report = _appError;
    if (report != null) {
      final space = report.indexOf(' ');
      final code = space < 0 ? report : report.substring(0, space);
      final detail = space < 0 ? '' : report.substring(space + 1);
      switch (code) {
        case 'already_running':
          if (token != null) {
            final endpoint =
                CoreEndpoint(Uri.parse('http://127.0.0.1:10820'), token);
            _api = CoreApi(endpoint);
            _lastError = null;
            return _api;
          }
          _lastError =
              'Another copy of ClxyPro is already running. Close it and restart the app.';
          return null;
        case 'dashboard_port_in_use':
          _lastError =
              'Another program is using $detail (the core\'s local address). Close it and restart the app.';
          return null;
        default: // start_failed
          _lastError = detail.isEmpty
              ? 'Core failed to start.'
              : 'Core failed to start: $detail';
          return null;
      }
    }
    final code = _exitCode;
    final tail = _stderrTail.isEmpty ? '' : ' ${_stderrTail.last}';
    _lastError = code == null
        ? 'Core stopped unexpectedly.$tail'
        : 'Core exited unexpectedly (code $code).$tail';
    return null;
  }

  void stop() {
    if (_process != null) {
      try {
        _process!.stdin.close();
        _process!.kill(ProcessSignal.sigterm);
      } catch (_) {}
      _process = null;
      _running = false;
      _api = null;
    }
  }
}
