import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../theme/clxy_colors.dart';

class DottedWorldMap extends StatefulWidget {
  final double dotAlpha;
  final bool animated;
  final double? width;
  final double? height;

  const DottedWorldMap({
    super.key,
    this.dotAlpha = 0.38,
    this.animated = true,
    this.width,
    this.height,
  });

  @override
  State<DottedWorldMap> createState() => _DottedWorldMapState();
}

class _DottedWorldMapState extends State<DottedWorldMap>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 4800),
    );
    if (widget.animated) {
      _controller.repeat();
    }
  }

  @override
  void didUpdateWidget(DottedWorldMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.animated != oldWidget.animated) {
      if (widget.animated) {
        _controller.repeat();
      } else {
        _controller.stop();
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return CustomPaint(
          size: Size(widget.width ?? double.infinity, widget.height ?? double.infinity),
          painter: _DottedWorldMapPainter(
            dotAlpha: widget.dotAlpha,
            wavePhase: widget.animated ? _controller.value * 2 * math.pi : 0.0,
            animated: widget.animated,
          ),
        );
      },
    );
  }
}

class _DottedWorldMapPainter extends CustomPainter {
  final double dotAlpha;
  final double wavePhase;
  final bool animated;

  _DottedWorldMapPainter({
    required this.dotAlpha,
    required this.wavePhase,
    required this.animated,
  });

  bool _ellipse(double nx, double ny, double cx, double cy, double rx, double ry) {
    final dx = (nx - cx) / rx;
    final dy = (ny - cy) / ry;
    return dx * dx + dy * dy <= 1.0;
  }

  bool _insideContinent(double nx, double ny) {
    final alaska = _ellipse(nx, ny, 0.09, 0.21, 0.055, 0.055);
    final canadaUs = _ellipse(nx, ny, 0.20, 0.28, 0.115, 0.125);
    final mexico = _ellipse(nx, ny, 0.21, 0.43, 0.045, 0.065);
    final greenland = _ellipse(nx, ny, 0.34, 0.13, 0.048, 0.055);
    final southAmNorth = _ellipse(nx, ny, 0.275, 0.59, 0.065, 0.095);
    final southAmSouth = _ellipse(nx, ny, 0.265, 0.74, 0.036, 0.120);
    final uk = _ellipse(nx, ny, 0.435, 0.25, 0.018, 0.030);
    final europe = _ellipse(nx, ny, 0.50, 0.27, 0.065, 0.075);
    final scandi = _ellipse(nx, ny, 0.515, 0.175, 0.040, 0.048);
    final africaNorth = _ellipse(nx, ny, 0.505, 0.465, 0.078, 0.095);
    final africaSouth = _ellipse(nx, ny, 0.530, 0.625, 0.048, 0.125);
    final madagascar = _ellipse(nx, ny, 0.598, 0.665, 0.014, 0.045);
    final middleEast = _ellipse(nx, ny, 0.595, 0.395, 0.045, 0.058);
    final siberiaWest = _ellipse(nx, ny, 0.66, 0.215, 0.115, 0.095);
    final eastAsia = _ellipse(nx, ny, 0.76, 0.32, 0.115, 0.120);
    final india = _ellipse(nx, ny, 0.695, 0.455, 0.040, 0.075);
    final indochina = _ellipse(nx, ny, 0.775, 0.475, 0.035, 0.065);
    final japan = _ellipse(nx, ny, 0.895, 0.305, 0.018, 0.055);
    final indonesia = _ellipse(nx, ny, 0.815, 0.575, 0.065, 0.025);
    final australia = _ellipse(nx, ny, 0.845, 0.725, 0.065, 0.088);
    final newZealand = _ellipse(nx, ny, 0.942, 0.810, 0.015, 0.042);

    return alaska || canadaUs || mexico || greenland ||
        southAmNorth || southAmSouth ||
        uk || europe || scandi ||
        africaNorth || africaSouth || madagascar ||
        middleEast || siberiaWest || eastAsia || india || indochina ||
        japan || indonesia || australia || newZealand;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    if (w <= 0 || h <= 0) return;

    final step = (w / 58.0).clamp(4.5, 7.0);
    final radius = step * 0.24;

    // Radial background glow
    final bgCenter = Offset(w * 0.5, h * 0.48);
    final bgRadius = w * 0.46;
    final bgPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          ClxyColors.cyanGlow.withOpacity((dotAlpha * 0.24).clamp(0.0, 1.0)),
          ClxyColors.bluePrimary.withOpacity((dotAlpha * 0.12).clamp(0.0, 1.0)),
          Colors.transparent,
        ],
      ).createShader(Rect.fromCircle(center: bgCenter, radius: bgRadius));
    canvas.drawCircle(bgCenter, bgRadius, bgPaint);

    final dotPaint = Paint()..style = PaintingStyle.fill;

    double y = step * 0.5;
    while (y < h) {
      double x = step * 0.5;
      while (x < w) {
        final nx = x / w;
        final ny = y / h;
        if (_insideContinent(nx, ny)) {
          final shimmer = animated
              ? 0.82 + 0.18 * math.sin(wavePhase + nx * 7.5 + ny * 4.5)
              : 1.0;
          final a = (dotAlpha * shimmer).clamp(0.12, 0.95);
          Color color;
          if (nx < 0.36) {
            color = ClxyColors.cyanGlow.withOpacity(a);
          } else if (nx < 0.68) {
            color = const Color(0xFF60A5FA).withOpacity(a);
          } else {
            color = const Color(0xFFC084FC).withOpacity((a + 0.06).clamp(0.0, 1.0));
          }
          dotPaint.color = color;
          canvas.drawCircle(Offset(x, y), radius, dotPaint);
        }
        x += step;
      }
      y += step;
    }
  }

  @override
  bool shouldRepaint(covariant _DottedWorldMapPainter oldDelegate) {
    return oldDelegate.wavePhase != wavePhase ||
        oldDelegate.dotAlpha != dotAlpha ||
        oldDelegate.animated != animated;
  }
}
