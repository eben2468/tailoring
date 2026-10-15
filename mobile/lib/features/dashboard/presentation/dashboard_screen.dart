import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../app/routes.dart';
import '../../../app/section_scaffold.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/feedback.dart';
import '../../../core/widgets/gap.dart';
import '../../../core/widgets/state_views.dart';
import '../../ai/presentation/insight_actions.dart';
import '../../auth/application/session_controller.dart';
import '../../inventory/domain/inventory.dart';
import '../../inventory/presentation/stock_sheet.dart';
import '../../sync/application/sync_providers.dart';
import '../../timer/application/timer_providers.dart';
import '../../timer/presentation/timer_widgets.dart';
import '../../tools/presentation/maintenance_sheet.dart';
import '../application/dashboard_providers.dart';
import '../domain/dashboard.dart';
import 'dashboard_widgets.dart';

/// Dashboard tab — Stitch "Tailor Owner Dashboard": greeting and shop status, KPI tiles, today's workload,
/// the top AI insight, the production schedule (timer, planned stages, appointments, up next), priority
/// jobs and stock / tool alerts. Built from the local copy, so it works offline.
class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  bool _pausing = false;

  Future<void> _pause() async {
    setState(() => _pausing = true);
    try {
      await ref.read(timerActionsProvider).stop();
      if (mounted) showAppSnack(context, 'Paused. Work logged.');
    } on ApiException catch (e) {
      if (mounted) showAppSnack(context, e.message, isError: true);
    } finally {
      if (mounted) setState(() => _pausing = false);
    }
  }

  void _open(ScheduleItem item) {
    final route = switch (item.kind) {
      ScheduleKind.timer when item.jobId != null && item.taskId != null => Routes.taskTimer(item.jobId!, item.taskId!),
      ScheduleKind.appointment when item.appointmentId != null => Routes.appointment(item.appointmentId!),
      _ when item.jobId != null => Routes.job(item.jobId!),
      _ => null,
    };
    if (route != null) unawaited(context.push(route));
  }

  @override
  Widget build(BuildContext context) {
    final dashboard = ref.watch(dashboardProvider);
    return SectionScaffold(
      title: 'Dashboard',
      body: RefreshIndicator(
        edgeOffset: MediaQuery.paddingOf(context).top + 64,
        onRefresh: () => ref.read(syncControllerProvider.notifier).syncNow(),
        child: switch (dashboard) {
          AsyncData(:final value) => _content(value),
          AsyncError(:final error) => ErrorView(error: error, onRetry: () => ref.invalidate(bootstrapProvider)),
          _ => const LoadingView(),
        },
      ),
    );
  }

  Widget _content(Dashboard d) {
    final now = ref.watch(minuteClockProvider);
    final name = ref.watch(sessionControllerProvider).value?.user.firstName;
    final timer = ref.watch(activeTimerProvider).value;
    final greeting = now.hour < 12 ? 'Morning' : (now.hour < 17 ? 'Afternoon' : 'Evening');
    final a = d.appointmentsToday;
    final agenda = a.fittings > 0
        ? '${a.fittings} fitting${a.fittings == 1 ? '' : 's'} scheduled'
        : a.total > 0
        ? '${a.total} appointment${a.total == 1 ? '' : 's'} today'
        : 'No appointments today';
    final next = d.nextUp;
    var queue = 0;

    return ListView(
      padding: belowHeaderAboveNav(context),
      children: [
        // Greeting + shop status
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(name == null ? greeting : '$greeting, $name', style: AppText.headlineLg, maxLines: 1, overflow: TextOverflow.ellipsis),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        width: 24,
                        height: 24,
                        decoration: const BoxDecoration(color: AppColors.secondaryFixed, shape: BoxShape.circle),
                        child: const Icon(Symbols.content_cut, size: 15, color: AppColors.onSecondaryFixed, fill: 1),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${DateFormat('EEEE, d MMM').format(d.date)} • $agenda',
                    style: AppText.bodyMd.copyWith(color: AppColors.onSurfaceVariant),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            Gap.sm,
            ShopPill(shop: d.shop, now: now),
          ],
        ),
        Gap.lg,
        _kpis(d),
        Gap.lg,
        WorkloadCard(workload: d.workload),
        if (d.insights.isNotEmpty) ...[Gap.lg, InsightBanner(insight: d.insights.first, onAct: () => runInsightAction(context, ref, d.insights.first), onDetail: () => context.push(Routes.ai))],
        Gap.xl,

        // Production schedule
        DashboardSection(
          title: 'Production Schedule',
          badge: '${d.schedule.length} ${d.schedule.length == 1 ? 'Task' : 'Tasks'}',
          trailing: next == null || next.taskId == null
              ? null
              : DashboardLink(
                  label: 'Start Next',
                  arrow: true,
                  onTap: () => startTimerFlow(context, ref, jobId: next.jobId!, taskId: next.taskId!, taskName: next.title),
                ),
        ),
        Gap.sm,
        AppCard(
          padding: const EdgeInsets.all(AppSpace.md),
          child: d.schedule.isEmpty
              ? Text('Nothing is planned for today and no job is waiting.', style: AppText.bodyMd.copyWith(color: AppColors.onSurfaceVariant))
              : Column(
                  children: [
                    for (final (i, item) in d.schedule.indexed) ...[
                      if (i > 0) Gap.md,
                      ScheduleRow(
                        item: item,
                        position: item.kind == ScheduleKind.next ? ++queue : 0,
                        isLast: i == d.schedule.length - 1,
                        timer: item.kind == ScheduleKind.timer ? timer : null,
                        onPause: _pause,
                        pausing: _pausing,
                        onTap: () => _open(item),
                      ),
                    ],
                  ],
                ),
        ),
        Gap.xl,

        // Priority jobs
        DashboardSection(
          title: 'Priority Commission Jobs',
          trailing: DashboardLink(label: 'View All ${d.count('open')}', onTap: () => context.go(Routes.jobs)),
        ),
        Gap.sm,
        if (d.priorityJobs.isEmpty)
          AppCard(
            child: Text('No jobs in production.', style: AppText.bodyMd.copyWith(color: AppColors.onSurfaceVariant)),
          )
        else
          for (final (i, job) in d.priorityJobs.indexed) ...[if (i > 0) Gap.md, PriorityJobCard(job: job, onTap: () => context.push(Routes.job(job.id)))],
        Gap.xl,

        // Stock and tools
        DashboardSection(
          title: 'Atelier Health & Stock',
          trailing: Text('${d.alertCount} Alert${d.alertCount == 1 ? '' : 's'}', style: AppText.labelSm.copyWith(color: AppColors.onSurfaceVariant)),
        ),
        Gap.sm,
        if (d.alertCount == 0)
          AppCard(
            child: Row(
              children: [
                const Icon(Symbols.check_circle, size: 20, color: AppColors.onTertiaryContainer),
                Gap.sm,
                Expanded(
                  child: Text('Stock and tools are in good shape.', style: AppText.bodyMd.copyWith(color: AppColors.onSurfaceVariant)),
                ),
              ],
            ),
          )
        else ...[
          for (final item in d.inventoryAlerts) ...[
            AlertRow.material(
              item,
              onTap: () => context.push(Routes.inventoryItem(item.id)),
              onRestock: () async {
                final saved = await showStockSheet(context, itemId: item.id, type: TransactionType.purchase, quantity: item.reorderQuantity);
                if (saved == true && mounted) showAppSnack(context, 'Stock received.');
              },
            ),
            Gap.md,
          ],
          for (final tool in d.maintenanceAlerts) ...[
            AlertRow.tool(
              tool,
              onTap: () => context.push(Routes.tool(tool.id)),
              onLog: () async {
                final saved = await showMaintenanceSheet(context, toolId: tool.id);
                if (saved == true && mounted) showAppSnack(context, 'Maintenance logged.');
              },
            ),
            Gap.md,
          ],
          if (d.inventoryAlertCount > d.inventoryAlerts.length || d.maintenanceAlertCount > d.maintenanceAlerts.length)
            Wrap(
              alignment: WrapAlignment.end,
              spacing: AppSpace.md,
              children: [
                if (d.inventoryAlertCount > d.inventoryAlerts.length) DashboardLink(label: 'All stock alerts (${d.inventoryAlertCount})', onTap: () => context.push(Routes.inventory)),
                if (d.maintenanceAlertCount > d.maintenanceAlerts.length) DashboardLink(label: 'All tool alerts (${d.maintenanceAlertCount})', onTap: () => context.push(Routes.tools)),
              ],
            ),
        ],
      ],
    );
  }

  Widget _kpis(Dashboard d) {
    final a = d.appointmentsToday;
    final visits = [
      if (a.fittings > 0) '${a.fittings} fit${a.fittings == 1 ? '' : 's'}',
      if (a.collections > 0) '${a.collections} collection${a.collections == 1 ? '' : 's'}',
      if (a.fittings == 0 && a.collections == 0 && a.total > 0) '${a.total} appointment${a.total == 1 ? '' : 's'}',
    ];
    final overdue = d.count('overdue');
    final late = d.counts['most_days_late'];
    final active = d.count('active');
    final atFitting = d.count('at_fitting');
    final queued = d.count('queued');
    void jobs() => context.go(Routes.jobs);

    Widget pair(Widget left, Widget right) => IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: left),
          const SizedBox(width: AppSpace.gutter),
          Expanded(child: right),
        ],
      ),
    );

    return Column(
      children: [
        pair(
          KpiTile(
            label: 'Active Jobs',
            value: active,
            icon: Symbols.straighten,
            onTap: jobs,
            footer: KpiNote(atFitting > 0 ? '$atFitting at fitting' : (queued > 0 ? '$queued queued' : 'In production'), color: AppColors.secondary),
          ),
          KpiTile(
            label: 'Due Today',
            value: d.count('due_today'),
            icon: Symbols.schedule,
            iconColor: AppColors.onPrimaryFixedVariant,
            iconBackground: AppColors.surfaceContainerHigh,
            onTap: jobs,
            footer: visits.isEmpty ? const KpiNote('No visits today') : KpiChip(visits.join(', ')),
          ),
        ),
        const SizedBox(height: AppSpace.gutter),
        pair(
          KpiTile(
            label: 'Overdue',
            value: overdue,
            icon: overdue == 0 ? Symbols.check_circle : Symbols.warning,
            iconColor: overdue == 0 ? AppColors.onTertiaryContainer : AppColors.error,
            iconBackground: overdue == 0 ? AppColors.tertiaryFixed.withValues(alpha: 0.4) : AppColors.errorContainer,
            onTap: jobs,
            footer: overdue == 0 ? const KpiNote('All on schedule', color: AppColors.onTertiaryContainer) : KpiNote('Up to $late day${late == 1 ? '' : 's'} late', color: AppColors.error),
          ),
          KpiTile(label: 'This Week', value: d.count('due_this_week'), icon: Symbols.checkroom, iconColor: AppColors.onSurfaceVariant, onTap: jobs, footer: const KpiNote('Due by Sunday')),
        ),
      ],
    );
  }
}
