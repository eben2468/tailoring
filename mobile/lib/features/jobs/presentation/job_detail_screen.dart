import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../app/routes.dart';
import '../../../app/section_scaffold.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/bottom_action_bar.dart';
import '../../../core/widgets/feedback.dart';
import '../../../core/widgets/gap.dart';
import '../../../core/widgets/state_views.dart';
import '../../../core/widgets/status_pill.dart';
import '../../customers/application/customer_providers.dart';
import '../../measurements/application/measurement_providers.dart';
import '../../timer/application/timer_providers.dart';
import '../../timer/presentation/timer_widgets.dart';
import '../application/job_providers.dart';
import '../domain/job.dart';
import 'job_sheets.dart';
import 'job_widgets.dart';

/// Job sheet — Stitch "Job Details / Production Stages": summary, production status ring,
/// active subtasks, production timeline, client specifications, and the next action at the bottom.
class JobDetailScreen extends ConsumerStatefulWidget {
  const JobDetailScreen({super.key, required this.jobId});

  final String jobId;

  @override
  ConsumerState<JobDetailScreen> createState() => _JobDetailScreenState();
}

class _JobDetailScreenState extends ConsumerState<JobDetailScreen> {
  bool _busy = false;

  JobController get _controller => ref.read(jobProvider(widget.jobId).notifier);

