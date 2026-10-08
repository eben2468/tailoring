import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../app/modules.dart';
import '../../../app/routes.dart';
import '../../../app/section_scaffold.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/feedback.dart';
import '../../../core/widgets/gap.dart';
import '../../../core/widgets/initials_avatar.dart';
import '../../../core/widgets/menu_row.dart';
import '../../../core/widgets/section_header.dart';
import '../../auth/application/session_controller.dart';

/// "More" tab: business modules, account, administration (admin only) and sign-out.
class MoreScreen extends ConsumerWidget {
  const MoreScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionControllerProvider).value;
    final user = session?.user;

    return SectionScaffold(
      title: 'More',
      body: ListView(
        padding: belowHeaderAboveNav(context),
        children: [
          if (user != null)
            AppCard(
              onTap: () => context.push(Routes.profile),
              child: Row(children: [
                InitialsAvatar(name: user.fullName, size: 48, dark: true),
                Gap.md,
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(user.fullName, style: AppText.titleSm, overflow: TextOverflow.ellipsis),
                    Text(user.email, style: AppText.bodySm.copyWith(color: AppColors.onSurfaceVariant), overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 2),
                    Text(
                      '${user.isAdmin ? 'System admin' : 'Owner'} · ${session!.business.name}',
                      style: AppText.labelSm.copyWith(color: AppColors.secondary),
                    ),
                  ]),
                ),
                const Icon(Symbols.chevron_right, size: 20, color: AppColors.outline),
              ]),
            ),
          Gap.xl,
          const Kicker('Atelier'),
          MenuGroup(children: [
            for (final module in const [AppModule.inventory, AppModule.tools, AppModule.reports, AppModule.ai])
              MenuRow(
                icon: module.icon,
                title: module.title,
                subtitle: module.description,
                onTap: () => context.push(Routes.module(module.name)),
              ),
          ]),
          Gap.xl,
          const Kicker('Settings'),
          MenuGroup(children: [
            MenuRow(
              icon: Symbols.apparel,
              title: 'Garment templates',
              subtitle: 'Production stages and standard hours for each garment',
              onTap: () => context.push(Routes.garmentTypes),
            ),
          ]),
          Gap.xl,
          const Kicker('Account'),
          MenuGroup(children: [
            MenuRow(icon: Symbols.person, title: 'Profile', subtitle: 'Name and phone number', onTap: () => context.push(Routes.profile)),
            MenuRow(icon: Symbols.key, title: 'Change password', subtitle: 'Signs out your other devices', onTap: () => context.push(Routes.changePassword)),
            MenuRow(icon: Symbols.notifications, title: 'Notifications', subtitle: AppModule.notifications.description, onTap: () => context.push(Routes.notifications)),
          ]),
          if (user?.isAdmin ?? false) ...[
            Gap.xl,
            const Kicker('System administration'),
            MenuGroup(children: [
              MenuRow(icon: Symbols.manage_accounts, title: 'Users', subtitle: 'Owner and admin accounts', onTap: () => context.push(Routes.adminUsers)),
              MenuRow(icon: Symbols.history, title: 'Audit log', subtitle: 'Sign-ins and sensitive changes', onTap: () => context.push(Routes.auditLog)),
            ]),
          ],
          Gap.xl,
          MenuGroup(children: [
            MenuRow(
              icon: Symbols.logout,
              title: 'Sign out',
              destructive: true,
              onTap: () async {
                final ok = await confirmAction(context, title: 'Sign out?', message: 'You will need your email and password to sign in again.', confirmLabel: 'Sign out', destructive: true);
                if (ok) await ref.read(sessionControllerProvider.notifier).signOut();
              },
            ),
          ]),
          Gap.lg,
          Text('Nutɔfe · v1.0.0', style: AppText.bodySm.copyWith(color: AppColors.outline), textAlign: TextAlign.center),
        ],
      ),
    );
  }
}
