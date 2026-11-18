import 'package:flutter/material.dart';
import '../theme/clxy_colors.dart';

class BrandHeader extends StatelessWidget {
  final double logoSize;
  final bool showLabel;
  final double labelSize;

  const BrandHeader({
    super.key,
    this.logoSize = 32.0,
    this.showLabel = true,
    this.labelSize = 17.0,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAlignment.center,
      children: [
        Image.asset(
          'assets/images/clxy_logo.png',
          width: logoSize,
          height: logoSize * 0.85,
          fit: BoxFit.contain,
        ),
        if (showLabel) ...[
          const SizedBox(width: 10.0),
          ShaderMask(
            shaderCallback: (bounds) => const LinearGradient(
              colors: [
                ClxyColors.cyanBright,
                Color(0xFF60A5FA),
                ClxyColors.pinkAccent,
              ],
            ).createShader(bounds),
            child: Text(
              'ClxyPro',
              style: TextStyle(
                fontFamily: 'Inter',
                fontWeight: FontWeight.bold,
                fontSize: labelSize,
                letterSpacing: 0.8,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ],
    );
  }
}
