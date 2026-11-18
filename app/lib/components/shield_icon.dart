import 'package:flutter/material.dart';

class ShieldIcon extends StatelessWidget {
  final Color color;
  final double size;

  const ShieldIcon({
    super.key,
    required this.color,
    this.size = 14.0,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(size, size * 1.14),
      painter: _ShieldIconPainter(color: color),
    );
  }
}

class _ShieldIconPainter extends CustomPainter {
  final Color color;

  _ShieldIconPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final path = Path()
      ..moveTo(w * 0.5, h * 0.03)
      ..lineTo(w * 0.11, h * 0.17)
      ..lineTo(w * 0.11, h * 0.46)
      ..cubicTo(w * 0.11, h * 0.69, w * 0.27, h * 0.91, w * 0.50, h * 0.97)
      ..cubicTo(w * 0.73, h * 0.91, w * 0.89, h * 0.69, w * 0.89, h * 0.46)
      ..lineTo(w * 0.89, h * 0.17)
      ..close();

    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _ShieldIconPainter oldDelegate) {
    return oldDelegate.color != color;
  }
}
