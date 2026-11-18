import 'package:flutter/material.dart';
import '../theme/clxy_colors.dart';

enum MainTab { home, servers, profile }

class ClxyBottomNavBar extends StatelessWidget {
  final MainTab activeTab;
  final ValueChanged<MainTab> onSelectTab;
  final bool isQuantum;

  const ClxyBottomNavBar({
    super.key,
    required this.activeTab,
    required this.onSelectTab,
    this.isQuantum = false,
  });

  @override
  Widget build(BuildContext context) {
    final activeTint =
        isQuantum ? ClxyColors.quantumPurple : ClxyColors.cyanBright;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: Container(
        height: 62.0,
        decoration: BoxDecoration(
          color: ClxyColors.obsidianCard.withOpacity(0.96),
          borderRadius: BorderRadius.circular(22.0),
          border: Border.all(color: ClxyColors.obsidianBorder, width: 1.0),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.4),
              blurRadius: 14.0,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        padding: const EdgeInsets.symmetric(horizontal: 6.0),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _buildNavItem(
              selected: activeTab == MainTab.home,
              label: 'Home',
              activeColor: activeTint,
              icon: Icons.home_rounded,
              unselectedIcon: Icons.home_outlined,
              onTap: () => onSelectTab(MainTab.home),
            ),
            if (!isQuantum) ...[
              _buildNavItem(
                selected: activeTab == MainTab.servers,
                label: 'Servers',
                activeColor: activeTint,
                icon: Icons.public_rounded,
                unselectedIcon: Icons.public_outlined,
                onTap: () => onSelectTab(MainTab.servers),
              ),
              _buildNavItem(
                selected: activeTab == MainTab.profile,
                label: 'Profile',
                activeColor: activeTint,
                icon: Icons.tune_rounded,
                unselectedIcon: Icons.tune_outlined,
                onTap: () => onSelectTab(MainTab.profile),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildNavItem({
    required bool selected,
    required String label,
    required Color activeColor,
    required IconData icon,
    required IconData unselectedIcon,
    required VoidCallback onTap,
  }) {
    final tint = selected ? activeColor : ClxyColors.textDim;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12.0),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 6.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedScale(
              scale: selected ? 1.08 : 1.0,
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOutBack,
              child: Icon(
                selected ? icon : unselectedIcon,
                color: tint,
                size: 20.0,
              ),
            ),
            const SizedBox(height: 3.0),
            Text(
              label,
              style: TextStyle(
                color: tint,
                fontSize: 10.0,
                fontWeight: selected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
            if (selected) ...[
              const SizedBox(height: 2.0),
              Container(
                width: 3.0,
                height: 3.0,
                decoration: BoxDecoration(
                  color: activeColor,
                  shape: BoxShape.circle,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
