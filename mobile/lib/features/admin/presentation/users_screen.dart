import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../app/routes.dart';
import '../../../app/section_scaffold.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/gap.dart';
import '../../../core/widgets/initials_avatar.dart';
import '../../../core/widgets/state_views.dart';
import '../../../core/widgets/status_pill.dart';
import '../application/admin_providers.dart';
import '../data/admin_api.dart';

/// Admin: owner/admin accounts.
class UsersScreen extends ConsumerWidget {
  const UsersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final users = ref.watch(adminUsersProvider);

    return DetailScaffold(
      title: 'Users',
      actions: [
        Padding(
          padding: const EdgeInsets.only(right: AppSpace.xs),
          child: AppButton(label: 'Add', icon: Symbols.person_add, size: AppButtonSize.small, onPressed: () => context.push(Routes.adminUserNew)),
        ),
      ],
      body: switch (users) {
        AsyncData(:final value) => RefreshIndicator(
            onRefresh: () => ref.refresh(adminUsersProvider.future),
            edgeOffset: MediaQuery.paddingOf(context).top + 64,
            child: ListView.separated(
              padding: belowHeader(context),
              itemCount: value.items.length,
              separatorBuilder: (_, _) => Gap.sm,
              itemBuilder: (context, i) => UserCard(user: value.items[i], onTap: () => context.push(Routes.adminUser(value.items[i].id))),
            ),
          ),
        AsyncError(:final error) => ErrorView(error: error, onRetry: () => ref.invalidate(adminUsersProvider)),
        _ => const LoadingView(),
      },
    );
  }
}

/// Account summary card (avatar, name, email, role and status pills).
class UserCard extends StatelessWidget {
  const UserCard({super.key, required this.user, this.onTap});

  final AdminUser user;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      onTap: onTap,
      child: Row(children: [
        InitialsAvatar(name: user.fullName, dark: user.role == 'admin'),
        Gap.md,
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(user.fullName, style: AppText.titleSm, overflow: TextOverflow.ellipsis),
            Text(user.email, style: AppText.bodySm.copyWith(color: AppColors.onSurfaceVariant), overflow: TextOverflow.ellipsis),
            Gap.xs,
            Wrap(spacing: 6, runSpacing: 4, children: [
              StatusPill(label: user.role == 'admin' ? 'Admin' : 'Owner', tone: StatusTone.info, showDot: false),
              userStatusPill(user),
            ]),
          ]),
        ),
        if (onTap != null) const Icon(Symbols.chevron_right, size: 20, color: AppColors.outline),
      ]),
    );
  }
}

StatusPill userStatusPill(AdminUser user) => switch (user) {
      AdminUser(isActive: false) => const StatusPill(label: 'Deactivated', tone: StatusTone.neutral),
      AdminUser(isLocked: true) => const StatusPill(label: 'Locked', tone: StatusTone.danger),
      AdminUser(lastLoginAt: final at?) => StatusPill(label: 'Active · ${Fmt.relative(at)}', tone: StatusTone.success),
      _ => const StatusPill(label: 'Never signed in', tone: StatusTone.warning),
    };