  /// Runs an action with a spinner on the bottom button; errors become snackbars.
  Future<Job?> _act(Future<Job> Function() action, {String? success}) async {
    if (_busy) return null;
    setState(() => _busy = true);
    try {
      final job = await action();
      if (mounted && success != null) showAppSnack(context, success);
      return job;
    } on ApiException catch (e) {
      if (mounted) showAppSnack(context, e.message, isError: true);
      return null;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _setStatus(Job job, JobStatus status) async {
    String? reason;
    if (status == JobStatus.cancelled) {
      reason = await askText(context, title: 'Cancel ${job.displayNumber}?', label: 'Reason', hint: 'e.g. Customer changed their mind', confirmLabel: 'Cancel job', destructive: true);
      if (reason == null) return;
    } else if (status == JobStatus.completed) {
      final ok = await confirmAction(context, title: 'Mark as collected?', message: '${job.customerName} has collected ${job.title}. Collected jobs can no longer be changed.', confirmLabel: 'Mark collected');
      if (!ok) return;
    }
    if (!mounted || _busy) return;
    setState(() => _busy = true);
    ConflictException? unfinished;
    try {
      await _controller.setStatus(status, reason: reason);
      if (mounted) showAppSnack(context, 'Job is now ${status.label.toLowerCase()}.');
    } on ConflictException catch (e) {
      if (e.code == 'TASKS_INCOMPLETE') {
        unfinished = e;
      } else if (mounted) {
        showAppSnack(context, e.message, isError: true);
      }
    } on ApiException catch (e) {
      if (mounted) showAppSnack(context, e.message, isError: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }

    // Unfinished stages: the server asks for an explicit confirmation.
    if (unfinished == null || !mounted) return;
    final force = await confirmAction(context, title: 'Stages not finished', message: '${unfinished.message} Mark the job ready for collection anyway?', confirmLabel: 'Mark ready anyway');
    if (force && mounted) await _act(() => _controller.setStatus(status, force: true), success: 'Job is ready for collection.');
  }

  Future<void> _menu(Job job, String action) async {
    switch (action) {
      case 'edit':
        await context.push(Routes.jobEdit(job.id));
      case 'hold':
        await _setStatus(job, JobStatus.onHold);
      case 'resume' || 'rework':
        await _setStatus(job, JobStatus.inProgress);
      case 'cancel':
        await _setStatus(job, JobStatus.cancelled);
      case 'progress':
        final percent = await askProgress(context, current: job.progressOverride ?? job.hours.progressPercent, manual: job.progressOverride != null);
        if (percent == null) return;
        await _act(() => _controller.run((api) => api.setProgressOverride(job.id, percent.isNaN ? null : percent)), success: percent.isNaN ? 'Progress is calculated from hours again.' : 'Progress set manually.');
      case 'delete':
        final ok = await confirmAction(context, title: 'Delete this draft?', message: '${job.title} for ${job.customerName} will be removed.', confirmLabel: 'Delete draft', destructive: true);
        if (!ok || !mounted) return;
        try {
          await ref.read(jobsApiProvider).deleteDraft(job.id);
          invalidateJobListsFromWidget(ref, customerId: job.customerId);
          if (mounted) {
            showAppSnack(context, 'Draft deleted.');
            context.pop();
          }
        } on ApiException catch (e) {
          if (mounted) showAppSnack(context, e.message, isError: true);
        }
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(jobProvider(widget.jobId));
    final job = async.value;

    return DetailScaffold(
      title: 'Job Details',
      actions: [
        if (job != null && !job.status.isClosed) ...[
          IconButton(
            tooltip: 'Edit job',
            icon: const Icon(Symbols.edit, size: 22, color: AppColors.onSurfaceVariant),
            onPressed: () => context.push(Routes.jobEdit(job.id)),
          ),
          PopupMenuButton<String>(
            tooltip: 'More actions',
            icon: const Icon(Symbols.more_vert, size: 22, color: AppColors.onSurfaceVariant),
            onSelected: (a) => _menu(job, a),
            itemBuilder: (_) => [
              if (job.canMoveTo(JobStatus.onHold)) const PopupMenuItem(value: 'hold', child: Text('Put on hold')),
              if (job.status == JobStatus.onHold) const PopupMenuItem(value: 'resume', child: Text('Resume production')),
              if (job.status == JobStatus.readyForCollection) const PopupMenuItem(value: 'rework', child: Text('Back to production')),
              if (job.status != JobStatus.draft) const PopupMenuItem(value: 'progress', child: Text('Set progress manually')),
              if (job.status == JobStatus.draft) const PopupMenuItem(value: 'delete', child: Text('Delete draft')),
              if (job.canMoveTo(JobStatus.cancelled)) const PopupMenuItem(value: 'cancel', child: Text('Cancel job')),
            ],
          ),
        ],
      ],
      bottomBar: job == null ? null : _bottomBar(job),
      body: switch (async) {
        AsyncData(value: final job) => RefreshIndicator(
            edgeOffset: MediaQuery.paddingOf(context).top + 64,
            onRefresh: () => ref.refresh(jobProvider(widget.jobId).future),
            child: ListView(
              padding: belowHeader(context, bottom: 24),
              children: [
                _Heading(job: job),
                Gap.lg,
                _SummaryCard(job: job),
                Gap.lg,
                _ProductionStatusCard(job: job),
                if (job.currentJobTask case final task? when !task.isMilestone) ...[
                  Gap.lg,
                  _SubtasksCard(job: job, task: task, busy: _busy, onAct: _act),
                ],
                Gap.lg,
                _TimelineCard(job: job, onTask: (task) => showTaskSheet(context, jobId: job.id, taskId: task.id)),
                Gap.lg,
                _SpecificationsCard(job: job),
                if (job.status == JobStatus.cancelled && job.cancelReason != null) ...[
                  Gap.lg,
                  AppCard(child: Text('Cancelled: ${job.cancelReason}', style: AppText.bodyMd.copyWith(color: AppColors.onErrorContainer))),
                ],
              ],
            ),
          ),
        AsyncError(:final error) => ErrorView(error: error, onRetry: () => ref.invalidate(jobProvider(widget.jobId))),
        _ => const LoadingView(),
      },
    );
  }

  /// The single next step for this job (Stitch: "Mark Stage Complete").
  Widget? _bottomBar(Job job) {
    final current = job.currentJobTask;
    final (String label, IconData icon, VoidCallback onPressed)? primary = switch (job.status) {
      JobStatus.draft => ('Queue Production', Symbols.verified, () => _setStatus(job, JobStatus.queued)),
      JobStatus.onHold => ('Resume Production', Symbols.play_arrow, () => _setStatus(job, JobStatus.inProgress)),
      JobStatus.readyForCollection => ('Mark Collected', Symbols.shopping_bag, () => _setStatus(job, JobStatus.completed)),
      JobStatus.queued || JobStatus.inProgress when current != null && !current.isMilestone => (
          'Mark Stage Complete',
          Symbols.check_circle,
          () => _act(() => _controller.setTaskStatus(current, TaskStatus.completed), success: '${current.name} completed.'),
        ),
      JobStatus.queued || JobStatus.inProgress => ('Ready for Collection', Symbols.inventory, () => _setStatus(job, JobStatus.readyForCollection)),
      _ => null,
    };
    if (primary == null) return null;

    return BottomActionBar(
      child: Row(children: [
        Expanded(
          flex: 2,
          child: AppButton(label: 'Edit Job', icon: Symbols.edit, variant: AppButtonVariant.tonal, onPressed: _busy ? null : () => context.push(Routes.jobEdit(job.id))),
        ),
        Gap.sm,
        Expanded(flex: 3, child: AppButton(label: primary.$1, icon: primary.$2, loading: _busy, onPressed: primary.$3)),
      ]),
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading({required this.job});

  final Job job;

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('JOB ${job.displayNumber}  ·  ${job.status.label.toUpperCase()}', style: AppText.labelSm.copyWith(color: AppColors.secondary, letterSpacing: 0.8)),
      const SizedBox(height: 2),
      GestureDetector(
        onTap: () => context.push(Routes.customer(job.customerId)),
        child: Text(job.customerName, style: AppText.headlineLg),
      ),
    ]);
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.job});

  final Job job;

  @override
  Widget build(BuildContext context) {
    Widget dateTile(IconData icon, String caption, DateTime? date, {String? footnote, Color? footnoteColor}) => Expanded(
          child: InsetTile(
            padding: const EdgeInsets.all(AppSpace.md),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(icon, size: 15, color: AppColors.onSurfaceVariant),
                const SizedBox(width: 4),
                Text(caption, style: AppText.labelSm.copyWith(color: AppColors.onSurfaceVariant)),
              ]),
              const SizedBox(height: 2),
              Text(date == null ? 'Not set' : Fmt.date(date), style: AppText.titleSm.copyWith(fontFeatures: const [FontFeature.tabularFigures()])),
              if (footnote != null) Text(footnote, style: AppText.bodySm.copyWith(color: footnoteColor ?? AppColors.onSurfaceVariant)),
            ]),
          ),
        );

    final days = job.flags.daysUntilDue;
    return AppCard(
      padding: const EdgeInsets.all(AppSpace.lg),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Wrap(spacing: AppSpace.sm, runSpacing: 6, children: [
          if (job.priority != JobPriority.normal) StatusPill(label: job.priority == JobPriority.urgent ? 'Urgent' : 'High Priority', tone: StatusTone.danger),
          if (job.dueDate != null && !job.status.isClosed)
            StatusPill(label: 'Due ${Fmt.shortDate(job.dueDate!)}', tone: job.flags.isOverdue ? StatusTone.danger : (job.flags.isDueSoon ? StatusTone.warning : StatusTone.neutral)),
          StatusPill(label: job.status.label, tone: jobStatusTone(job.status)),
        ]),
        Gap.md,
        Text(job.title, style: AppText.headlineMd),
        Text(
          [if (job.title != job.jobTypeName) job.jobTypeName, ?job.components, '${job.quantity} piece${job.quantity == 1 ? '' : 's'}'].join(' · '),
          style: AppText.bodySm.copyWith(color: AppColors.onSurfaceVariant),
        ),
        if (job.fabricNote != null) ...[
          Gap.md,
          InsetTile(
            padding: const EdgeInsets.all(AppSpace.md),
            child: Row(children: [
              const Icon(Symbols.texture, size: 22, color: AppColors.onSurfaceVariant),
              Gap.md,
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Selected Textile', style: AppText.labelSm.copyWith(color: AppColors.onSurfaceVariant)),
                  Text(job.fabricNote!, style: AppText.titleSm),
                ]),
              ),
            ]),
          ),
        ],
        Gap.md,
        IntrinsicHeight(child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          dateTile(Symbols.calendar_today, 'Ordered', job.orderDate),
          Gap.sm,
          dateTile(
            Symbols.local_shipping,
            'Due',
            job.dueDate,
            footnote: job.collectionDate != null ? 'Collect ${Fmt.shortDate(job.collectionDate!)}' : (days != null && !job.status.isClosed ? Fmt.dueIn(days) : null),
            footnoteColor: job.flags.isOverdue ? AppColors.error : null,
          ),
        ])),
      ]),
    );
  }
}

