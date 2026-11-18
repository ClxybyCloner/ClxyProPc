import 'package:flutter/material.dart';
import '../theme/clxy_colors.dart';
import 'circular_country_flag.dart';

class RouteTunnelBox extends StatefulWidget {
  final bool connected;
  final String originCode;
  final String originName;
  final String originIp;
  final String destCode;
  final String destName;
  final String destIp;

  const RouteTunnelBox({
    super.key,
    required this.connected,
    required this.originCode,
    required this.originName,
    required this.originIp,
    required this.destCode,
    required this.destName,
    required this.destIp,
  });

  @override
  State<RouteTunnelBox> createState() => _RouteTunnelBoxState();
}

class _RouteTunnelBoxState extends State<RouteTunnelBox>
    with TickerProviderStateMixin {
  late final AnimationController _dashController;
  late final AnimationController _packetController;

  @override
  void initState() {
    super.initState();
    _dashController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    )..repeat();

    _packetController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1150),
    )..repeat();
  }

  @override
  void dispose() {
    _dashController.dispose();
    _packetController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 380),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
        decoration: BoxDecoration(
          color: ClxyColors.routeBoxSurface,
          borderRadius: BorderRadius.circular(12.0),
          border: Border.all(
            color: widget.connected
                ? const Color(0x4D38BDF8)
                : const Color(0x2294A3B8),
            width: 1.0,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            // Origin node (aligned right before flag)
            Expanded(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Flexible(
                    child: Column(
                      crossAxisAlignment: CrossAlignment.end,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          widget.originName,
                          style: const TextStyle(
                            color: ClxyColors.textPrimary,
                            fontSize: 11.0,
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          widget.originIp,
                          style: const TextStyle(
                            color: ClxyColors.textMuted,
                            fontSize: 9.5,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 7.0),
                  CircularCountryFlag(
                    countryCode: widget.originCode,
                    size: 24.0,
                  ),
                ],
              ),
            ),

            // Animated middle connector
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8.0),
              child: AnimatedBuilder(
                animation: Listenable.merge([_dashController, _packetController]),
                builder: (context, _) {
                  return CustomPaint(
                    size: const Size(54.0, 14.0),
                    painter: _RouteConnectorPainter(
                      connected: widget.connected,
                      dashOffset: _dashController.value * -16.0,
                      packetProgress: _packetController.value,
                    ),
                  );
                },
              ),
            ),

            // Destination node
            Expanded(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.start,
                children: [
                  CircularCountryFlag(
                    countryCode: widget.destCode,
                    size: 24.0,
                  ),
                  const SizedBox(width: 7.0),
                  Flexible(
                    child: Column(
                      crossAxisAlignment: CrossAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          widget.destName,
                          style: const TextStyle(
                            color: ClxyColors.textPrimary,
                            fontSize: 11.0,
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          widget.destIp,
                          style: TextStyle(
                            color: widget.connected
                                ? ClxyColors.cyanText
                                : ClxyColors.textMuted,
                            fontSize: 9.5,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RouteConnectorPainter extends CustomPainter {
  final bool connected;
  final double dashOffset;
  final double packetProgress;

  _RouteConnectorPainter({
    required this.connected,
    required this.dashOffset,
    required this.packetProgress,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final cy = size.height / 2.0;
    const startX = 2.0;
    final endX = size.width - 4.0;
    final totalLen = endX - startX;

    final linePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    if (connected) {
      linePaint.shader = const LinearGradient(
        colors: [
          ClxyColors.cyanGlow,
          ClxyColors.bluePrimary,
          Color(0xFFA855F7),
        ],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    } else {
      linePaint.color = ClxyColors.timerDim;
    }

    // Draw dashed line
    const dashLen = 4.0;
    const spaceLen = 3.0;
    double curX = startX + (connected ? (dashOffset % (dashLen + spaceLen)) : 0.0);
    while (curX < endX) {
      final x1 = curX.clamp(startX, endX);
      final x2 = (curX + dashLen).clamp(startX, endX);
      if (x2 > x1) {
        canvas.drawLine(Offset(x1, cy), Offset(x2, cy), linePaint);
      }
      curX += dashLen + spaceLen;
    }

    // Draw arrow head at end
    final arrowPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round
      ..color = connected ? const Color(0xFFA855F7) : ClxyColors.timerDim;
    canvas.drawLine(Offset(endX - 3.0, cy - 3.5), Offset(endX, cy), arrowPaint);
    canvas.drawLine(Offset(endX - 3.0, cy + 3.5), Offset(endX, cy), arrowPaint);

    // Glowing packet bead if connected
    if (connected) {
      final beadX = startX + packetProgress * totalLen;
      final beadPaint = Paint()
        ..color = ClxyColors.cyanBright
        ..style = PaintingStyle.fill;
      canvas.drawCircle(Offset(beadX, cy), 2.2, beadPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _RouteConnectorPainter oldDelegate) {
    return oldDelegate.connected != connected ||
        oldDelegate.dashOffset != dashOffset ||
        oldDelegate.packetProgress != packetProgress;
  }
}
