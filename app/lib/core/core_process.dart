import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'core_api.dart';
import 'prefs.dart';

class CoreProcess {
  Process? _process;
  bool _running = false;
  CoreApi? _api;

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

  Future<CoreApi?> startAndConnect() async {
    final dataDir = Prefs.userDataDir.path;
    final tokenFile = File('$dataDir${Platform.pathSeparator}local-api.token');

    final exe = executablePath;
    if (!File(exe).existsSync()) {
      // If core is not built yet (e.g. running in test or before build), log and return null
      return null;
    }

    try {
      _process = await Process.start(
        exe,
        ['-app', '-data', dataDir],
        mode: ProcessStartMode.normal,
      );
      _running = true;

      // Pipe stderr for debugging
      _process!.stderr.transform(utf8.decoder).listen((line) {
        // Log core output
      });

      _process!.exitCode.then((code) {
        _running = false;
        _api = null;
      });

      // Poll for local-api.token up to 10 seconds
      for (int i = 0; i < 20; i++) {
        await Future.delayed(const Duration(milliseconds: 500));
        if (tokenFile.existsSync()) {
          final token = tokenFile.readAsStringSync().trim();
          if (token.isNotEmpty) {
            final endpoint = CoreEndpoint(Uri.parse('http://127.0.0.1:10820'), token);
            _api = CoreApi(endpoint);
            return _api;
          }
        }
      }
    } catch (_) {
      _running = false;
    }
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