/// Dark "PRODUCTION STATUS" card with the progress ring.
class _ProductionStatusCard extends ConsumerWidget {
  const _ProductionStatusCard({required this.job});

  final Job job;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final h = job.hours;
    final current = job.currentTask;
    return Container(
      padding: const EdgeInsets.all(AppSpace.lg),
      decoration: BoxDecoration(color: AppColors.primaryContainer, borderRadius: AppRadius.card, boxShadow: AppShadows.raised),
      child: Column(children: [
        Row(children: [
          Container(width: 6, height: 6, decoration: const BoxDecoration(color: AppColors.tertiaryFixedDim, shape: BoxShape.circle)),
          const SizedBox(width: 6),
          Expanded(child: Text('PRODUCTION STATUS', style: AppText.overline.copyWith(color: AppColors.onPrimaryContainer))),
          if (current != null && !job.status.isClosed)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(color: AppColors.inverseSurface, borderRadius: AppRadius.full),
              child: Text(current.isMilestone ? current.name : '${current.typeName} Phase', style: AppText.labelSm.copyWith(color: AppColors.inverseOnSurface)),
            ),
        ]),
        Gap.lg,
        SizedBox.square(
          dimension: 148,
          child: Stack(alignment: Alignment.center, children: [
            SizedBox.expand(
              child: CircularProgressIndicator(
                value: (h.progressPercent / 100).clamp(0, 1).toDouble(),
                strokeWidth: 10,
                strokeCap: StrokeCap.round,
                color: AppColors.secondaryContainer,
                backgroundColor: AppColors.inverseSurface,
              ),
            ),
            Column(mainAxisSize: MainAxisSize.min, children: [
              Text.rich(TextSpan(children: [
                TextSpan(text: '${h.progressPercent.round()}', style: AppText.displayLg.copyWith(color: AppColors.onPrimary, fontFeatures: const [FontFeature.tabularFigures()])),
                TextSpan(text: '%', style: AppText.headlineMd.copyWith(color: AppColors.onPrimary)),
              ])),
              Text(h.isProgressManual ? 'Set manually' : 'Complete', style: AppText.bodySm.copyWith(color: AppColors.onPrimaryContainer)),
            ]),
          ]),
        ),
        Gap.lg,
        Text(
          '${Fmt.hours(h.actualSeconds)} of ${Fmt.hours(h.estimatedSeconds)} Hours Completed',
          style: AppText.titleSm.copyWith(color: AppColors.onPrimary, fontFeatures: const [FontFeature.tabularFigures()]),
        ),
        Gap.sm,
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          decoration: BoxDecoration(color: AppColors.inverseSurface, borderRadius: AppRadius.full),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(h.overrunSeconds > 0 ? Symbols.warning : Symbols.hourglass_top, size: 14, color: h.overrunSeconds > 0 ? AppColors.warningAccent : AppColors.inverseOnSurface),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
              h.overrunSeconds > 0
                  ? '${Fmt.hours(h.remainingSeconds)} hrs remaining · ${Fmt.hours(h.overrunSeconds)} over'
                  : '${Fmt.hours(h.remainingSeconds)} hrs remaining to baseline',
              style: AppText.labelSm.copyWith(color: AppColors.inverseOnSurface),
              textAlign: TextAlign.center,
            ),
            ),
          ]),
        ),
        if (job.status.isInProduction && current != null && !current.isMilestone) ...[
          Gap.lg,
          _TimerButton(job: job, current: current),
        ],
      ]),
    );
  }
}

