import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_text.dart';

/// Nutɔfe monogram shown where the Stitch screens place the studio logo.
/// The final logo file will replace this widget's body (one place to change).
class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.size = 32, this.onDark = false});

  final double size;

  /// White tile with a navy letter, for navy backgrounds (sign-in panel).
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: onDark ? AppColors.surfaceContainerLowest : AppColors.primaryContainer, borderRadius: BorderRadius.circular(size * 0.28)),
      child: Text(
        'N',
        style: AppText.titleSm.copyWith(color: onDark ? AppColors.primaryContainer : AppColors.onPrimary, fontSize: size * 0.5, height: 1, fontWeight: FontWeight.w700),
      ),
    );
  }
}

/// Brand name + "Studio" status chip, as in the dashboard header.
class BrandTitle extends StatelessWidget {
  const BrandTitle({super.key, required this.subtitle});

  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text('Nutɔfe', style: AppText.titleSm, overflow: TextOverflow.ellipsis),
            ),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(color: AppColors.surfaceContainerHigh, borderRadius: AppRadius.full),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: const BoxDecoration(color: AppColors.tertiaryFixedDim, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 4),
                  Text('Studio', style: AppText.labelSm.copyWith(fontSize: 10, color: AppColors.onSurfaceVariant, height: 1.2)),
                ],
              ),
            ),
          ],
        ),
        Text(subtitle.toUpperCase(), style: AppText.overline, overflow: TextOverflow.ellipsis),
      ],
    );
  }
}
