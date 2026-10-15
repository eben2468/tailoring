import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';

/// White content card: 12px radius + Tailwind shadow-sm, on the #F9F9FF canvas.
class AppCard extends StatelessWidget {
  const AppCard({super.key, required this.child, this.padding = const EdgeInsets.all(AppSpace.md), this.onTap, this.color});

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final content = Padding(padding: padding, child: child);
    return DecoratedBox(
      decoration: BoxDecoration(color: color ?? AppColors.surfaceContainerLowest, borderRadius: AppRadius.card, boxShadow: AppShadows.card),
      child: onTap == null
          ? content
          : Material(
              type: MaterialType.transparency,
              borderRadius: AppRadius.card,
              clipBehavior: Clip.antiAlias,
              child: InkWell(onTap: onTap, child: content),
            ),
    );
  }
}

/// Tinted inner tile (bg surface-container-low, 8px radius) — e.g. the
/// "LOGGED / REMAINING / DUE DATE" boxes and measurement cells.
class InsetTile extends StatelessWidget {
  const InsetTile({super.key, required this.child, this.padding = const EdgeInsets.all(AppSpace.sm), this.color});

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(color: color ?? AppColors.surfaceContainerLow, borderRadius: AppRadius.control),
      child: child,
    );
  }
}
