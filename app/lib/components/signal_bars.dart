import 'package:flutter/material.dart';
import '../theme/clxy_colors.dart';

class SignalBars extends StatelessWidget {
  final int pingMs;

  const SignalBars({
    super.key,
    required this.pingMs,
  });

  @override
  Widget build(BuildContext context) {
    final activeBars = pingMs <= 0
        ? 3
        : pingMs < 120
            ? 4
            : pingMs < 240
                ? 3
                : pingMs < 450
                    ? 2
                    : 1;

    final activeColor = (pingMs <= 0 || pingMs < 400)
        ? ClxyColors.cyanGlow
        : pingMs < 1000
            ? ClxyColors.amberWarning
            : ClxyColors.redDisconnectStart;

    return CustomPaint(
      size: const Size(16.0, 11.0),
      painter: _SignalBarsPainter(
        activeBars: activeBars,
        activeColor: activeColor,
        inactiveColor: ClxyColors.barInactive,
      ),
    );
  }
}

class _SignalBarsPainter extends CustomPainter {
  final int activeBars;
  final Color activeColor;
  final Color inactiveColor;

  _SignalBarsPainter({
    required this.activeBars,
    required this.activeColor,
    required this.inactiveColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final barW = size.width / 5.5;
    final gap = (size.width - barW * 4) / 3.0;
    const heights = [0.30, 0.50, 0.75, 1.0];

    for (int i = 0; i < heights.length; i++) {
      final h = size.height * heights[i];
      final x = i * (barW + gap);
      final y = size.height - h;
      final paint = Paint()
        ..color = (i < activeBars) ? activeColor : inactiveColor
        ..style = PaintingStyle.fill;

      final rrect = RRect.fromRectAndRadius(
        Rect.fromLTWH(x, y, barW, h),
        const Radius.circular(1.0),
      );
      canvas.drawRRect(rrect, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _SignalBarsPainter oldDelegate) {
    return oldDelegate.activeBars != activeBars ||
        oldDelegate.activeColor != activeColor ||
        oldDelegate.inactiveColor != inactiveColor;
  }
}
