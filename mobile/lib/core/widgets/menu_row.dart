import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_text.dart';
import 'app_card.dart';

/// Icon tile + title/subtitle + trailing — the row pattern from the "Atelier Health & Stock" list.
class MenuRow extends StatelessWidget {
  const MenuRow({super.key, required this.icon, required this.title, this.subtitle, this.onTap, this.trailing, this.destructive = false, this.subtitleColor});

  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;
  final Widget? trailing;
  final bool destructive;
  final Color? subtitleColor;

  @override
  Widget build(BuildContext context) {
    final titleColor = destructive ? AppColors.error : AppColors.onSurface;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpace.md, vertical: AppSpace.md - 2),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(color: destructive ? AppColors.errorContainer : AppColors.surfaceContainerHigh, borderRadius: AppRadius.control),
              child: Icon(icon, size: 20, color: destructive ? AppColors.error : AppColors.onSurface),
            ),
            const SizedBox(width: AppSpace.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: AppText.titleSm.copyWith(color: titleColor),
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (subtitle != null)
                    Text(
                      subtitle!,
                      style: AppText.bodySm.copyWith(color: subtitleColor ?? AppColors.onSurfaceVariant),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 2,
                    ),
                ],
              ),
            ),
            if (trailing != null) trailing! else if (onTap != null) const Icon(Symbols.chevron_right, size: 20, color: AppColors.outline),
          ],
        ),
      ),
    );
  }
}

/// A card holding [MenuRow]s separated by hairlines.
class MenuGroup extends StatelessWidget {
  const MenuGroup({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: EdgeInsets.zero,
      child: ClipRRect(
        borderRadius: AppRadius.card,
        child: Column(
          children: [
            for (var i = 0; i < children.length; i++) ...[if (i > 0) const Divider(indent: 64), children[i]],
          ],
        ),
      ),
    );
  }
}