/// "Start Work Timer (Sewing)" — or "Open Timer" while it runs on this job.
class _TimerButton extends ConsumerWidget {
  const _TimerButton({required this.job, required this.current});

  final Job job;
  final CurrentTask current;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final timer = ref.watch(activeTimerProvider).value;
    final runningHere = timer != null && timer.jobId == job.id;
    return SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.secondaryContainer,
          foregroundColor: AppColors.onSecondary,
          minimumSize: const Size.fromHeight(48),
          shape: RoundedRectangleBorder(borderRadius: AppRadius.control),
          textStyle: AppText.titleSm,
        ),
        icon: Icon(runningHere ? Symbols.timer : Symbols.play_arrow, size: 20),
        label: runningHere
            ? Ticker(builder: (_, now) => Text('Timer running · ${clockText(timer.elapsed(now))}'))
            : Text('Start Work Timer (${current.typeName})'),
        onPressed: runningHere
            ? () => context.push(Routes.taskTimer(job.id, timer.taskId))
            : () => startTimerFlow(context, ref, jobId: job.id, taskId: current.id, taskName: current.name),
      ),
    );
  }
}

class _SubtasksCard extends ConsumerWidget {
  const _SubtasksCard({required this.job, required this.task, required this.busy, required this.onAct});

  final Job job;
  final JobTask task;
  final bool busy;
  final Future<Job?> Function(Future<Job> Function() action, {String? success}) onAct;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(jobProvider(job.id).notifier);
    final editable = !job.status.isClosed;
    final next = task.checklist.where((i) => !i.isDone).firstOrNull;

