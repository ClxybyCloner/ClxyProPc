import 'dart:io';
import 'package:flutter/material.dart';
import '../components/settings_rows.dart';
import '../core/app_state.dart';
import '../core/prefs.dart';
import '../theme/clxy_colors.dart';
import 'logs_screen.dart';
import 'split_tunnel_picker.dart';
import 'update_dialog.dart';

class ProfileScreen extends StatefulWidget {
  final AppState state;
  final VoidCallback onOpenSignIn;

  const ProfileScreen({
    super.key,
    required this.state,
    required this.onOpenSignIn,
  });

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  void _openLogs() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => LogsScreen(state: widget.state)),
    );
  }

  void _openSplitTunnel() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const SplitTunnelPicker()),
    );
  }

  void _showPortDialog(String title, int currentPort, ValueChanged<int> onSave) {
    final ctrl = TextEditingController(text: currentPort.toString());
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ClxyColors.cardSurface,
        title: Text(title, style: const TextStyle(color: ClxyColors.textPrimary, fontSize: 16)),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.number,
          style: const TextStyle(color: ClxyColors.textPrimary),
          decoration: const InputDecoration(
            hintText: '1024 - 65535',
            hintStyle: TextStyle(color: ClxyColors.textDim),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel', style: TextStyle(color: ClxyColors.textMuted)),
          ),
          ElevatedButton(
            onPressed: () {
              final port = int.tryParse(ctrl.text.trim());
              if (port != null && port >= 1024 && port <= 65535) {
                onSave(port);
                setState(() {});
                Navigator.of(ctx).pop();
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: ClxyColors.blueDeep),
            child: const Text('Save', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _showDnsDialog() {
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: ClxyColors.cardSurface,
          title: const Text('DNS Provider', style: TextStyle(color: ClxyColors.textPrimary, fontSize: 16)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildDnsRadio('cloudflare', 'Cloudflare (1.1.1.1)', setDialogState),
              _buildDnsRadio('google', 'Google (8.8.8.8)', setDialogState),
              _buildDnsRadio('quad9', 'Quad9 (9.9.9.9)', setDialogState),
              _buildDnsRadio('custom', 'Custom DNS', setDialogState),
            ],
          ),
          actions: [
            ElevatedButton(
              onPressed: () {
                setState(() {});
                Navigator.of(ctx).pop();
              },
              style: ElevatedButton.styleFrom(backgroundColor: ClxyColors.blueDeep),
              child: const Text('Close', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDnsRadio(String val, String label, StateSetter setDialogState) {
    return RadioListTile<String>(
      value: val,
      groupValue: Prefs.dnsProvider,
      title: Text(label, style: const TextStyle(color: ClxyColors.textPrimary, fontSize: 13)),
      activeColor: ClxyColors.cyanGlow,
      onChanged: (newVal) {
        if (newVal != null) {
          Prefs.dnsProvider = newVal;
          setDialogState(() {});
        }
      },
    );
  }

  void _showAboutDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ClxyColors.cardSurface,
        title: const Text('About ClxyPro', style: TextStyle(color: ClxyColors.textPrimary, fontSize: 16)),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('ClxyPro for Windows (Portable)', style: TextStyle(color: ClxyColors.textPrimary, fontWeight: FontWeight.bold)),
            SizedBox(height: 4),
            Text('Version 1.5.17', style: TextStyle(color: ClxyColors.cyanText, fontSize: 13)),
            SizedBox(height: 12),
            Text(
              'A completely self-contained, portable Windows VPN and Proxy client matching the Android ClxyPro stack. Dual-engine architecture featuring CLXY Hyper (Firefox MASQUE) and CLXY Quantum (Aether Direct).',
              style: TextStyle(color: ClxyColors.textMuted, fontSize: 12, height: 1.4),
            ),
            SizedBox(height: 12),
            Text('Portable directory:', style: TextStyle(color: ClxyColors.textDim, fontSize: 11)),
            Text('All configuration and credentials stored inside user-data\\', style: TextStyle(color: ClxyColors.textMuted, fontSize: 11)),
          ],
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(),
            style: ElevatedButton.styleFrom(backgroundColor: ClxyColors.blueDeep),
            child: const Text('OK', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 12.0),
      children: [
        // Top Header
        const Text(
          'Settings & Profile',
          style: TextStyle(
            color: ClxyColors.textPrimary,
            fontSize: 18.0,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12.0),

        // Protocol Status Banner
        Container(
          padding: const EdgeInsets.all(14.0),
          decoration: BoxDecoration(
            color: ClxyColors.cardSurface,
            borderRadius: BorderRadius.circular(12.0),
            border: Border.all(color: ClxyColors.glassBorder, width: 1.0),
          ),
          child: Row(
            children: [
              Container(
                width: 38.0,
                height: 38.0,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: widget.state.isQuantum
                      ? ClxyColors.quantumPurple.withOpacity(0.2)
                      : ClxyColors.cyanGlow.withOpacity(0.2),
                ),
                child: Center(
                  child: widget.state.isQuantum
                      ? const Text('🪐', style: TextStyle(fontSize: 18.0))
                      : const Icon(Icons.bolt_rounded, color: ClxyColors.cyanText, size: 22.0),
                ),
              ),
              const SizedBox(width: 12.0),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.state.isQuantum ? 'CLXY Quantum Engine' : 'CLXY Hyper Engine',
                      style: const TextStyle(
                        color: ClxyColors.textPrimary,
                        fontSize: 14.0,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 2.0),
                    Text(
                      widget.state.isQuantum
                          ? 'Aether direct anycast mesh · zero-log MASQUE'
                          : 'Firefox HTTP/3 MASQUE direct transport',
                      style: const TextStyle(
                        color: ClxyColors.textMuted,
                        fontSize: 11.0,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 16.0),
        _buildSectionHeader('General'),
        const SizedBox(height: 8.0),

        SettingSwitchRow(
          title: 'Sound Effects',
          subtitle: 'Play audio notification on connect',
          checked: Prefs.connectSound,
          onCheckedChange: (val) {
            setState(() => Prefs.connectSound = val);
          },
        ),
        const SizedBox(height: 8.0),

        SettingSwitchRow(
          title: 'Auto-Retry Connection',
          subtitle: 'Automatically reconnect if connection drops',
          checked: Prefs.autoRetry,
          onCheckedChange: (val) {
            setState(() => Prefs.autoRetry = val);
          },
        ),
        const SizedBox(height: 8.0),

        SettingSwitchRow(
          title: 'Close to System Tray',
          subtitle: 'Keep running in background when window is closed',
          checked: Prefs.closeToTray,
          onCheckedChange: (val) {
            setState(() => Prefs.closeToTray = val);
          },
        ),

        const SizedBox(height: 16.0),
        _buildSectionHeader('Connection & Ports'),
        const SizedBox(height: 8.0),

        ProfileMenuCard(
          icon: Icons.electrical_services_rounded,
          title: 'Local SOCKS5 Port',
          subtitle: 'Port: ${Prefs.socksPort}',
          onClick: () => _showPortDialog('SOCKS5 Port', Prefs.socksPort, (p) => Prefs.socksPort = p),
        ),
        const SizedBox(height: 8.0),

        ProfileMenuCard(
          icon: Icons.http_rounded,
          title: 'Local HTTP Proxy Port',
          subtitle: 'Port: ${Prefs.httpPort}',
          onClick: () => _showPortDialog('HTTP Port', Prefs.httpPort, (p) => Prefs.httpPort = p),
        ),
        const SizedBox(height: 8.0),

        SettingSwitchRow(
          title: 'Share over LAN',
          subtitle: 'Listen on local network for other devices (Port 1081)',
          checked: Prefs.shareLan,
          onCheckedChange: (val) {
            setState(() => Prefs.shareLan = val);
          },
        ),

        const SizedBox(height: 16.0),
        _buildSectionHeader('Routing & Protection'),
        const SizedBox(height: 8.0),

        SettingSwitchRow(
          title: 'Bypass Local Network (LAN)',
          subtitle: 'Direct routing for 192.168.x.x, 10.x.x.x and private subnets',
          checked: Prefs.bypassLan,
          onCheckedChange: (val) {
            setState(() => Prefs.bypassLan = val);
          },
        ),
        const SizedBox(height: 8.0),

        SettingSwitchRow(
          title: 'Bypass Domestic Traffic',
          subtitle: 'Direct routing for national and local sites',
          checked: Prefs.bypassDomestic,
          onCheckedChange: (val) {
            setState(() => Prefs.bypassDomestic = val);
          },
        ),
        const SizedBox(height: 8.0),

        SettingSwitchRow(
          title: 'Block Ads & Trackers',
          subtitle: 'Filter malicious domains and advertising telemetry',
          checked: Prefs.blockAds,
          onCheckedChange: (val) {
            setState(() => Prefs.blockAds = val);
          },
        ),
        const SizedBox(height: 8.0),

        ProfileMenuCard(
          icon: Icons.dns_rounded,
          title: 'DNS Provider',
          subtitle: 'Current: ${Prefs.dnsProvider.toUpperCase()}',
          onClick: _showDnsDialog,
        ),
        const SizedBox(height: 8.0),

        ProfileMenuCard(
          icon: Icons.alt_route_rounded,
          title: 'Split Tunneling (App Bypass)',
          subtitle: '${Prefs.vpnExcludedApps.length} programs bypassed',
          onClick: _openSplitTunnel,
        ),

        const SizedBox(height: 16.0),
        _buildSectionHeader('Diagnostics & Updates'),
        const SizedBox(height: 8.0),

        ProfileMenuCard(
          icon: Icons.receipt_long_rounded,
          title: 'Live Logs & Diagnostics',
          subtitle: 'View detailed connection and engine logs',
          onClick: _openLogs,
        ),
        const SizedBox(height: 8.0),

        ProfileMenuCard(
          icon: Icons.system_update_rounded,
          title: 'Check for Updates',
          subtitle: 'Current version: 1.5.17',
          onClick: () async {
            await widget.state.checkUpdates(force: true);
            if (!mounted) return;
            if (widget.state.update != null) {
              showUpdateDialog(context, widget.state, widget.state.update!);
            } else {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('ClxyPro is up to date.')),
              );
            }
          },
        ),
        const SizedBox(height: 8.0),

        ProfileMenuCard(
          icon: Icons.info_outline_rounded,
          title: 'About ClxyPro & Licenses',
          subtitle: 'Open source information and legal notices',
          onClick: _showAboutDialog,
        ),

        const SizedBox(height: 24.0),
      ],
    );
  }

  Widget _buildSectionHeader(String title) {
    return Text(
      title,
      style: const TextStyle(
        color: ClxyColors.cyanText,
        fontSize: 12.0,
        fontWeight: FontWeight.bold,
        letterSpacing: 0.5,
      ),
    );
  }
}
