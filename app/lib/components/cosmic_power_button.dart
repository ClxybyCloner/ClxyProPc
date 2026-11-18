import 'package:flutter/material.dart';
import '../theme/clxy_colors.dart';

class CosmicPowerButton extends StatefulWidget {
  final bool connected;
  final bool connecting;
  final bool isQuantum;
  final double buttonSize;
  final VoidCallback onTap;

  const CosmicPowerButton({
    super.key,
    required this.connected,
    required this.connecting,
    this.isQuantum = false,
    this.buttonSize = 132.0,
    required this.onTap,
  });

  @override
  State<CosmicPowerButton> createState() => _CosmicPowerButtonState();
}

class _CosmicPowerButtonState extends State<CosmicPowerButton>
    with TickerProviderStateMixin {
  late final AnimationController _pulseController;
  late final AnimationController _breathController;
  bool _isPressed = false;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..repeat();

    _breathController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _breathController.dispose();
    super.dispose();
  }

  Color get _glowPrimary {
    if (widget.connected) {
      return widget.isQuantum ? ClxyColors.quantumPurple : ClxyColors.cyanGlow;
    }
    if (widget.connecting) {
      return ClxyColors.amberWarning;
    }
    return ClxyColors.bluePrimary.withOpacity(0.5);
  }

  Color get _glowSecondary {
    if (widget.connected) {
      return widget.isQuantum ? ClxyColors.quantumViolet : ClxyColors.purplePrimary;
    }
    if (widget.connecting) {
      return ClxyColors.bluePrimary;
    }
    return ClxyColors.purplePrimary.withOpacity(0.4);
  }

  Color get _coreStart {
    if (widget.connected) {
      return widget.isQuantum ? ClxyColors.quantumPurple : ClxyColors.cyanBright;
    }
    if (widget.connecting) {
      return ClxyColors.amberWarning;
    }
    return const Color(0xFF1E293B);
  }

  Color get _coreMid {
    if (widget.connected) {
      return widget.isQuantum ? const Color(0xFF4C1D95) : ClxyColors.blueDeep;
    }
    if (widget.connecting) {
      return ClxyColors.bluePrimary;
    }
    return const Color(0xFF0F172A);
  }

  Color get _coreEnd {
    if (widget.connected) {
      return widget.isQuantum ? ClxyColors.quantumViolet : ClxyColors.purplePrimary;
    }
    if (widget.connecting) {
      return ClxyColors.purplePrimary;
    }
    return const Color(0xFF1E1B4B);
  }

  @override
  Widget build(BuildContext context) {
    final bSize = widget.buttonSize;
    final totalSize = bSize * 1.46;

    return GestureDetector(
      onTapDown: (_) => setState(() => _isPressed = true),
      onTapUp: (_) {
        setState(() => _isPressed = false);
        widget.onTap();
      },
      onTapCancel: () => setState(() => _isPressed = false),
      child: AnimatedScale(
        scale: _isPressed ? 0.92 : 1.0,
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOutBack,
        child: SizedBox(
          width: totalSize,
          height: totalSize,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Outer rings when connected or connecting
              if (widget.connected || widget.connecting) ...[
                AnimatedBuilder(
                  animation: _pulseController,
                  builder: (context, _) {
                    final p1 = _pulseController.value;
                    final p2 = (p1 + 0.5) % 1.0;
                    return Stack(
                      alignment: Alignment.center,
                      children: [
                        _buildRing(p1, bSize),
                        _buildRing(p2, bSize),
                      ],
                    );
                  },
                ),
              ] else ...[
                // Idle breathing ring
                AnimatedBuilder(
                  animation: _breathController,
                  builder: (context, _) {
                    final breath = 0.98 + 0.06 * _breathController.value;
                    final ringColor = (widget.isQuantum
                            ? ClxyColors.quantumPurple
                            : ClxyColors.cyanGlow)
                        .withOpacity(0.16);
                    return Transform.scale(
                      scale: breath,
                      child: Container(
                        width: bSize * 1.08,
                        height: bSize * 1.08,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: ringColor, width: 1.0),
                        ),
                      ),
                    );
                  },
                ),
              ],

              // Central button circle
              AnimatedContainer(
                duration: const Duration(milliseconds: 380),
                width: bSize,
                height: bSize,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: [_coreStart, _coreMid, _coreEnd],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  border: Border.all(
                    color: (widget.connected || widget.connecting)
                        ? const Color(0x99BAE6FD)
                        : const Color(0x4794A3B8),
                    width: 1.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: widget.connected
                          ? _glowPrimary.withOpacity(0.65)
                          : Colors.black.withOpacity(0.5),
                      blurRadius: widget.connected ? 28 : 14,
                      spreadRadius: widget.connected ? 4 : 0,
                    ),
                  ],
                ),
                child: Center(
                  child: widget.connecting
                      ? SizedBox(
                          width: bSize * 0.33,
                          height: bSize * 0.33,
                          child: const CircularProgressIndicator(
                            strokeWidth: 3.0,
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        )
                      : Icon(
                          Icons.power_settings_new_rounded,
                          color: Colors.white,
                          size: bSize * 0.35,
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRing(double p, double size) {
    final ringScale = 0.96 + p * 0.42;
    final ringAlpha = (1.0 - p) * 0.52;
    final primary = _glowPrimary;
    final secondary = _glowSecondary;

    return Transform.scale(
      scale: ringScale,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: primary.withOpacity(ringAlpha.clamp(0.0, 1.0)),
            width: 2.0,
          ),
          gradient: RadialGradient(
            colors: [
              primary.withOpacity((ringAlpha * 0.25).clamp(0.0, 1.0)),
              Colors.transparent,
            ],
          ),
        ),
      ),
    );
  }
}
