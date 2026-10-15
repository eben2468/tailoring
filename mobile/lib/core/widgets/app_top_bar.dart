import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_text.dart';
import 'brand_mark.dart';
import 'initials_avatar.dart';

/// The 64px frosted header from the Stitch screens.
///
/// * Tab screens:    logo + "Nutɔfe [Studio]" + section name · bell · avatar
/// * Detail screens: back · "NUTƆFE" overline + screen title · bell · avatar (+ optional actions)
class AppTopBar extends StatelessWidget implements PreferredSizeWidget {
  const AppTopBar.section({super.key, required this.title, this.userName, this.onNotifications, this.onAvatar, this.hasUnread = false}) : isDetail = false, actions = const [];

  const AppTopBar.detail({super.key, required this.title, this.userName, this.onNotifications, this.onAvatar, this.hasUnread = false, this.actions = const []}) : isDetail = true;

  final String title;
  final bool isDetail;
  final String? userName;
  final VoidCallback? onNotifications;
  final VoidCallback? onAvatar;
  final bool hasUnread;
  final List<Widget> actions;

  @override
  Size get preferredSize => const Size.fromHeight(64);

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: Container(
          decoration: BoxDecoration(color: AppColors.surface.withValues(alpha: 0.8), boxShadow: AppShadows.header),
          child: SafeArea(
            bottom: false,
            child: SizedBox(
              height: 64,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpace.margin),
                child: Row(
                  children: [
                    if (isDetail) ...[
                      Transform.translate(
                        offset: const Offset(-8, 0),
                        child: IconButton(
                          tooltip: 'Back',
                          onPressed: () => Navigator.of(context).maybePop(),
                          icon: const Icon(Symbols.arrow_back, size: 22, color: AppColors.onSurface),
                          style: IconButton.styleFrom(minimumSize: const Size(44, 44)),
                        ),
                      ),
                      Expanded(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('NUTƆFE', style: AppText.overline),
                            Text(title, style: AppText.titleSm, overflow: TextOverflow.ellipsis, maxLines: 1),
                          ],
                        ),
                      ),
                    ] else ...[
                      const BrandMark(),
                      const SizedBox(width: AppSpace.sm),
                      Expanded(child: BrandTitle(subtitle: title)),
                    ],
                    ...actions,
                    if (onNotifications != null) _BellButton(onPressed: onNotifications!, hasUnread: hasUnread),
                    if (onAvatar != null)
                      Padding(
                        padding: const EdgeInsets.only(left: AppSpace.xs),
                        child: InkResponse(
                          onTap: onAvatar,
                          radius: 22,
                          child: Semantics(
                            button: true,
                            label: 'Profile',
                            child: InitialsAvatar(name: userName ?? '', size: 32, ring: true),
                          ),
                        ),
                      ),
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

class _BellButton extends StatelessWidget {
  const _BellButton({required this.onPressed, required this.hasUnread});

  final VoidCallback onPressed;
  final bool hasUnread;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: 'Notifications',
      onPressed: onPressed,
      style: IconButton.styleFrom(minimumSize: const Size(44, 44)),
      icon: Stack(
        clipBehavior: Clip.none,
        children: [
          const Icon(Symbols.notifications, size: 22, color: AppColors.onSurfaceVariant),
          if (hasUnread)
            Positioned(
              top: 0,
              right: 1,
              child: Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: AppColors.secondary,
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.surface, width: 2),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
