import 'dart:convert';
import 'dart:io';

/// What installing or removing the TUN service came to.
sealed class TunServiceResult {
  const TunServiceResult();
}

class TunServiceDone extends TunServiceResult {
  const TunServiceDone();
}

/// The user declined the administrator prompt.
class TunServiceCancelled extends TunServiceResult {
  const TunServiceCancelled();
}

class TunServiceFailed extends TunServiceResult {
  const TunServiceFailed(this.error);

  /// Why, in the program's English.
  final String error;
}

/// The TUN mode's service (core/cmd/clxy-vpn-tun), beside the core: its
/// install command asks for administrator rights itself (one prompt:
/// Windows' UAC), installs the service, and starts it; its uninstall
/// command removes it, through the running service without a prompt. The
/// core then uses the service; the app only installs it.
///
/// Ported from Arman's TunService (arman-vpn-client/app/lib/core/
/// tun_service.dart). The clone dropped this whole file, so the TUN
/// service was NEVER installed: the core's tunSync dialled a service that
/// did not exist (TunCodeMissing, retried silently every 2s), the app
/// never read the TUN status, and VPN mode showed "Connected & Protected"
/// while no traffic was routed at all. The daemon's own TunStatus comment
/// says it: "the app installs it before it turns the TUN mode on".
class TunService {
  TunService(this.executable);

  /// From the core's executable: the service is in the same folder.
  factory TunService.besideCore(String coreExecutable) => TunService(
    '${File(coreExecutable).parent.path}${Platform.pathSeparator}'
    'clxy-vpn-tun${Platform.isWindows ? '.exe' : ''}',
  );

  final String executable;

  /// [prompt] is the reason macOS' administrator prompt shows, in the
  /// user's language; Windows names the program itself.
  Future<TunServiceResult> install({String? prompt}) =>
      _run('install', prompt);

  Future<TunServiceResult> uninstall({String? prompt}) =>
      _run('uninstall', prompt);

  /// Exit status 0 done, 3 the prompt declined, anything else failed with
  /// the reason on the standard error (core/cmd/clxy-vpn-tun).
  Future<TunServiceResult> _run(String command, String? prompt) async {
    if (!File(executable).existsSync()) {
      return TunServiceFailed('$executable is missing');
    }
    try {
      final r = await Process.run(
        executable,
        [
          command,
          if (Platform.isMacOS && prompt != null) ...['-prompt', prompt],
        ],
        stderrEncoding: utf8,
        stdoutEncoding: utf8,
      );
      return switch (r.exitCode) {
        0 => const TunServiceDone(),
        3 => const TunServiceCancelled(),
        _ => TunServiceFailed(
          _firstLine(r.stderr as String? ?? '', 'exit code ${r.exitCode}'),
        ),
      };
    } on ProcessException catch (e) {
      return TunServiceFailed(e.message);
    }
  }

  static String _firstLine(String text, String fallback) {
    final line = text.trim().split('\n').first.trim();
    return line.replaceFirst(RegExp(r'^clxy-vpn-tun:\s*'), '').isEmpty
        ? fallback
        : line.replaceFirst(RegExp(r'^clxy-vpn-tun:\s*'), '');
  }
}
