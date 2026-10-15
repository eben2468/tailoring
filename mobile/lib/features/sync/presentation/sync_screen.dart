import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../app/routes.dart';
import '../../../app/section_scaffold.dart';
import '../../../core/local/local_store.dart';
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
import '../../../core/widgets/status_pill.dart';
import '../application/sync_providers.dart';
import '../domain/local_ops.dart';

/// Strip above the bottom navigation while offline, while changes wait, or when one needs attention.
class SyncBanner extends ConsumerWidget {
  const SyncBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(syncControllerProvider);
    final (String text, Color background, Color foreground, IconData icon)? look = switch (s) {
      SyncStatus(failed: > 0) => ('${s.failed} change${s.failed == 1 ? '' : 's'} need${s.failed == 1 ? 's' : ''} your attention', AppColors.errorContainer, AppColors.onErrorContainer, Symbols.sync_problem),
      SyncStatus(online: false) => (
          s.pending > 0 ? 'Offline · ${s.pending} change${s.pending == 1 ? '' : 's'} saved on this phone' : 'Offline · showing data saved on this phone',
          AppColors.warningContainer,
          AppColors.warning,
          Symbols.cloud_off,
        ),
      SyncStatus(pending: > 0) => ('Syncing ${s.pending} change${s.pending == 1 ? '' : 's'}…', AppColors.secondaryFixed, AppColors.onSecondaryFixedVariant, Symbols.sync),
      _ => null,
    };
    if (look == null) return const SizedBox.shrink();
    return Material(
      color: look.$2,
      child: InkWell(
        onTap: () => context.push(Routes.sync),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpace.margin, vertical: AppSpace.sm),
          child: Row(children: [
            Icon(look.$4, size: 18, color: look.$3),
            Gap.sm,
            Expanded(child: Text(look.$1, style: AppText.labelMd.copyWith(color: look.$3), maxLines: 1, overflow: TextOverflow.ellipsis)),
            Icon(Symbols.chevron_right, size: 18, color: look.$3),
          ]),
        ),
      ),
    );
  }
}

/// Sync: connection state, changes waiting to be sent, and changes the server refused (with the
/// owner's choices: resend, save anyway, keep my version, or discard).
class SyncScreen extends ConsumerWidget {
  const SyncScreen({super.key});

