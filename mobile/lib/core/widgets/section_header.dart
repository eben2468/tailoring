import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_text.dart';

/// "Production Schedule [4 Tasks] ........ Start Next →" — headline-md title, optional count chip and link.
class SectionHeader extends StatelessWidget {
  const SectionHeader({super.key, required this.title, this.count, this.actionLabel, this.onAction});

  final String title;
  final String? count;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Flexible(
          child: Text(title, style: AppText.headlineMd, overflow: TextOverflow.ellipsis),
        ),
        if (count != null) ...[
          const SizedBox(width: AppSpace.sm),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(color: AppColors.surfaceContainer, borderRadius: AppRadius.full),
            child: Text(count!, style: AppText.labelSm.copyWith(color: AppColors.onSurfaceVariant)),
          ),
        ],
        const Spacer(),
        if (actionLabel != null && onAction != null)
          InkWell(
            onTap: onAction,
            borderRadius: AppRadius.small,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
              child: Text(actionLabel!, style: AppText.labelMd.copyWith(color: AppColors.secondary)),
            ),
          ),
      ],
    );
  }
}

/// Uppercase kicker above a group of rows/fields ("PATRON PROFILE", "ACCOUNT").
class Kicker extends StatelessWidget {
  const Kicker(this.text, {super.key, this.trailing});

  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 2, bottom: AppSpace.sm),
      child: Row(
        children: [
          Expanded(child: Text(text.toUpperCase(), style: AppText.overline)),
          ?trailing,
        ],
      ),
    );
  }
}