    return AppCard(
      padding: const EdgeInsets.all(AppSpace.lg),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          const Icon(Symbols.checklist, size: 20, color: AppColors.secondary),
          Gap.sm,
          Expanded(child: Text('Active Subtasks', style: AppText.titleSm)),
          Text('Stage ${job.stepIndex} of ${job.stepTotal}', style: AppText.labelMd.copyWith(color: AppColors.onSurfaceVariant)),
        ]),
        const SizedBox(height: 2),
        Text(task.name, style: AppText.bodySm.copyWith(color: AppColors.onSurfaceVariant)),
        Gap.md,
        if (task.checklist.isEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpace.sm),
            child: Text('Break this stage into small steps to tick off as you go.', style: AppText.bodySm.copyWith(color: AppColors.onSurfaceVariant)),
          ),
        for (final item in task.checklist) ...[
          _ChecklistRow(
            item: item,
            isNext: item == next,
            onToggle: editable && !busy ? () => onAct(() => controller.toggleChecklist(item)) : null,
            onDelete: editable ? () => onAct(() => controller.run((api) => api.deleteChecklistItem(item.id)), success: 'Subtask removed.') : null,
          ),
          Gap.sm,
        ],
        if (editable)
          Align(
            alignment: Alignment.centerLeft,
            child: AppButton(
              label: 'Add subtask',
              icon: Symbols.add,
              variant: AppButtonVariant.text,
              size: AppButtonSize.small,
              onPressed: () async {
                final label = await askText(context, title: 'New subtask', label: 'Subtask', hint: 'e.g. Set sleeves & shoulder pads', confirmLabel: 'Add', maxLength: 150);
                if (label != null) await onAct(() => controller.run((api) => api.addChecklistItem(task.id, label)));
              },
            ),
          ),
      ]),
    );
  }
}

class _ChecklistRow extends StatelessWidget {
  const _ChecklistRow({required this.item, required this.isNext, required this.onToggle, required this.onDelete});

  final ChecklistItem item;
  final bool isNext;
  final VoidCallback? onToggle;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final background = isNext ? AppColors.secondaryFixed : AppColors.surfaceContainerLow;
    return Material(
      color: background,
      borderRadius: AppRadius.control,
      child: InkWell(
        borderRadius: AppRadius.control,
        onTap: onToggle,
        onLongPress: onDelete,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpace.md, vertical: AppSpace.md),
          child: Row(children: [
            AnimatedContainer(
              duration: AppMotion.fast,
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: item.isDone ? AppColors.tertiaryFixedDim : AppColors.surfaceContainerLowest,
                border: item.isDone ? null : Border.all(color: isNext ? AppColors.secondary : AppColors.outlineVariant, width: 1.5),
              ),
              child: item.isDone ? const Icon(Symbols.check, size: 15, color: AppColors.tertiaryContainer, weight: 700) : null,
            ),
            Gap.md,
            Expanded(
              child: Text(
                item.label,
                style: AppText.bodyMd.copyWith(
                  color: item.isDone ? AppColors.onSurfaceVariant : AppColors.onSurface,
                  decoration: item.isDone ? TextDecoration.lineThrough : null,
                  fontWeight: isNext ? FontWeight.w600 : null,
                ),
              ),
            ),
            Text(item.isDone ? 'Done' : (isNext ? 'Next' : 'Pending'), style: AppText.labelSm.copyWith(color: isNext ? AppColors.secondary : AppColors.onSurfaceVariant)),
          ]),
        ),
      ),
    );
  }
}

