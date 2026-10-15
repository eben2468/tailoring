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
import '../../notifications/application/notification_providers.dart';
import '../../sync/application/sync_providers.dart';

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
                onTap: () => context.push(switch (module) {
                  AppModule.inventory => Routes.inventory,
                  AppModule.tools => Routes.tools,
                  AppModule.reports => Routes.reports,
                  AppModule.ai => Routes.ai,
                  _ => Routes.module(module.name),
                }),
              ),
          ]),
          Gap.xl,
          const Kicker('Settings'),
          MenuGroup(children: [
            Builder(builder: (context) {
              final s = ref.watch(syncControllerProvider);
              return MenuRow(
                icon: s.online ? Symbols.cloud_done : Symbols.cloud_off,
                title: 'Sync',
                subtitle: s.failed > 0
                    ? '${s.failed} change${s.failed == 1 ? '' : 's'} need${s.failed == 1 ? 's' : ''} your attention'
                    : s.pending > 0
                        ? '${s.pending} change${s.pending == 1 ? '' : 's'} waiting to be sent'
                        : (s.online ? 'Everything is on the server' : 'Offline · working from this phone'),
                subtitleColor: s.failed > 0 ? AppColors.error : null,
                onTap: () => context.push(Routes.sync),
              );
            }),
            MenuRow(
              icon: Symbols.apparel,
              title: 'Garment templates',
              subtitle: 'Production stages and standard hours for each garment',
              onTap: () => context.push(Routes.garmentTypes),
            ),
            MenuRow(
              icon: Symbols.category,
              title: 'Material categories',
              subtitle: 'How inventory is grouped',
              onTap: () => context.push(Routes.inventoryCategories),
            ),
            MenuRow(
              icon: Symbols.precision_manufacturing,
              title: 'Tool categories',
              subtitle: 'How equipment is grouped',
              onTap: () => context.push(Routes.toolCategories),
            ),
          ]),
          Gap.xl,
          const Kicker('Account'),
          MenuGroup(children: [
            MenuRow(icon: Symbols.person, title: 'Profile', subtitle: 'Name and phone number', onTap: () => context.push(Routes.profile)),
            MenuRow(icon: Symbols.key, title: 'Change password', subtitle: 'Signs out your other devices', onTap: () => context.push(Routes.changePassword)),
            Builder(builder: (context) {
              final unread = ref.watch(unreadNotificationsProvider);
              return MenuRow(
                icon: Symbols.notifications,
                title: 'Notifications',
                subtitle: unread == 0 ? 'Deadlines, fittings, stock and tool service' : '$unread unread',
                subtitleColor: unread == 0 ? null : AppColors.secondary,
                onTap: () => context.push(Routes.notifications),
              );
            }),
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
                final waiting = ref.read(syncControllerProvider).pending + ref.read(syncControllerProvider).failed;
                final ok = await confirmAction(
                  context,
                  title: 'Sign out?',
                  message: waiting > 0
                      ? '$waiting change${waiting == 1 ? ' has' : 's have'} not reached the server yet and will be lost. Connect to the internet and sync first to keep ${waiting == 1 ? 'it' : 'them'}.'
                      : 'The business data is removed from this phone. You will need your email and password to sign in again.',
                  confirmLabel: 'Sign out',
                  destructive: true,
                );
                if (!ok) return;
                await ref.read(sessionControllerProvider.notifier).signOut();
                ref.read(localStoreProvider).wipe(); // customer data does not stay on a signed-out phone
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
