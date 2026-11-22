import 'dart:ui';
import 'package:flutter/material.dart';
import '../components/brand_header.dart';
import '../components/circular_country_flag.dart';
import '../components/cosmic_power_button.dart';
import '../components/dotted_world_map.dart';
import '../components/mode_pill_group.dart';
import '../components/route_tunnel_box.dart';
import '../components/shield_icon.dart';
import '../components/signal_bars.dart';
import '../core/app_state.dart';
import '../core/prefs.dart';
import '../theme/clxy_colors.dart';
import 'quantum_serial_dialog.dart';
import 'update_dialog.dart';

class HomeScreen extends StatelessWidget {
  final AppState state;
  final VoidCallback onOpenServers;
  final VoidCallback onOpenSignIn;

  const HomeScreen({
    super.key,
    required this.state,
    required this.onOpenServers,
    required this.onOpenSignIn,
  });

  Color get _shieldColor {
    if (state.isConnected) {
      return state.isQuantum ? ClxyColors.quantumPurple : ClxyColors.cyanGlow;
    }
    if (state.isConnecting) {
      return ClxyColors.amberWarning;
    }
    return ClxyColors.textMuted;
  }

  Color get _statusColor {
    if (state.isConnected) {
      return state.isQuantum ? ClxyColors.quantumPurple : ClxyColors.cyanText;
    }
    if (state.isConnecting) {
      return ClxyColors.amberWarning;
    }
    return ClxyColors.textSecondary;
  }

  String _formatTimer(int totalSecs) {
    final hrs = totalSecs ~/ 3600;
    final mins = (totalSecs % 3600) ~/ 60;
    final secs = totalSecs % 60;
    final minSec =
        '${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
    if (hrs > 0) {
      return '${hrs.toString().padLeft(2, '0')}:$minSec';
    }
    return minSec;
  }

