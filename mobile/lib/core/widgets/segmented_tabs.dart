import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_text.dart';

/// Segmented control from the customer dossier ("Measurements | Commissions | Preferences"):
/// tinted track, selected segment on white with a soft shadow.
class SegmentedTabs extends StatelessWidget {
  const SegmentedTabs({super.key, required this.labels, required this.selected, required this.onChanged});

  final List<String> labels;
  final int selected;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: AppColors.surfaceContainer, borderRadius: AppRadius.control),
      child: Row(
        children: [
          for (var i = 0; i < labels.length; i++)
            Expanded(
              child: Semantics(
                selected: i == selected,
                button: true,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => onChanged(i),
                  child: AnimatedContainer(
                    duration: AppMotion.fast,
                    curve: AppMotion.curve,
                    padding: const EdgeInsets.symmetric(vertical: AppSpace.sm),
                    decoration: BoxDecoration(
                      color: i == selected ? AppColors.surfaceContainerLowest : Colors.transparent,
                      borderRadius: BorderRadius.circular(6),
                      boxShadow: i == selected ? AppShadows.card : null,
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      labels[i],
                      style: AppText.labelMd.copyWith(color: i == selected ? AppColors.onSurface : AppColors.onSurfaceVariant),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
