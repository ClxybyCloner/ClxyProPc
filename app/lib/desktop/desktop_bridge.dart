import 'dart:io';
import 'package:flutter/services.dart';

class TrayItem {
  final int id;
  final String label;
  final bool enabled;
  final bool checked;
  final bool separator;
  final List<TrayItem> children;

  const TrayItem(
    this.id,
    this.label, {
    this.enabled = true,
    this.checked = false,
    this.children = const [],
  }) : separator = false;

  const TrayItem.separator()
      : id = 0,
        label = '',
        enabled = false,
        checked = false,
        separator = true,
        children = const [];

  Map<String, dynamic> toMap() => {
        'id': id,
        'label': label,
        'enabled': enabled,
        'checked': checked,
        'separator': separator,
        if (children.isNotEmpty)
          'children': [for (final c in children) c.toMap()],
      };
}

class DesktopBridge {
  static const _channel = MethodChannel('app/desktop');

  final VoidCallback onCloseRequested;
  final VoidCallback onTrayClicked;
  final void Function(int id) onTrayMenu;
  final VoidCallback onShown;

  DesktopBridge({
    required this.onCloseRequested,
    required this.onTrayClicked,
    required this.onTrayMenu,
    required this.onShown,
  }) {
    if (Platform.isWindows) {
      _channel.setMethodCallHandler((call) async {
        switch (call.method) {
          case 'closeRequested':
            onCloseRequested();
            break;
          case 'trayClicked':
            onTrayClicked();
            break;
          case 'trayMenu':
            onTrayMenu(call.arguments as int);
            break;
          case 'shown':
            onShown();
            break;
        }
      });
    }
  }

  Future<void> setTray({
    required String icon,
    required String tooltip,
    required List<TrayItem> items,
    bool rtl = false,
  }) async {
    if (!Platform.isWindows) return;
    try {
      await _channel.invokeMethod('setTray', {
        'icon': icon,
        'tooltip': tooltip,
        'rtl': rtl,
        'items': [for (final i in items) i.toMap()],
      });
    } catch (_) {}
  }

  Future<void> notify(String title, String body) async {
    if (!Platform.isWindows) return;
    try {
      await _channel.invokeMethod('notify', {'title': title, 'body': body});
    } catch (_) {}
  }

  Future<void> setAutostart({required bool enabled, required String command}) async {
    if (!Platform.isWindows) return;
    try {
      await _channel.invokeMethod('setAutostart', {
        'enabled': enabled,
        'command': command,
      });
    } catch (_) {}
  }

  Future<void> show() async {
    if (!Platform.isWindows) return;
    try {
      await _channel.invokeMethod('show');
    } catch (_) {}
  }

  Future<void> hide() async {
    if (!Platform.isWindows) return;
    try {
      await _channel.invokeMethod('hide');
    } catch (_) {}
  }

  Future<void> quit() async {
    if (!Platform.isWindows) return;
    try {
      await _channel.invokeMethod('quit');
    } catch (_) {}
  }
}
