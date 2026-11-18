import 'package:flutter/material.dart';
import '../theme/clxy_colors.dart';

class ProfileMenuCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final String? badgeText;
  final VoidCallback onClick;

  const ProfileMenuCard({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.badgeText,
    required this.onClick,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onClick,
      borderRadius: BorderRadius.circular(12.0),
      child: Container(
        constraints: const BoxConstraints(minHeight: 60.0),
        padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 12.0),
        decoration: BoxDecoration(
          color: ClxyColors.cardSurface,
          borderRadius: BorderRadius.circular(12.0),
          border: Border.all(color: ClxyColors.glassBorder, width: 1.0),
        ),
        child: Row(
          children: [
            Container(
              width: 36.0,
              height: 36.0,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: ClxyColors.blueDeep.withOpacity(0.22),
              ),
              child: Icon(icon, color: ClxyColors.cyanGlow, size: 19.0),
            ),
            const SizedBox(width: 12.0),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          color: ClxyColors.textPrimary,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (badgeText != null) ...[
                        const SizedBox(width: 6.0),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6.0, vertical: 1.0),
                          decoration: BoxDecoration(
                            color: ClxyColors.cyanGlow.withOpacity(0.18),
                            borderRadius: BorderRadius.circular(999.0),
                          ),
                          child: Text(
                            badgeText!,
                            style: const TextStyle(
                              color: ClxyColors.cyanText,
                              fontSize: 9.0,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2.0),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      color: ClxyColors.textMuted,
                      fontSize: 11.0,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
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
    );
  }
}

class SheetHeader extends StatelessWidget {
  final String title;
  final VoidCallback onDismiss;

  const SheetHeader({
    super.key,
    required this.title,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
      decoration: const BoxDecoration(
        color: ClxyColors.modalSurface,
        border: Border(
          bottom: BorderSide(color: ClxyColors.glassBorder, width: 0.5),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: ClxyColors.textPrimary,
              fontSize: 16.0,
              fontWeight: FontWeight.bold,
            ),
          ),
          IconButton(
            onPressed: onDismiss,
            icon: const Icon(Icons.close_rounded, color: ClxyColors.textPrimary),
            splashRadius: 20.0,
          ),
        ],
      ),
    );
  }
}

class SettingSwitchRow extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool checked;
  final ValueChanged<bool> onCheckedChange;

  const SettingSwitchRow({
    super.key,
    required this.title,
    required this.subtitle,
    required this.checked,
    required this.onCheckedChange,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => onCheckedChange(!checked),
      borderRadius: BorderRadius.circular(12.0),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 10.0),
        decoration: BoxDecoration(
          color: ClxyColors.cardSurface,
          borderRadius: BorderRadius.circular(12.0),
          border: Border.all(color: ClxyColors.glassBorder, width: 1.0),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: ClxyColors.textPrimary,
                      fontSize: 13.0,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2.0),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      color: ClxyColors.textMuted,
                      fontSize: 11.0,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10.0),
            Switch(
              value: checked,
              onChanged: onCheckedChange,
              activeThumbColor: ClxyColors.bgTop,
              activeTrackColor: ClxyColors.cyanGlow,
              inactiveThumbColor: ClxyColors.textMuted,
              inactiveTrackColor: ClxyColors.barInactive,
            ),
          ],
        ),
      ),
    );
  }
}

class ChoiceRow extends StatelessWidget {
  final String title;
  final List<MapEntry<String, String>> options;
  final String selected;
  final ValueChanged<String> onSelect;

  const ChoiceRow({
    super.key,
    required this.title,
    required this.options,
    required this.selected,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: ClxyColors.textMuted,
            fontSize: 12.0,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 6.0),
        Row(
          children: options.map((opt) {
            final isSelected = selected == opt.key;
            return Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3.0),
                child: InkWell(
                  onTap: () => onSelect(opt.key),
                  borderRadius: BorderRadius.circular(8.0),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6.0, vertical: 9.0),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: isSelected
                          ? ClxyColors.blueDeep.withOpacity(0.50)
                          : ClxyColors.cardSurface,
                      borderRadius: BorderRadius.circular(8.0),
                      border: Border.all(
                        color: isSelected
                            ? ClxyColors.cyanGlow
                            : ClxyColors.glassBorder,
                        width: 1.0,
                      ),
                    ),
                    child: Text(
                      opt.value,
                      style: TextStyle(
                        color: isSelected ? Colors.white : ClxyColors.textSecondary,
                        fontSize: 11.0,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }
}
