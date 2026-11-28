import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'components/bottom_nav_bar.dart';
import 'components/cosmic_background.dart';
import 'core/app_state.dart';
import 'core/prefs.dart';
import 'desktop/desktop_bridge.dart';
import 'screens/home_screen.dart';
import 'screens/logs_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/quantum_serial_dialog.dart';
import 'screens/servers_screen.dart';
import 'screens/signin_screen.dart';
import 'theme/clxy_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Prefs.init();
  await AppState.instance.init();

  // This is a GUI executable: nothing reaches a console, so Flutter errors
  // are logged to user-data/flutter.log instead of vanishing, and a build
  // failure shows its message on screen (ErrorWidget) instead of a blank
  // gray window.
  FlutterError.onError = (details) {
    _logFlutterError('FlutterError', details.exception, details.stack);
    FlutterError.presentError(details);
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    _logFlutterError('AsyncError', error, stack);
    return true;
  };
  ErrorWidget.builder = (details) => _FlutterErrorBox(details: details);

  runApp(const ClxyProApp());
}

void _logFlutterError(String kind, Object error, StackTrace? stack) {
  try {
    final file = File(
        '${Prefs.userDataDir.path}${Platform.pathSeparator}flutter.log');
    final stamp = DateTime.now().toIso8601String();
    file.writeAsStringSync('[$stamp] $kind: $error\n${stack ?? ''}\n',
        mode: FileMode.append);
  } catch (_) {}
}

/// Shown in place of a widget whose build failed, so a rendering error
/// is visible (and screenshottable) instead of a blank gray window.
class _FlutterErrorBox extends StatelessWidget {
  const _FlutterErrorBox({required this.details});
  final FlutterErrorDetails details;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF070B19),
      padding: const EdgeInsets.all(16.0),
      alignment: Alignment.center,
      child: SingleChildScrollView(
        child: Text(
          'Something went wrong:\n\n${details.exception}',
          style: const TextStyle(color: Colors.white, fontSize: 12.0),
        ),
      ),
    );
  }
}

