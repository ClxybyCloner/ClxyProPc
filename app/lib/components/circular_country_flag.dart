import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

// Flags drawn by hand on canvas (kept: proper flags beat emoji).
const _handDrawn = {
  'US', 'DE', 'FR', 'GB', 'NL', 'CA', 'JP', 'IR', 'IE', 'CH', 'SE', 'FI', 'AR'
};
const _special = {'', 'REC', 'AUTO'};

// Codes with a bundled SVG flag in assets/flags/ (34 shipped + 11
// added for the exit list in v1.5.31). Windows has no flag emoji —
// Segoe UI Emoji renders 🇷🇴 as the two letters "RO" — so the SVG is
// the only way a flag shows here at all.
const _svgFlags = {
  'AR', 'AT', 'AU', 'BE', 'BG', 'BR', 'CA', 'CH', 'CL', 'CO', 'CZ', 'DE',
  'DK', 'EE', 'ES', 'FI', 'FR', 'GB', 'GH', 'HR', 'HU', 'IE', 'IN', 'IT',
  'JP', 'KR', 'LV', 'MX', 'MY', 'NL', 'NO', 'NZ', 'PE', 'PH', 'PL', 'PT',
  'RO', 'RS', 'SE', 'SG', 'SK', 'TH', 'US', 'ZA',
};

/// Any other two-letter code gets a real flag emoji (Android rc8):
/// regional indicators, no hashed badge, no ring (rc11).
bool _isEmojiFlag(String code) =>
    code.length == 2 &&
    !_special.contains(code) &&
    !_handDrawn.contains(code) &&
    code != 'CLXY';

String _flagEmoji(String code) {
  final first = 0x1F1E6 + (code.codeUnitAt(0) - 0x41);
  final second = 0x1F1E6 + (code.codeUnitAt(1) - 0x41);
  return String.fromCharCode(first) + String.fromCharCode(second);
}

class CircularCountryFlag extends StatelessWidget {
  final String countryCode;
  final double size;

  const CircularCountryFlag({
    super.key,
    required this.countryCode,
    this.size = 34.0,
  });

