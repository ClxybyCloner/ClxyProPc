import 'package:flutter/material.dart';

import '../core/app_state.dart';
import '../core/app_updater.dart';
import '../core/models.dart';

/// Shows the update dialog: version + changelog, then Download & Install.
/// While installing, the dialog shows progress; on error it shows the reason.
/// On success the app exits and the updater script relaunches it.
Future<void> showUpdateDialog(
  BuildContext context,
  AppState state,
  UpdateInfo update,
) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (context) => _UpdateDialog(state: state, update: update),
  );
}

class _UpdateDialog extends StatefulWidget {
  final AppState state;
  final UpdateInfo update;

  const _UpdateDialog({required this.state, required this.update});

  @override
  State<_UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<_UpdateDialog> {
  bool _installing = false;
  double? _progress;
  String _status = '';
  String? _error;

  Future<void> _install() async {
    setState(() {
      _installing = true;
      _progress = 0;
      _status = 'Downloading v${widget.update.version}…';
      _error = null;
    });
    try {
      await AppUpdater.install(
        version: widget.update.version,
        downloadUrl: widget.update.downloadUrl,
        onBeforeExit: () async {
          if (widget.state.isConnected) await widget.state.disconnect();
          widget.state.coreProcess.stop();
        },
        onProgress: (progress, status) {
          if (!mounted) return;
          setState(() {
            _progress = progress;
            _status = status;
          });
        },
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _installing = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Update to v${widget.update.version}'),
      content: _error != null
          ? _buildError()
          : _installing
              ? _buildProgress()
              : _buildInfo(),
      actions: _error != null
          ? [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Close'),
              ),
              TextButton(
                onPressed: _install,
                child: const Text('Try Again'),
              ),
            ]
          : _installing
              ? null
              : [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Later'),
                  ),
                  TextButton(
                    onPressed: _install,
                    child: const Text('Download & Install'),
                  ),
                ],
    );
  }

  Widget _buildInfo() {
    final changelog = widget.update.changelog.trim();
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

  Widget _buildProgress() {
    return SizedBox(
      width: double.maxFinite,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LinearProgressIndicator(value: _progress),
          const SizedBox(height: 12),
          Text(_status, style: const TextStyle(fontSize: 13)),
        ],
      ),
    );
  }

  Widget _buildError() {
    return SizedBox(
      width: double.maxFinite,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('The update could not be installed:'),
          const SizedBox(height: 8),
          Text(_error!, style: const TextStyle(fontSize: 13)),
        ],
      ),
    );
  }
}