class ClxyProApp extends StatelessWidget {
  const ClxyProApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ClxyPro',
      debugShowCheckedModeBanner: false,
      theme: ClxyTheme.darkTheme,
      home: const MainShell(),
    );
  }
}

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  final AppState _appState = AppState.instance;
  MainTab _activeTab = MainTab.home;
  DesktopBridge? _bridge;

  @override
  void initState() {
    super.initState();
    _appState.addListener(_onStateChanged);
    _initDesktop();
  }

  void _initDesktop() {
    if (Platform.isWindows) {
      _bridge = DesktopBridge(
        onCloseRequested: () {
          if (Prefs.closeToTray) {
            _bridge?.hide();
            // The window is gone but the app lives on in the tray: pause
            // animations and slow the pollers (AppState.setWindowHidden).
            AppState.instance.setWindowHidden(true);
          } else {
            _bridge?.quit();
          }
        },
        onTrayClicked: () {
          AppState.instance.setWindowHidden(false);
          _bridge?.show();
        },
        onShown: () {
          AppState.instance.setWindowHidden(false);
          _bridge?.show();
        },
        onTrayMenu: (id) {
          switch (id) {
            case 1: // Show
              AppState.instance.setWindowHidden(false);
              _bridge?.show();
              break;
            case 2: // Toggle Connect
              if (_appState.isConnected) {
                _appState.disconnect();
              } else if (_appState.isConnecting) {
                _bridge?.show();
              } else if (_readyToConnect()) {
                // Quick-connect in the background, like the Android tile:
                // the window only opens when the user must do something
                // first. The serial callback cannot fire here (readiness
                // already checked it); it only aborts if state changed.
                _appState.toggleConnect(onNeedSerial: (_) async => false);
              } else {
                _bridge?.show();
              }
              break;
            case 3: // Quit
              _bridge?.quit();
              break;
          }
        },
      );
      _updateTray();
    }
  }

  /// True when a background connect can proceed without the user. The only
  /// step that needs the user before connecting is the serial (one per
  /// engine); this build has no consent step, and sign-in is not a
  /// connect prerequisite (the home button connects the same way without
  /// a session).
  bool _readyToConnect() {
    if (_appState.isQuantum && !Prefs.quantumUnlocked) return false;
    if (_appState.isHyper && !Prefs.hyperUnlocked) return false;
    return true;
  }

  /// Shows the serial dialog (same as the home screen's prompt). Used
  /// after sign-in: Android asks the serial at connect, after sign-in.
  Future<bool> _promptSerial(bool forHyper) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => QuantumSerialDialog(
        forHyper: forHyper,
        onDismiss: () => Navigator.of(ctx).pop(false),
        onActivated: () => Navigator.of(ctx).pop(true),
      ),
    );
    return result ?? false;
  }

  void _updateTray() {
    if (_bridge == null) return;
    final isConn = _appState.isConnected;
    final tooltip = isConn ? 'ClxyPro - Protected' : 'ClxyPro - Disconnected';

    _bridge!.setTray(
      icon: _trayIconPath(isConn),
      tooltip: tooltip,
      items: [
        const TrayItem(1, 'Open ClxyPro'),
        const TrayItem.separator(),
        TrayItem(2, isConn ? 'Disconnect' : 'Connect'),
        const TrayItem.separator(),
        const TrayItem(3, 'Quit'),
      ],
    );
  }

  /// Absolute path of the tray .ico for the current state. The icons ship in
  /// the bundle at data/flutter_assets/assets/tray/ (on.ico = connected,
  /// off.ico = disconnected). The old code passed the bare names
  /// 'connected'/'disconnected', which match no file — LoadImageW failed,
  /// no icon was ever added to the tray, and the app was invisible there
  /// (no way to see it or Quit it) while still running. If the .ico is
  /// ever missing, fall back to the exe itself: LoadImageW reads the
  /// icon embedded in it.
  String _trayIconPath(bool connected) {
    final exeDir = File(Platform.resolvedExecutable).parent.path;
    final sep = Platform.pathSeparator;
    final icon = File('$exeDir${sep}data${sep}flutter_assets${sep}assets'
        '${sep}tray${sep}${connected ? 'on' : 'off'}.ico');
    if (icon.existsSync()) return icon.path;
    return Platform.resolvedExecutable;
  }

  void _onStateChanged() {
    _updateTray();
    setState(() {});
  }

  @override
  void dispose() {
    _appState.removeListener(_onStateChanged);
    super.dispose();
  }

  void _openSignIn() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SignInScreen(
          state: _appState,
          onDone: () {
            Navigator.of(context).pop();
            setState(() {});
            // Android connects right after sign-in (MainActivity toggle{}):
            // sign-in first, then the serial at connect. Sign-in only
            // exists in Hyper mode, so the dialog here is always the
            // Hyper one.
            if (_appState.status == VpnStatus.idle) {
              _appState.connect(onNeedSerial: _promptSerial);
            }
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ClxyCosmicBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: IndexedStack(
            // All four tabs for both engines (v1.5.31): Profile and
            // Logs are no longer Hyper-only (Android rc6 parity).
            index: _activeTab.index,
            children: [
              HomeScreen(
                state: _appState,
                onOpenServers: () {
                  setState(() => _activeTab = MainTab.servers);
                },
                onOpenSignIn: _openSignIn,
              ),
              ServersScreen(
                state: _appState,
                onClose: () {
                  setState(() => _activeTab = MainTab.home);
                },
              ),
              LogsScreen(
                state: _appState,
                onClose: () {
                  setState(() => _activeTab = MainTab.home);
                },
              ),
              ProfileScreen(
                state: _appState,
                onOpenSignIn: _openSignIn,
              ),
            ],
          ),
        ),
        bottomNavigationBar: ClxyBottomNavBar(
          activeTab: _activeTab,
          isQuantum: _appState.isQuantum,
          onSelectTab: (tab) {
            setState(() => _activeTab = tab);
          },
        ),
      ),
    );
  }
}