  Future<bool> _promptQuantumSerial(BuildContext context) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => QuantumSerialDialog(
        onDismiss: () => Navigator.of(ctx).pop(false),
        onActivated: () => Navigator.of(ctx).pop(true),
      ),
    );
    return result ?? false;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxHeight < 680;
        final topPad = compact ? 8.0 : 16.0;
        final sectionGap = compact ? 6.0 : 10.0;
        final timerSize = compact ? 34.0 : 40.0;
        final mapHeight = compact ? 190.0 : 230.0;
        final btnDiameter = compact ? 116.0 : 130.0;

        return SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox(height: topPad),

              // Brand header
              BrandHeader(
                logoSize: compact ? 26.0 : 28.0,
                labelSize: compact ? 14.5 : 15.5,
              ),

              SizedBox(height: sectionGap),

              // New version banner
              if (state.update != null) ...[
                MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: GestureDetector(
                    onTap: () =>
                        showUpdateDialog(context, state, state.update!),
                    child: _buildUpdateBanner(context, state.update!.version),
                  ),
                ),
                SizedBox(height: sectionGap),
              ],

              // Dual-Core Switcher
              _buildCoreSwitcher(),

              SizedBox(height: sectionGap),

              // Shield + Status text
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ShieldIcon(color: _shieldColor, size: 14.0),
                  const SizedBox(width: 7.0),
                  Text(
                    state.statusLabel,
                    style: TextStyle(
                      color: _statusColor,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 4.0),

              // Large Tabular Timer
              Text(
                _formatTimer(state.elapsedSeconds),
                style: TextStyle(
                  color: state.isConnected
                      ? ClxyColors.textPrimary
                      : ClxyColors.timerDim,
                  fontSize: timerSize,
                  fontWeight: FontWeight.w400,
                  letterSpacing: 0.5,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),

              SizedBox(height: sectionGap),

              // Speed stats row
              _buildSpeedRow(),

              SizedBox(height: compact ? 2.0 : 6.0),

              // Dotted World Map with Cosmic Power Button
              SizedBox(
                width: double.infinity,
                height: mapHeight,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    DottedWorldMap(
                      dotAlpha: (state.isConnected || state.isConnecting)
                          ? 0.54
                          : 0.44,
                      animated: true,
                      height: mapHeight,
                    ),
                    CosmicPowerButton(
                      connected: state.isConnected,
                      connecting: state.isConnecting,
                      isQuantum: state.isQuantum,
                      buttonSize: btnDiameter,
                      onTap: () {
                        state.toggleConnect(
                          onNeedQuantumSerial: () =>
                              _promptQuantumSerial(context),
                        );
                      },
                    ),
                  ],
                ),
              ),

              SizedBox(height: compact ? 4.0 : 8.0),

              // Route Tunnel Box
              RouteTunnelBox(
                connected: state.isConnected || state.isConnecting,
                originCode: state.originCode,
                originName: state.originName,
                originIp: state.originIp,
                destCode: state.destCode,
                destName: state.destName,
                destIp: state.destIp,
              ),

              SizedBox(height: sectionGap),

              // Hyper Mode: Account / Quota card. The selected-server
              // card is shared: Quantum shows the pinned relay (or
              // Auto Scan) and opens the same Servers list.
              if (state.isHyper) ...[
                _buildDataUsageCard(context),
                SizedBox(height: sectionGap),
              ],
              _buildSelectedServerCard(),
              SizedBox(height: sectionGap),

              // Mode selector (VPN Mode | Proxy Mode)
              ModePillGroup(
                isVpn: state.isVpnMode,
                onSelectMode: (isVpn) {
                  state.setMode(isVpn ? 'VPN' : 'PROXY');
                },
              ),

              SizedBox(height: compact ? 8.0 : 16.0),
            ],
          ),
        );
      },
    );
  }

  Widget _buildUpdateBanner(BuildContext context, String version) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 380),
      decoration: BoxDecoration(
        color: ClxyColors.cardSurface,
        borderRadius: BorderRadius.circular(999.0),
        border: Border.all(color: ClxyColors.cyanBorder, width: 1.0),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 8.0),
      child: Row(
        children: [
          const Icon(
            Icons.system_update_rounded,
            color: ClxyColors.cyanText,
            size: 16.0,
          ),
          const SizedBox(width: 8.0),
          Expanded(
            child: Text(
              'New version v$version available',
              style: const TextStyle(
                color: ClxyColors.cyanText,
                fontSize: 12.5,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const Icon(
            Icons.chevron_right_rounded,
            color: ClxyColors.cyanText,
            size: 16.0,
          ),
        ],
      ),
    );
  }

  Widget _buildCoreSwitcher() {
    return Container(
      constraints: const BoxConstraints(maxWidth: 380),
      decoration: BoxDecoration(
        color: const Color(0xD10C1328),
        borderRadius: BorderRadius.circular(999.0),
        border: Border.all(color: ClxyColors.glassBorder, width: 1.0),
      ),
      padding: const EdgeInsets.all(3.0),
      child: Row(
        children: [
          // CLXY Hyper
          Expanded(
            child: InkWell(
              onTap: (!state.isConnected && !state.isConnecting)
                  ? () => state.setCore('firefox')
                  : null,
              borderRadius: BorderRadius.circular(999.0),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 7.0),
                decoration: BoxDecoration(
                  color: state.isHyper
                      ? ClxyColors.cyanGlow.withOpacity(0.22)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(999.0),
                  border: Border.all(
                    color: state.isHyper
                        ? ClxyColors.cyanGlow.withOpacity(0.55)
                        : Colors.transparent,
                    width: 1.0,
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.bolt_rounded,
                      color: state.isHyper
                          ? ClxyColors.cyanText
                          : ClxyColors.textDim,
                      size: 15.0,
                    ),
                    const SizedBox(width: 6.0),
                    Text(
                      'CLXY Hyper',
                      style: TextStyle(
                        color: state.isHyper
                            ? ClxyColors.cyanText
                            : ClxyColors.textDim,
                        fontSize: 12.5,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // CLXY Quantum
          Expanded(
            child: InkWell(
              onTap: (!state.isConnected && !state.isConnecting)
                  ? () => state.setCore('aether')
                  : null,
              borderRadius: BorderRadius.circular(999.0),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 7.0),
                decoration: BoxDecoration(
                  color: state.isQuantum
                      ? ClxyColors.quantumPurple.withOpacity(0.28)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(999.0),
                  border: Border.all(
                    color: state.isQuantum
                        ? ClxyColors.quantumPurple.withOpacity(0.65)
                        : Colors.transparent,
                    width: 1.0,
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text('🪐', style: TextStyle(fontSize: 12.0)),
                    const SizedBox(width: 6.0),
                    Text(
                      'CLXY Quantum',
                      style: TextStyle(
                        color: state.isQuantum
                            ? ClxyColors.quantumPurple
                            : ClxyColors.textDim,
                        fontSize: 12.5,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSpeedRow() {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 320),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          // Download rate
          Column(
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    state.downRate,
                    style: const TextStyle(
                      color: ClxyColors.textPrimary,
                      fontSize: 14.5,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(width: 3.0),
                  const Text(
                    'KB/s',
                    style: TextStyle(
                      color: ClxyColors.textMuted,
                      fontSize: 10.0,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 2.0),
              const Row(
                children: [
                  Icon(
                    Icons.arrow_downward_rounded,
                    color: ClxyColors.cyanGlow,
                    size: 11.0,
                  ),
                  SizedBox(width: 2.0),
                  Text(
                    'Download',
                    style: TextStyle(
                      color: ClxyColors.textDim,
                      fontSize: 9.5,
                    ),
                  ),
                ],
              ),
            ],
          ),

          // Upload rate
          Column(
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    state.upRate,
                    style: const TextStyle(
                      color: ClxyColors.textPrimary,
                      fontSize: 14.5,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(width: 3.0),
                  const Text(
                    'KB/s',
                    style: TextStyle(
                      color: ClxyColors.textMuted,
                      fontSize: 10.0,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 2.0),
              const Row(
                children: [
                  Icon(
                    Icons.arrow_upward_rounded,
                    color: ClxyColors.pinkAccent,
                    size: 11.0,
                  ),
                  SizedBox(width: 2.0),
                  Text(
                    'Upload',
                    style: TextStyle(
                      color: ClxyColors.textDim,
                      fontSize: 9.5,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDataUsageCard(BuildContext context) {
    final hasSession = Prefs.sessionToken.isNotEmpty;
    final email = Prefs.sessionEmail;
    final quota = Prefs.sessionQuota.isNotEmpty ? Prefs.sessionQuota : 'Unlimited Cloud Mesh';

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 460),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 10.0),
        decoration: BoxDecoration(
          color: ClxyColors.cardSurface,
          borderRadius: BorderRadius.circular(12.0),
          border: Border.all(color: ClxyColors.glassBorder, width: 1.0),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Container(
                  width: 34.0,
                  height: 34.0,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: ClxyColors.blueDeep.withOpacity(0.25),
                  ),
                  child: const Icon(
                    Icons.cloud_queue_rounded,
                    color: ClxyColors.cyanGlow,
                    size: 18.0,
                  ),
                ),
                const SizedBox(width: 12.0),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      hasSession ? (email.isNotEmpty ? email : 'CLXY Cloud Account') : 'CLXY Cloud Account',
                      style: const TextStyle(
                        color: ClxyColors.textPrimary,
                        fontSize: 13.0,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2.0),
                    Text(
                      hasSession ? quota : 'Sign in to access premium locations',
                      style: const TextStyle(
                        color: ClxyColors.textMuted,
                        fontSize: 10.5,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            if (!hasSession)
              InkWell(
                onTap: onOpenSignIn,
                borderRadius: BorderRadius.circular(8.0),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 6.0),
                  decoration: BoxDecoration(
                    color: ClxyColors.cyanGlow.withOpacity(0.18),
                    borderRadius: BorderRadius.circular(8.0),
                    border: Border.all(color: ClxyColors.cyanGlow.withOpacity(0.4), width: 1.0),
                  ),
                  child: const Text(
                    'Sign In',
                    style: TextStyle(
                      color: ClxyColors.cyanText,
                      fontSize: 11.5,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildSelectedServerCard() {
    final pingLabel = state.latencyMs > 0
        ? '${state.latencyMs}ms'
        : (state.isConnected ? 'Online' : 'Ready');

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 460),
      child: InkWell(
        onTap: onOpenServers,
        borderRadius: BorderRadius.circular(12.0),
        child: Container(
          constraints: const BoxConstraints(minHeight: 58.0),
          padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 10.0),
          decoration: BoxDecoration(
            color: ClxyColors.cardSurface,
            borderRadius: BorderRadius.circular(12.0),
            border: Border.all(color: ClxyColors.glassBorder, width: 1.0),
          ),
          child: Row(
            children: [
              CircularCountryFlag(
                countryCode: state.destCode,
                size: 34.0,
              ),
              const SizedBox(width: 13.0),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      state.destName,
                      style: const TextStyle(
                        color: ClxyColors.textPrimary,
                        fontSize: 14.0,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2.0),
                    Row(
                      children: [
                        Text(
                          '${state.destIp} • $pingLabel',
                          style: const TextStyle(
                            color: ClxyColors.textMuted,
                            fontSize: 11.0,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(width: 6.0),
                        SignalBars(pingMs: state.latencyMs),
                      ],
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                color: ClxyColors.textMuted,
                size: 20.0,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
