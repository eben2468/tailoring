import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';

/// Dark navy feature panel (Stitch: bg-primary-container, rounded-xl, shadow-md) with the designs' soft blue
/// glow in the bottom-right corner (`bg-secondary/15 rounded-full blur-2xl`) and an optional faint watermark
/// icon (the timer and production-status panels). Used for the AI insight, production status, workload,
/// timer and fleet panels so they all read as one family.
class HeroPanel extends StatelessWidget {
  const HeroPanel({super.key, required this.child, this.padding = const EdgeInsets.all(AppSpace.lg), this.watermark, this.radius});

  final Widget child;
  final EdgeInsetsGeometry padding;

  /// Large faint icon in the corner, e.g. Symbols.timer.
  final IconData? watermark;
  final BorderRadius? radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(color: AppColors.primaryContainer, borderRadius: radius ?? AppRadius.card, boxShadow: AppShadows.raised),
      child: Stack(
        children: [
          Positioned(
            right: -40,
            bottom: -40,
            child: IgnorePointer(
              child: Container(
                width: 150,
                height: 150,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(colors: [AppColors.secondary.withValues(alpha: 0.28), AppColors.secondary.withValues(alpha: 0)]),
                ),
              ),
            ),
          ),
          if (watermark != null)
            Positioned(
              right: -18,
              bottom: -22,
              child: IgnorePointer(child: Icon(watermark, size: 132, color: AppColors.onPrimary.withValues(alpha: 0.05))),
            ),
          Padding(padding: padding, child: child),
        ],
      ),
    );
  }
}
