import 'package:flutter/material.dart';
import '../theme/clxy_colors.dart';

class ClxyCosmicBackground extends StatelessWidget {
  const ClxyCosmicBackground({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [ClxyColors.bgTop, ClxyColors.bgMid, ClxyColors.bgBottom],
        ),
      ),
      child: CustomPaint(
        painter: _CosmicPainter(),
        child: child,
      ),
    );
  }
}

class _CosmicPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // 1. Cyan Glow (top-left)
    final p1 = Paint()
      ..shader = RadialGradient(
        colors: [ClxyColors.cyanGlow.withOpacity(0.12), Colors.transparent],
      ).createShader(Rect.fromCircle(
        center: Offset(w * 0.18, h * 0.20),
        radius: w * 0.65,
      ));
    canvas.drawCircle(Offset(w * 0.18, h * 0.20), w * 0.65, p1);

    // 2. Purple Glow (top-right)
    final p2 = Paint()
      ..shader = RadialGradient(
        colors: [ClxyColors.purplePrimary.withOpacity(0.15), Colors.transparent],
      ).createShader(Rect.fromCircle(
        center: Offset(w * 0.84, h * 0.26),
        radius: w * 0.68,
      ));
    canvas.drawCircle(Offset(w * 0.84, h * 0.26), w * 0.68, p2);

    // 3. Blue Glow (bottom-center)
    final p3 = Paint()
      ..shader = RadialGradient(
        colors: [ClxyColors.bluePrimary.withOpacity(0.10), Colors.transparent],
      ).createShader(Rect.fromCircle(
        center: Offset(w * 0.50, h * 0.86),
        radius: w * 0.72,
      ));
    canvas.drawCircle(Offset(w * 0.50, h * 0.86), w * 0.72, p3);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