  static const _tables = {
    'customer': Tables.customers,
    'job': Tables.jobs,
    'task': Tables.tasks,
    'checklist': Tables.checklist,
    'worklog': Tables.workLogs,
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(syncControllerProvider);
    final engine = ref.watch(syncEngineProvider);
    final failed = engine.failed;
    final pending = engine.pending;

    Future<void> retry(OutboxItem item, {Map<String, dynamic>? body}) async {
      await engine.retry(item, body: body).catchError((Object _) {});
      if (context.mounted) {
        final still = engine.failed.where((f) => f.seq == item.seq).firstOrNull;
        showAppSnack(context, still == null ? 'Sent.' : (still.errorMessage ?? 'Still refused.'), isError: still != null);
      }
    }

    return DetailScaffold(
      title: 'Sync',
      body: ListView(
        padding: belowHeader(context, bottom: 32),
        children: [
          AppCard(
            padding: const EdgeInsets.all(AppSpace.lg),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                Icon(status.online ? Symbols.cloud_done : Symbols.cloud_off, size: 28, color: status.online ? AppColors.onTertiaryContainer : AppColors.warning),
                Gap.md,
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(status.online ? 'Connected' : 'Offline', style: AppText.headlineMd),
                    Text(
                      status.lastSync == null ? 'Not synced yet on this phone' : 'Last synced ${Fmt.relative(status.lastSync!).toLowerCase()}',
                      style: AppText.bodySm.copyWith(color: AppColors.onSurfaceVariant),
                    ),
                  ]),
                ),
              ]),
              Gap.md,
              Text(
                'Everything you do is saved on this phone first and sent to the server when there is a connection. '
                'Work keeps going without signal.',
                style: AppText.bodyMd.copyWith(color: AppColors.onSurfaceVariant),
              ),
              Gap.lg,
              AppButton(
                label: 'Sync now',
                icon: Symbols.sync,
                variant: AppButtonVariant.tonal,
                expand: true,
                loading: status.syncing,
                onPressed: () => ref.read(syncControllerProvider.notifier).syncNow(),
              ),
            ]),
          ),
          if (failed.isNotEmpty) ...[
            Gap.xl,
            const Kicker('Needs your attention'),
            for (final item in failed) ...[
              _FailedCard(
                item: item,
                onRetry: () => retry(item),
                onSaveAnyway: item.errorCode == 'DUPLICATE_PHONE' ? () => retry(item, body: {...item.body, 'allow_duplicate_phone': true}) : null,
                onKeepMine: item.errorCode == 'CONFLICT_VERSION'
                    ? () async {
                        final route = matchOp(item.method, item.path);
                        final table = _tables[item.op.split('.').first];
                        final current = route == null || table == null || route.params.isEmpty ? null : engine.store.get(table, route.params.first)?['version'];
                        await retry(item, body: {...item.body, 'version': ?current});
                      }
                    : null,
                onDiscard: () async {
                  final ok = await confirmAction(context, title: 'Discard this change?', message: '"${item.label}" will not be saved. The server\'s version is kept.', confirmLabel: 'Discard', destructive: true);
                  if (ok) await engine.discard(item);
                },
              ),
              Gap.sm,
            ],
          ],
          Gap.xl,
          Kicker('Waiting to sync', trailing: Text('${pending.length}', style: AppText.labelMd.copyWith(color: AppColors.onSurfaceVariant))),
          if (pending.isEmpty)
            const AppCard(child: MessageView(icon: Symbols.cloud_done, title: 'All changes are on the server', message: 'Nothing is waiting to be sent.'))
          else
            AppCard(
              child: Column(children: [
                for (final item in pending)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: AppSpace.xs),
                    child: Row(children: [
                      const Icon(Symbols.schedule, size: 18, color: AppColors.onSurfaceVariant),
                      Gap.sm,
                      Expanded(child: Text(item.label, style: AppText.bodyMd)),
                      Text(Fmt.relative(item.createdAt.toLocal()), style: AppText.bodySm.copyWith(color: AppColors.outline)),
                    ]),
                  ),
              ]),
            ),
        ],
      ),
    );
  }
}

class _FailedCard extends StatelessWidget {
  const _FailedCard({required this.item, required this.onRetry, required this.onDiscard, this.onSaveAnyway, this.onKeepMine});

  final OutboxItem item;
  final VoidCallback onRetry;
  final VoidCallback onDiscard;
  final VoidCallback? onSaveAnyway;
  final VoidCallback? onKeepMine;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.all(AppSpace.lg),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(child: Text(item.label, style: AppText.titleSm)),
          StatusPill(label: Fmt.relative(item.createdAt.toLocal()), tone: StatusTone.neutral, showDot: false),
        ]),
        Gap.xs,
        Text(item.errorMessage ?? 'The server refused this change.', style: AppText.bodyMd.copyWith(color: AppColors.onErrorContainer)),
        Gap.md,
        Wrap(spacing: AppSpace.sm, runSpacing: AppSpace.sm, children: [
          if (onSaveAnyway != null) AppButton(label: 'Save anyway', size: AppButtonSize.small, onPressed: onSaveAnyway),
          if (onKeepMine != null) AppButton(label: 'Keep my version', size: AppButtonSize.small, onPressed: onKeepMine),
          if (onSaveAnyway == null && onKeepMine == null) AppButton(label: 'Try again', variant: AppButtonVariant.tonal, size: AppButtonSize.small, onPressed: onRetry),
          AppButton(label: 'Discard', variant: AppButtonVariant.danger, size: AppButtonSize.small, onPressed: onDiscard),
        ]),
      ]),
    );
  }
}
