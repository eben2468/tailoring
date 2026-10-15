import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../app/section_scaffold.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/feedback.dart';
import '../../../core/widgets/gap.dart';
import '../../../core/widgets/section_header.dart';
import '../../../core/widgets/state_views.dart';
import '../../sync/application/sync_providers.dart';
import '../application/notification_providers.dart';
import '../domain/app_notification.dart';

/// The bell: deadlines, fittings, stock, tool service and forgotten timers (not designed in Stitch;
/// built from the design system). Opening one marks it read and goes to what it is about.
class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

  Future<void> _open(BuildContext context, WidgetRef ref, AppNotification n) async {
    try {
      await ref.read(notificationsApiProvider).markRead(n);
    } on ApiException catch (e) {
      if (context.mounted) showAppSnack(context, e.message, isError: true);
    }
    if (n.route != null && n.route!.isNotEmpty && context.mounted) unawaited(context.push(n.route!));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = ref.watch(notificationsProvider);
    final unread = ref.watch(unreadNotificationsProvider);
    return DetailScaffold(
      title: 'Notifications',
      body: RefreshIndicator(
        edgeOffset: MediaQuery.paddingOf(context).top + 64,
        onRefresh: () => ref.read(syncControllerProvider.notifier).syncNow(),
        child: switch (list) {
          AsyncData(:final value) when value.isEmpty => ListView(padding: belowHeader(context), children: const [
              SizedBox(
                height: 480,
                child: MessageView(
                  icon: Symbols.notifications_none,
                  title: 'All quiet',
                  message: 'Deadlines, fittings, low stock, tool service and forgotten timers will appear here.',
                ),
              ),
            ]),
          AsyncData(:final value) => () {
              final today = DateTime.now();
              bool isToday(DateTime d) => d.year == today.year && d.month == today.month && d.day == today.day;
              final todays = value.where((n) => isToday(n.createdAt)).toList();
              final earlier = value.where((n) => !isToday(n.createdAt)).toList();
              return ListView(padding: belowHeader(context), children: [
                Row(children: [
                  Expanded(
                    child: Text(unread == 0 ? 'Everything read' : '$unread unread', style: AppText.bodyMd.copyWith(color: AppColors.onSurfaceVariant)),
                  ),
                  if (unread > 0)
                    AppButton(
                      label: 'Mark all read',
                      icon: Symbols.done_all,
                      variant: AppButtonVariant.text,
                      size: AppButtonSize.small,
                      onPressed: () async {
                        try {
                          await ref.read(notificationsApiProvider).markAllRead();
                        } on ApiException catch (e) {
                          if (context.mounted) showAppSnack(context, e.message, isError: true);
                        }
                      },
                    ),
                ]),
                for (final (title, group) in [('Today', todays), ('Earlier', earlier)])
                  if (group.isNotEmpty) ...[
                    Gap.md,
                    Kicker(title),
                    Gap.sm,
                    AppCard(
                      padding: EdgeInsets.zero,
                      child: Column(children: [
                        for (final (i, n) in group.indexed) ...[
                          if (i > 0) const Divider(height: 1, indent: 64, color: AppColors.surfaceContainer),
                          _NotificationRow(n: n, onTap: () => _open(context, ref, n)),
                        ],
                      ]),
                    ),
                  ],
              ]);
            }(),
          AsyncError(:final error) => ListView(padding: belowHeader(context), children: [SizedBox(height: 480, child: ErrorView(error: error, onRetry: () => ref.invalidate(bootstrapProvider)))]),
          _ => const LoadingView(),
        },
      ),
    );
  }
}

class _NotificationRow extends StatelessWidget {
  const _NotificationRow({required this.n, required this.onTap});

  final AppNotification n;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final (tint, color) = switch (n.severity) {
      NotificationSeverity.critical => (AppColors.errorContainer, AppColors.error),
      NotificationSeverity.warning => (AppColors.warningContainer, AppColors.warning),
      NotificationSeverity.info => (AppColors.surfaceContainerHigh, AppColors.secondary),
    };
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(AppSpace.md),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(color: tint, borderRadius: AppRadius.control),
            child: Icon(n.icon, size: 20, color: color),
          ),
          Gap.md,
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(n.title, style: AppText.labelMd.copyWith(fontWeight: n.isUnread ? FontWeight.w700 : FontWeight.w500, color: AppColors.onSurface)),
              if (n.body != null) ...[const SizedBox(height: 2), Text(n.body!, style: AppText.bodySm.copyWith(color: AppColors.onSurfaceVariant))],
              const SizedBox(height: 4),
              Text(Fmt.relative(n.createdAt), style: AppText.labelSm.copyWith(color: AppColors.outline, fontWeight: FontWeight.w500)),
            ]),
          ),
          if (n.isUnread) ...[
            Gap.sm,
            Container(width: 8, height: 8, margin: const EdgeInsets.only(top: 6), decoration: const BoxDecoration(color: AppColors.secondary, shape: BoxShape.circle)),
          ],
        ]),
      ),
    );
  }
}
