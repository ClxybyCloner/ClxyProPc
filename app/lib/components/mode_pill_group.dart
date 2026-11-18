import 'package:flutter/material.dart';
import '../theme/clxy_colors.dart';

class ModePillGroup extends StatelessWidget {
  final bool isVpn;
  final ValueChanged<bool> onSelectMode;

  const ModePillGroup({
    super.key,
    required this.isVpn,
    required this.onSelectMode,
  });

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 460),
      child: Container(
        padding: const EdgeInsets.all(4.0),
        decoration: BoxDecoration(
          color: const Color(0xD10C1328),
          borderRadius: BorderRadius.circular(999.0),
          border: Border.all(color: const Color(0x2994A3B8), width: 1.0),
        ),
        child: Row(
          children: [
            _buildPill(
              active: isVpn,
              title: 'VPN Mode',
              subtitle: 'All Device',
              onTap: () => onSelectMode(true),
            ),
            const SizedBox(width: 6.0),
            _buildPill(
              active: !isVpn,
              title: 'Proxy Mode',
              subtitle: 'SOCKS5 1080',
              onTap: () => onSelectMode(false),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPill({
    required bool active,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 240),
          curve: Curves.easeOut,
          height: 44.0,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999.0),
            gradient: active
                ? const LinearGradient(
                    colors: [
                      Color(0x3D00E5FF),
                      Color(0x4D3B82F6),
                      Color(0x4D9333EA),
                    ],
                  )
                : null,
            border: Border.all(
              color: active
                  ? ClxyColors.cyanGlow.withOpacity(0.62)
                  : Colors.transparent,
              width: 1.0,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                title,
                style: TextStyle(
                  color: active ? Colors.white : ClxyColors.textMuted,
                  fontSize: 12.0,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 6.0),
              Text(
                subtitle,
                style: TextStyle(
                  color: active ? ClxyColors.cyanText : ClxyColors.textDim,
                  fontSize: 10.0,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
