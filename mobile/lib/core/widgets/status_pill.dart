import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_text.dart';

/// Semantic tone → (text/dot colour, soft background), per DESIGN.md "Status Pills & Chips".
enum StatusTone {
  info(AppColors.onSecondaryFixedVariant, AppColors.secondaryFixed, AppColors.secondary),
  success(AppColors.onTertiaryContainer, Color(0xFFDDFBEE), AppColors.tertiaryFixedDim),
  warning(AppColors.warning, AppColors.warningContainer, AppColors.warningAccent),
  danger(AppColors.onErrorContainer, AppColors.errorContainer, AppColors.error),
  neutral(AppColors.onSurfaceVariant, AppColors.surfaceContainer, AppColors.outline);

  const StatusTone(this.foreground, this.background, this.dot);

  final Color foreground;
  final Color background;
  final Color dot;
}

/// Compact rounded pill with optional 6px status dot ("● In Stock", "High Priority").
class StatusPill extends StatelessWidget {
  const StatusPill({super.key, required this.label, this.tone = StatusTone.neutral, this.showDot = true, this.uppercase = false});

  final String label;
  final StatusTone tone;
  final bool showDot;
  final bool uppercase;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: tone.background, borderRadius: AppRadius.full),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showDot) ...[
            Container(width: 6, height: 6, decoration: BoxDecoration(color: tone.dot, shape: BoxShape.circle)),
            const SizedBox(width: 5),
          ],
          Text(uppercase ? label.toUpperCase() : label, style: AppText.labelSm.copyWith(color: tone.foreground, height: 1.2)),
        ],
      ),
    );
  }
}
