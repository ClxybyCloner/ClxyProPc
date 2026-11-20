import 'package:flutter/material.dart';

import '../core/app_state.dart';
import '../core/app_updater.dart';
import '../core/models.dart';

/// Shows the update dialog: version + changelog, then Download.
/// The download runs in [AppUpdater], not in this dialog: closing the
/// dialog never cancels it, and reopening re-attaches to the live
/// progress. When the zip is ready, Install & Restart finishes the job
/// (the app exits and the updater script relaunches it).
Future<void> showUpdateDialog(
  BuildContext context,
  AppState state,
  UpdateInfo update,
) {
  return showDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (context) => _UpdateDialog(state: state, update: update),
  );
}

class _UpdateDialog extends StatelessWidget {
  final AppState state;
  final UpdateInfo update;

  const _UpdateDialog({required this.state, required this.update});

  Future<void> _download() async {
    try {
      await AppUpdater.ensureDownloaded(
        version: update.version,
        downloadUrl: update.downloadUrl,
      );
    } catch (_) {
      // The failure is in the download state the dialog shows.
    }
  }

  Future<void> _install() async {
    try {
      await AppUpdater.installDownloaded(
        version: update.version,
        onBeforeExit: () async {
          if (state.isConnected) await state.disconnect();
          state.coreProcess.stop();
        },
      );
    } catch (_) {
      // The failure is in the download state the dialog shows.
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<UpdateDownloadState>(
      stream: AppUpdater.downloadStream,
      initialData: AppUpdater.downloadState(update.version),
      builder: (context, snapshot) {
        var dl = snapshot.data;
        if (dl == null || dl.version != update.version) {
          dl = AppUpdater.downloadState(update.version);
        }
        final installing = dl?.installing == true;
        return PopScope(
          // The download may be left running; the install itself
          // (extract + restart) is the point of no return.
          canPop: !installing,
          child: AlertDialog(
            title: Text('Update to v${update.version}'),
            content: _buildContent(dl),
            actions: _buildActions(context, dl),
          ),
        );
      },
    );
  }

  Widget _buildContent(UpdateDownloadState? dl) {
    if (dl?.error != null) return _buildError(dl!.error!);
    if (dl?.downloaded == true && dl?.installing != true) {
      return const SizedBox(
        width: double.maxFinite,
        child: Text('Download complete — ready to install.'),
      );
    }
    if (dl != null) return _buildProgress(dl);
    return _buildInfo();
  }

  List<Widget>? _buildActions(BuildContext context, UpdateDownloadState? dl) {
    final pop = () => Navigator.of(context).pop();
    if (dl?.error != null) {
      return [
        TextButton(onPressed: pop, child: const Text('Close')),
        TextButton(
          onPressed: dl!.downloaded ? _install : _download,
          child: const Text('Try Again'),
        ),
      ];
    }
    if (dl?.installing == true) return null;
    if (dl?.downloaded == true) {
      return [
        TextButton(onPressed: pop, child: const Text('Close')),
        TextButton(onPressed: _install, child: const Text('Install & Restart')),
      ];
    }
    if (dl != null) {
      return [
        TextButton(onPressed: pop, child: const Text('Close')),
      ];
    }
    return [
      TextButton(onPressed: pop, child: const Text('Later')),
      TextButton(onPressed: _download, child: const Text('Download')),
    ];
  }

  Widget _buildInfo() {
    final changelog = update.changelog.trim();
    return SizedBox(
      width: double.maxFinite,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('A new version of ClxyPro is available.'),
          const SizedBox(height: 12),
          if (changelog.isNotEmpty)
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 200),
              child: SingleChildScrollView(
                child: Text(changelog, style: const TextStyle(fontSize: 13)),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildProgress(UpdateDownloadState dl) {
    return SizedBox(
      width: double.maxFinite,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LinearProgressIndicator(value: dl.progress),
          const SizedBox(height: 12),
          Text(dl.status, style: const TextStyle(fontSize: 13)),
          if (dl.isDownloading) ...[
            const SizedBox(height: 8),
            const Text(
              'You can close this — the download keeps going.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildError(String error) {
    return SizedBox(
      width: double.maxFinite,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('The update could not be installed:'),
          const SizedBox(height: 8),
          Text(error, style: const TextStyle(fontSize: 13)),
        ],
      ),
    );
  }
}