  @override
  Widget build(BuildContext context) {
    final code = countryCode.trim().toUpperCase();
    // SVG first: a real flag image. Emoji only when there is no SVG
    // (and on Windows that renders as the two letters — same
    // information, never a blank).
    final isSvg = _svgFlags.contains(code) && !_handDrawn.contains(code);
    final emoji = !isSvg && _isEmojiFlag(code) ? _flagEmoji(code) : '';
    final showText = code == 'CLXY' || emoji.isNotEmpty;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        // No ring around an emoji flag (Android rc11).
        border: emoji.isEmpty
            ? Border.all(
                color: Colors.white.withOpacity(0.18),
                width: 1.0,
              )
            : null,
      ),
      child: ClipOval(
        child: Stack(
          alignment: Alignment.center,
          children: [
            if (isSvg)
              SvgPicture.asset(
                'assets/flags/${code.toLowerCase()}.svg',
                width: size,
                height: size,
                fit: BoxFit.cover,
              )
            else
              CustomPaint(
                size: Size(size, size),
                painter: _FlagPainter(code: code),
              ),
            if (showText)
              Text(
                emoji.isNotEmpty
                    ? emoji
                    : (code == 'CLXY'
                        ? 'CX'
                        : (code.length >= 2 ? code.substring(0, 2) : code)),
                style: TextStyle(
                  color: Colors.white,
                  // Emoji glyphs fill the circle; the code text stays small.
                  fontSize: emoji.isNotEmpty ? size * 0.72 : size * 0.34,
                  fontWeight: FontWeight.bold,
                  letterSpacing: -0.5,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _FlagPainter extends CustomPainter {
  final String code;

  _FlagPainter({required this.code});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // Emoji and SVG flags paint nothing: the emoji text / SVG is the flag.
    if (_isEmojiFlag(code)) return;
    if (_svgFlags.contains(code) && !_handDrawn.contains(code)) return;

    switch (code) {
      case '':
      case 'REC':
      case 'AUTO':
        final rect = Rect.fromLTWH(0, 0, w, h);
        final paint = Paint()
          ..shader = const LinearGradient(
            colors: [Color(0xFF00E5FF), Color(0xFF3B82F6), Color(0xFF9333EA)],
          ).createShader(rect);
        canvas.drawRect(rect, paint);

        final strokePaint = Paint()
          ..color = Colors.white.withOpacity(0.3)
          ..style = PaintingStyle.stroke
          ..strokeWidth = w * 0.06;
        canvas.drawCircle(Offset(w * 0.5, h * 0.5), w * 0.32, strokePaint);

        final centerPaint = Paint()
          ..color = Colors.white
          ..style = PaintingStyle.fill;
        canvas.drawCircle(Offset(w * 0.5, h * 0.5), w * 0.12, centerPaint);
        break;

      case 'US':
        final stripeH = h / 13.0;
        final redPaint = Paint()..color = const Color(0xFFB22234);
        final whitePaint = Paint()..color = Colors.white;
        for (int i = 0; i < 13; i++) {
          canvas.drawRect(
            Rect.fromLTWH(0, i * stripeH, w, stripeH + 0.5),
            i % 2 == 0 ? redPaint : whitePaint,
          );
        }
        final bluePaint = Paint()..color = const Color(0xFF3C3B6E);
        canvas.drawRect(Rect.fromLTWH(0, 0, w * 0.46, h * 0.54), bluePaint);
        for (int row = 0; row < 3; row++) {
          for (int col = 0; col < 3; col++) {
            canvas.drawCircle(
              Offset(w * (0.10 + col * 0.13), h * (0.12 + row * 0.14)),
              w * 0.028,
              whitePaint,
            );
          }
        }
        break;

      case 'DE':
        canvas.drawRect(Rect.fromLTWH(0, 0, w, h / 3.0 + 0.5), Paint()..color = const Color(0xFF111111));
        canvas.drawRect(Rect.fromLTWH(0, h / 3.0, w, h / 3.0 + 0.5), Paint()..color = const Color(0xFFDD0000));
        canvas.drawRect(Rect.fromLTWH(0, 2.0 * h / 3.0, w, h / 3.0 + 0.5), Paint()..color = const Color(0xFFFFCE00));
        break;

      case 'FR':
        canvas.drawRect(Rect.fromLTWH(0, 0, w / 3.0 + 0.5, h), Paint()..color = const Color(0xFF002654));
        canvas.drawRect(Rect.fromLTWH(w / 3.0, 0, w / 3.0 + 0.5, h), Paint()..color = Colors.white);
        canvas.drawRect(Rect.fromLTWH(2.0 * w / 3.0, 0, w / 3.0 + 0.5, h), Paint()..color = const Color(0xFFED2939));
        break;

      case 'GB':
        canvas.drawRect(Rect.fromLTWH(0, 0, w, h), Paint()..color = const Color(0xFF012169));
        final whiteLine = Paint()
          ..color = Colors.white
          ..strokeWidth = w * 0.18;
        canvas.drawLine(Offset.zero, Offset(w, h), whiteLine);
        canvas.drawLine(Offset(w, 0), Offset(0, h), whiteLine);
        final redLine = Paint()
          ..color = const Color(0xFFC8102E)
          ..strokeWidth = w * 0.08;
        canvas.drawLine(Offset.zero, Offset(w, h), redLine);
        canvas.drawLine(Offset(w, 0), Offset(0, h), redLine);
        canvas.drawRect(Rect.fromLTWH(w * 0.39, 0, w * 0.22, h), Paint()..color = Colors.white);
        canvas.drawRect(Rect.fromLTWH(0, h * 0.39, w, h * 0.22), Paint()..color = Colors.white);
        canvas.drawRect(Rect.fromLTWH(w * 0.43, 0, w * 0.14, h), Paint()..color = const Color(0xFFC8102E));
        canvas.drawRect(Rect.fromLTWH(0, h * 0.43, w, h * 0.14), Paint()..color = const Color(0xFFC8102E));
        break;

      case 'NL':
        canvas.drawRect(Rect.fromLTWH(0, 0, w, h / 3.0 + 0.5), Paint()..color = const Color(0xFFAE1C28));
        canvas.drawRect(Rect.fromLTWH(0, h / 3.0, w, h / 3.0 + 0.5), Paint()..color = Colors.white);
        canvas.drawRect(Rect.fromLTWH(0, 2.0 * h / 3.0, w, h / 3.0 + 0.5), Paint()..color = const Color(0xFF21468B));
        break;

      case 'CA':
        canvas.drawRect(Rect.fromLTWH(0, 0, w * 0.25, h), Paint()..color = const Color(0xFFFF0000));
        canvas.drawRect(Rect.fromLTWH(w * 0.25, 0, w * 0.50, h), Paint()..color = Colors.white);
        canvas.drawRect(Rect.fromLTWH(w * 0.75, 0, w * 0.25, h), Paint()..color = const Color(0xFFFF0000));
        canvas.drawCircle(Offset(w * 0.5, h * 0.5), w * 0.14, Paint()..color = const Color(0xFFFF0000));
        break;

      case 'JP':
        canvas.drawRect(Rect.fromLTWH(0, 0, w, h), Paint()..color = Colors.white);
        canvas.drawCircle(Offset(w * 0.5, h * 0.5), w * 0.28, Paint()..color = const Color(0xFFBC002D));
        break;

      case 'IR':
        canvas.drawRect(Rect.fromLTWH(0, 0, w, h / 3.0 + 0.5), Paint()..color = const Color(0xFF239F40));
        canvas.drawRect(Rect.fromLTWH(0, h / 3.0, w, h / 3.0 + 0.5), Paint()..color = Colors.white);
        canvas.drawRect(Rect.fromLTWH(0, 2.0 * h / 3.0, w, h / 3.0 + 0.5), Paint()..color = const Color(0xFFDA0000));
        break;

      case 'IE':
        canvas.drawRect(Rect.fromLTWH(0, 0, w / 3.0 + 0.5, h), Paint()..color = const Color(0xFF169B62));
        canvas.drawRect(Rect.fromLTWH(w / 3.0, 0, w / 3.0 + 0.5, h), Paint()..color = Colors.white);
        canvas.drawRect(Rect.fromLTWH(2.0 * w / 3.0, 0, w / 3.0 + 0.5, h), Paint()..color = const Color(0xFFFF883E));
        break;

      case 'CH':
        canvas.drawRect(Rect.fromLTWH(0, 0, w, h), Paint()..color = const Color(0xFFDA291C));
        final whitePaint = Paint()..color = Colors.white;
        canvas.drawRect(Rect.fromLTWH(w * 0.40, h * 0.17, w * 0.20, h * 0.66), whitePaint);
        canvas.drawRect(Rect.fromLTWH(w * 0.17, h * 0.40, w * 0.66, h * 0.20), whitePaint);
        break;

      case 'SE':
        canvas.drawRect(Rect.fromLTWH(0, 0, w, h), Paint()..color = const Color(0xFF006AA7));
        final yellowPaint = Paint()..color = const Color(0xFFFECC02);
        canvas.drawRect(Rect.fromLTWH(w * 0.28, 0, w * 0.16, h), yellowPaint);
        canvas.drawRect(Rect.fromLTWH(0, h * 0.42, w, h * 0.16), yellowPaint);
        break;

      case 'FI':
        canvas.drawRect(Rect.fromLTWH(0, 0, w, h), Paint()..color = Colors.white);
        final bluePaint = Paint()..color = const Color(0xFF002F6C);
        canvas.drawRect(Rect.fromLTWH(w * 0.26, 0, w * 0.18, h), bluePaint);
        canvas.drawRect(Rect.fromLTWH(0, h * 0.41, w, h * 0.18), bluePaint);
        break;

      case 'AR':
        final lightBlue = Paint()..color = const Color(0xFF74ACDF);
        canvas.drawRect(Rect.fromLTWH(0, 0, w, h / 3.0 + 0.5), lightBlue);
        canvas.drawRect(Rect.fromLTWH(0, h / 3.0, w, h / 3.0 + 0.5), Paint()..color = Colors.white);
        canvas.drawRect(Rect.fromLTWH(0, 2.0 * h / 3.0, w, h / 3.0 + 0.5), lightBlue);
        canvas.drawCircle(Offset(w * 0.5, h * 0.5), w * 0.10, Paint()..color = const Color(0xFFF6B40E));
        break;

      case 'CLXY':
        final rect = Rect.fromLTWH(0, 0, w, h);
        final paint = Paint()
          ..shader = const LinearGradient(
            colors: [Color(0xFF00E5FF), Color(0xFF7C3AED), Color(0xFF9333EA)],
          ).createShader(rect);
        canvas.drawRect(rect, paint);
        break;

      default:
        final hash = (code.hashCode & 0x7FFFFFFF) % 360;
        final c1 = HSLColor.fromAHSL(1.0, hash.toDouble(), 0.65, 0.42).toColor();
        final c2 = HSLColor.fromAHSL(1.0, ((hash + 48) % 360).toDouble(), 0.72, 0.30).toColor();
        final rect = Rect.fromLTWH(0, 0, w, h);
        final paint = Paint()
          ..shader = LinearGradient(colors: [c1, c2]).createShader(rect);
        canvas.drawRect(rect, paint);
        break;
    }
  }

  @override
  bool shouldRepaint(covariant _FlagPainter oldDelegate) {
    return oldDelegate.code != code;
  }
}
