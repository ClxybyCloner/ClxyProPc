import 'dart:io';
import 'package:flutter/material.dart';
import 'components/bottom_nav_bar.dart';
import 'components/cosmic_background.dart';
import 'core/app_state.dart';
import 'core/prefs.dart';
import 'desktop/desktop_bridge.dart';
import 'screens/home_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/servers_screen.dart';
import 'screens/signin_screen.dart';
import 'theme/clxy_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Prefs.init();
  await AppState.instance.init();

  runApp(const ClxyProApp());
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
          } else {
            _bridge?.quit();
          }
        },
        onTrayClicked: () => _bridge?.show(),
        onShown: () => _bridge?.show(),
        onTrayMenu: (id) {
          switch (id) {
            case 1: // Show
              _bridge?.show();
              break;
            case 2: // Toggle Connect
              if (_appState.isConnected) {
                _appState.disconnect();
              } else {
                _bridge?.show();
                // If serial needed, showing window will guide the user
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

  void _updateTray() {
    if (_bridge == null) return;
    final isConn = _appState.isConnected;
    final tooltip = isConn ? 'ClxyPro - Protected' : 'ClxyPro - Disconnected';
    final iconName = isConn ? 'connected' : 'disconnected';

    _bridge!.setTray(
      icon: iconName,
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
            index: _appState.isQuantum ? 0 : _activeTab.index,
            children: [
              HomeScreen(
                state: _appState,
                onOpenServers: () {
                  setState(() => _activeTab = MainTab.servers);
                },
                onOpenSignIn: _openSignIn,
              ),
              if (!_appState.isQuantum)
                ServersScreen(
                  state: _appState,
                  onClose: () {
                    setState(() => _activeTab = MainTab.home);
                  },
                ),
              if (!_appState.isQuantum)
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