class _TimelineCard extends StatelessWidget {
  const _TimelineCard({required this.job, required this.onTask});

  final Job job;
  final ValueChanged<JobTask> onTask;

  @override
  Widget build(BuildContext context) {
    final current = job.currentTask?.id;
    var number = 0;
    return AppCard(
      padding: const EdgeInsets.all(AppSpace.lg),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          const Icon(Symbols.timeline, size: 20, color: AppColors.onSurface),
          Gap.sm,
          Expanded(child: Text('Production Timeline', style: AppText.titleSm)),
          Text('Stage ${job.stepIndex} of ${job.stepTotal}', style: AppText.labelMd.copyWith(color: AppColors.secondary)),
        ]),
        Gap.md,
        for (final (i, task) in job.tasks.indexed)
          _TimelineRow(
            task: task,
            number: task.status == TaskStatus.skipped ? null : ++number,
            isCurrent: task.id == current,
            isLast: i == job.tasks.length - 1,
            onTap: () => onTask(task),
          ),
        if (!job.status.isClosed) ...[
          Gap.sm,
          Align(
            alignment: Alignment.centerLeft,
            child: AppButton(label: 'Add stage', icon: Symbols.add, variant: AppButtonVariant.text, size: AppButtonSize.small, onPressed: () => showAddStageSheet(context, jobId: job.id)),
          ),
        ],
      ]),
    );
  }
}

class _TimelineRow extends StatelessWidget {
  const _TimelineRow({required this.task, required this.number, required this.isCurrent, required this.isLast, required this.onTap});

  final JobTask task;
  final int? number;
  final bool isCurrent;
  final bool isLast;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final done = task.status == TaskStatus.completed;
    final skipped = task.status == TaskStatus.skipped;
    final date = task.completedAt ?? task.scheduledStart;

    final String subtitle;
    if (task.isMilestone) {
      subtitle = done ? (task.completedAt == null ? 'Reached' : 'Reached ${Fmt.shortDate(task.completedAt!)}') : 'Milestone · follows the job status';
    } else if (skipped) {
      subtitle = 'Skipped${task.actualSeconds > 0 ? ' · ${Fmt.hours(task.actualSeconds)} hrs logged' : ''}';
    } else if (done) {
      subtitle = 'Completed · ${Fmt.hours(task.actualSeconds)} hrs logged';
    } else if (isCurrent || task.status == TaskStatus.inProgress) {
      subtitle = 'Current Phase · ${Fmt.hours(task.actualSeconds)} of ${Fmt.hours(task.estimatedSeconds)} hrs logged';
    } else {
      subtitle = task.estimatedSeconds > 0 ? 'Est. ${Fmt.hours(task.estimatedSeconds)} hr' : 'No estimate yet';
    }

    final Widget marker = switch (task.status) {
      _ when task.isMilestone => Icon(Symbols.flag, size: 18, color: done ? AppColors.onTertiaryContainer : AppColors.outline),
      TaskStatus.completed => Container(
          width: 22,
          height: 22,
          decoration: const BoxDecoration(color: AppColors.tertiaryFixedDim, shape: BoxShape.circle),
          child: const Icon(Symbols.check, size: 15, color: AppColors.tertiaryContainer, weight: 700),
        ),
      _ when isCurrent => Container(
          width: 22,
          height: 22,
          decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: AppColors.secondary, width: 2)),
          child: Center(child: Container(width: 10, height: 10, decoration: const BoxDecoration(color: AppColors.secondary, shape: BoxShape.circle))),
        ),
      TaskStatus.skipped => const Icon(Symbols.do_not_disturb_on, size: 18, color: AppColors.outline),
      _ => Container(width: 10, height: 10, decoration: const BoxDecoration(color: AppColors.outlineVariant, shape: BoxShape.circle)),
    };

    return InkWell(
      onTap: onTap,
      borderRadius: AppRadius.control,
      child: IntrinsicHeight(
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SizedBox(
            width: 28,
            child: Column(children: [
              SizedBox(height: 26, child: Center(child: marker)),
              if (!isLast) Expanded(child: Container(width: 2, color: done ? AppColors.tertiaryFixedDim : AppColors.surfaceContainerHigh)),
            ]),
          ),
          Gap.sm,
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 3, bottom: AppSpace.lg),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Row(children: [
                  Expanded(
                    child: Text(
                      number == null ? task.name : '$number. ${task.name}',
                      style: AppText.titleSm.copyWith(
                        color: isCurrent ? AppColors.secondary : (skipped ? AppColors.outline : AppColors.onSurface),
                        decoration: skipped ? TextDecoration.lineThrough : null,
                      ),
                    ),
                  ),
                  if (isCurrent && task.status == TaskStatus.inProgress)
                    const StatusPill(label: 'In Progress', tone: StatusTone.info, showDot: false)
                  else if (date != null)
                    Text(Fmt.shortDate(date), style: AppText.labelMd.copyWith(color: AppColors.onSurfaceVariant)),
                ]),
                const SizedBox(height: 2),
                Text(subtitle, style: AppText.bodySm.copyWith(color: AppColors.onSurfaceVariant)),
                if (isCurrent && !task.isMilestone && task.estimatedSeconds > 0) ...[
                  Gap.sm,
                  JobProgressBar(percent: task.progressPercent, height: 6),
                ],
              ]),
            ),
          ),
        ]),
      ),
    );
  }
}

