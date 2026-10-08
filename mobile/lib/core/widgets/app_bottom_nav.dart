import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_text.dart';

/// One destination in the bottom dock.
class NavDestination {
  const NavDestination(this.label, this.icon);

  final String label;
  final IconData icon;
}

/// The five destinations from the Stitch bottom bar, in order.
const appDestinations = [
  NavDestination('Dashboard', Symbols.grid_view),
  NavDestination('Jobs', Symbols.content_cut),
  NavDestination('Calendar', Symbols.calendar_month),
  NavDestination('Customers', Symbols.contacts),
  NavDestination('More', Symbols.widgets),
];

/// 64px frosted dock: active item in midnight navy (semibold) with a 24×2 indicator bar above
/// the icon; inactive items in on-surface-variant.
class AppBottomNav extends StatelessWidget {
  const AppBottomNav({super.key, required this.currentIndex, required this.onSelected, this.destinations = appDestinations});

  final int currentIndex;
  final ValueChanged<int> onSelected;
  final List<NavDestination> destinations;

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: Container(
          decoration: BoxDecoration(color: AppColors.surface.withValues(alpha: 0.9), boxShadow: AppShadows.bottomBar),
          child: SafeArea(
            top: false,
            child: SizedBox(
              height: 64,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpace.xs),
                child: Row(
                  children: [
                    for (var i = 0; i < destinations.length; i++)
                      Expanded(child: _NavItem(destination: destinations[i], selected: i == currentIndex, onTap: () => onSelected(i))),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({required this.destination, required this.selected, required this.onTap});

  final NavDestination destination;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? AppColors.primaryContainer : AppColors.onSurfaceVariant;
    return Semantics(
      selected: selected,
      button: true,
      label: destination.label,
      child: InkResponse(
        onTap: onTap,
        containedInkWell: true,
        highlightShape: BoxShape.rectangle,
        child: Stack(
          alignment: Alignment.center,
          fit: StackFit.expand, // indicator is positioned against the full 64px item, above the icon
          children: [
            Positioned(
              top: 6,
              child: AnimatedOpacity(
                opacity: selected ? 1 : 0,
                duration: AppMotion.fast,
                child: Container(width: 24, height: 2, decoration: BoxDecoration(color: AppColors.primaryContainer, borderRadius: AppRadius.full)),
              ),
            ),
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(destination.icon, size: 22, color: color, weight: selected ? 500 : 400),
                const SizedBox(height: 2),
                Text(
                  destination.label,
                  style: AppText.labelSm.copyWith(
                    color: color,
                    letterSpacing: -0.1,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.fade,
                  softWrap: false,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