/// "Client Specifications": key current measurements, style preferences and job notes.
class _SpecificationsCard extends ConsumerWidget {
  const _SpecificationsCard({required this.job});

  final Job job;

  /// Measurement codes highlighted on the job sheet, in order (first three recorded are shown).
  static const _highlight = ['chest', 'waist', 'inseam', 'shoulder', 'sleeve', 'trouser_length', 'hip'];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(currentMeasurementsProvider(job.customerId)).value;
    final customer = ref.watch(customerProvider(job.customerId)).value;
    final unit = displayUnitFor(customer, ref.watch(defaultMeasurementUnitProvider));
    final values = [
      for (final code in _highlight)
        ?current?.values.where((v) => v.code == code && v.valueCm != null).firstOrNull,
    ].take(3).toList();
    final notes = [job.description, job.notes, customer?.stylePreferences].whereType<String>().where((s) => s.trim().isNotEmpty).toList();

    return AppCard(
      padding: const EdgeInsets.all(AppSpace.lg),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          const Icon(Symbols.tune, size: 20, color: AppColors.onSurface),
          Gap.sm,
          Expanded(child: Text('Client Specifications', style: AppText.titleSm)),
          AppButton(label: 'Full Dossier', icon: Symbols.arrow_forward, variant: AppButtonVariant.text, size: AppButtonSize.small, onPressed: () => context.push(Routes.customer(job.customerId))),
        ]),
        Gap.md,
        if (values.isEmpty)
          Text(
            current == null ? 'Loading measurements…' : 'No measurements recorded for ${job.customerName} yet.',
            style: AppText.bodySm.copyWith(color: AppColors.onSurfaceVariant),
          )
        else
          Row(children: [
            for (final (i, v) in values.indexed) ...[
              if (i > 0) Gap.sm,
              Expanded(
                child: InsetTile(
                  padding: const EdgeInsets.symmetric(vertical: AppSpace.md),
                  child: Column(children: [
                    Text(v.label.split(' ').first, style: AppText.labelSm.copyWith(color: AppColors.onSurfaceVariant), maxLines: 1),
                    const SizedBox(height: 2),
                    Text.rich(TextSpan(children: [
                      TextSpan(text: unit.format(v.valueCm!), style: AppText.metricNum),
                      TextSpan(text: ' ${unit.code}', style: AppText.bodySm.copyWith(color: AppColors.onSurfaceVariant)),
                    ])),
                  ]),
                ),
              ),
            ],
          ]),
        if (job.measuredAt != null) ...[
          Gap.sm,
          Text('This job uses measurements from ${Fmt.date(job.measuredAt!)}.', style: AppText.bodySm.copyWith(color: AppColors.onSurfaceVariant)),
        ],
        if (notes.isNotEmpty) ...[
          Gap.md,
          InsetTile(
            padding: const EdgeInsets.all(AppSpace.md),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('STYLING & FINISH NOTES', style: AppText.overline.copyWith(color: AppColors.secondary)),
              const SizedBox(height: 4),
              for (final note in notes) Text(note, style: AppText.bodyMd),
            ]),
          ),
        ],
      ]),
    );
  }
}
