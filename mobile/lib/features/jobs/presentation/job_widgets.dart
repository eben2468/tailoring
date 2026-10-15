import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../app/routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/gap.dart';
import '../../../core/widgets/initials_avatar.dart';
import '../../../core/widgets/status_pill.dart';
import '../../timer/application/timer_providers.dart';
import '../../timer/presentation/timer_widgets.dart';
import '../domain/job.dart';

/// Pill for the top-right of a job card: urgency first (priority, overdue, due soon), otherwise the status.
StatusPill jobHeadlinePill(Job job) {
  final days = job.flags.daysUntilDue;
  if (job.status.isClosed || job.status == JobStatus.readyForCollection || job.status == JobStatus.draft || job.status == JobStatus.onHold) {
    return StatusPill(label: job.status.label, tone: jobStatusTone(job.status));
  }
  if (job.priority == JobPriority.urgent) return const StatusPill(label: 'Urgent', tone: StatusTone.danger);
  if (job.flags.isOverdue) return StatusPill(label: 'Overdue ${Fmt.dueIn(days!).replaceFirst(' late', '')}', tone: StatusTone.danger);
  if (job.priority == JobPriority.high) return const StatusPill(label: 'High Priority', tone: StatusTone.danger);
  if (job.flags.isDueSoon && days != null) {
    return StatusPill(label: days <= 1 ? 'Due ${days == 0 ? 'Today' : 'Tomorrow'}' : 'Due in $days days', tone: days <= 1 ? StatusTone.danger : StatusTone.warning);
  }
  return StatusPill(label: job.status.label, tone: jobStatusTone(job.status));
}

StatusTone jobStatusTone(JobStatus status) => switch (status) {
  JobStatus.inProgress => StatusTone.info,
  JobStatus.readyForCollection || JobStatus.completed => StatusTone.success,
  JobStatus.onHold => StatusTone.warning,
  JobStatus.cancelled => StatusTone.danger,
  _ => StatusTone.neutral,
};

/// Colour for a stage's `color_key` (design tokens only).
Color stageColor(String? key) => switch (key) {
  'teal' || 'green' => AppColors.onTertiaryContainer,
  'amber' => AppColors.warningAccent,
  'indigo' => AppColors.onSecondaryFixedVariant,
  'rose' => AppColors.error,
  'slate' => AppColors.outline,
  _ => AppColors.secondary,
};

/// Thin rounded progress bar (Stitch: h-2 rounded-full bg-surface-container).
class JobProgressBar extends StatelessWidget {
  const JobProgressBar({super.key, required this.percent, this.color = AppColors.secondary, this.height = 8, this.background = AppColors.surfaceContainer});

  final double percent;
  final Color color;
  final double height;
  final Color background;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: AppRadius.full,
      child: SizedBox(
        height: height,
        child: Stack(
          fit: StackFit.expand,
          children: [
            ColoredBox(color: background),
            FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: (percent / 100).clamp(0, 1).toDouble(),
              child: ColoredBox(color: color),
            ),
          ],
        ),
      ),
    );
  }
}

/// ESTIMATED · COMPLETED · REMAINING hours tile (job cards and the job sheet).
class HoursTriplet extends StatelessWidget {
  const HoursTriplet({super.key, required this.hours});

  final JobHours hours;

  @override
  Widget build(BuildContext context) {
    Widget cell(String caption, int seconds, Color color) => Expanded(
      child: Column(
        children: [
          Text(caption, style: AppText.overline.copyWith(fontSize: 10)),
          const SizedBox(height: 2),
          Text('${Fmt.hours(seconds)}h', style: AppText.metricNum.copyWith(color: color, fontSize: 18)),
        ],
      ),
    );

    return InsetTile(
      padding: const EdgeInsets.symmetric(vertical: AppSpace.md),
      child: Row(
        children: [
          cell('ESTIMATED', hours.estimatedSeconds, AppColors.onSurface),
          cell('COMPLETED', hours.actualSeconds, AppColors.onTertiaryContainer),
          cell('REMAINING', hours.remainingSeconds, AppColors.secondary),
        ],
      ),
    );
  }
}

/// Stage names under the progress bar (as in the Stitch jobs list) when they fit; otherwise "Stage 3 of 9".
class StageLabels extends StatelessWidget {
  const StageLabels({super.key, required this.job});

  final Job job;

  static const maxLabels = 6;

  @override
  Widget build(BuildContext context) {
    if (job.stages.isEmpty) return const SizedBox.shrink();
    if (job.stages.length > maxLabels) {
      return Text('Stage ${job.stepIndex} of ${job.stepTotal}', style: AppText.labelSm.copyWith(color: AppColors.onSurfaceVariant));
    }
    return Row(
      children: [
        for (final stage in job.stages)
          Expanded(
            // Short whole words as in the design ("Ready" for "Ready for Collection"); shrink rather than cut off.
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                stage.typeName.split(' ').first,
                textAlign: TextAlign.center,
                maxLines: 1,
                style: AppText.labelSm.copyWith(
                  fontSize: 10,
                  color: switch (stage.status) {
                    TaskStatus.completed => AppColors.onTertiaryContainer,
                    TaskStatus.inProgress => AppColors.secondary,
                    _ => stage.id == job.currentTask?.id ? AppColors.secondary : AppColors.outline,
                  },
                  fontWeight: stage.id == job.currentTask?.id ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Job card from the Stitch "Production Jobs" list. [compact] (customer history) drops the hours tile.
class JobCard extends StatelessWidget {
  const JobCard({super.key, required this.job, required this.onTap, this.compact = false, this.showCustomer = true});

  final Job job;
  final VoidCallback onTap;
  final bool compact;
  final bool showCustomer;

  @override
  Widget build(BuildContext context) {
    final current = job.currentTask;
    final progressColor = job.status == JobStatus.readyForCollection || job.status == JobStatus.completed
        ? AppColors.onTertiaryContainer
        : job.hours.progressPercent >= 80
        ? AppColors.primaryContainer
        : AppColors.secondary;

    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.all(AppSpace.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (showCustomer) ...[InitialsAvatar(name: job.customerName, size: 44), Gap.md],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: 'JOB ${job.displayNumber}',
                            style: AppText.labelMd.copyWith(color: AppColors.secondary),
                          ),
                          if (showCustomer) ...[
                            TextSpan(
                              text: '  ·  ',
                              style: AppText.labelMd.copyWith(color: AppColors.outline),
                            ),
                            TextSpan(text: job.customerName, style: AppText.titleSm),
                          ],
                        ],
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      job.title == job.jobTypeName || job.components == null ? job.title : '${job.title} (${job.components})',
                      style: AppText.bodySm.copyWith(color: AppColors.onSurfaceVariant),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              Gap.sm,
              jobHeadlinePill(job),
            ],
          ),
          Gap.md,
          Wrap(
            spacing: AppSpace.sm,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (current != null && !job.status.isClosed) StatusPill(label: current.isMilestone ? current.name : '${current.typeName} Stage', tone: StatusTone.info),
              StatusPill(label: '${job.quantity} piece${job.quantity == 1 ? '' : 's'}', tone: StatusTone.neutral, showDot: false),
              if (job.dueDate != null && !job.status.isClosed)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Symbols.schedule, size: 15, color: job.flags.isOverdue ? AppColors.error : AppColors.secondary),
                    const SizedBox(width: 4),
                    Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(text: 'Due ${Fmt.shortDate(job.dueDate!)}', style: AppText.labelMd),
                          if (job.flags.daysUntilDue != null)
                            TextSpan(
                              text: ' (${Fmt.dueIn(job.flags.daysUntilDue!)})',
                              style: AppText.bodySm.copyWith(color: job.flags.isOverdue ? AppColors.error : AppColors.onSurfaceVariant),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              if (job.status == JobStatus.completed && job.completedAt != null) Text('Collected ${Fmt.date(job.completedAt!)}', style: AppText.bodySm.copyWith(color: AppColors.onSurfaceVariant)),
            ],
          ),
          Gap.md,
          Row(
            children: [
              Expanded(
                child: Text(
                  current == null ? 'Progress' : 'Progress: ${current.name}',
                  style: AppText.labelMd.copyWith(color: AppColors.onSurfaceVariant),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                '${job.hours.progressPercent.round()}%',
                style: AppText.labelMd.copyWith(color: progressColor, fontFeatures: const [FontFeature.tabularFigures()]),
              ),
            ],
          ),
          const SizedBox(height: 6),
          JobProgressBar(percent: job.hours.progressPercent, color: progressColor),
          const SizedBox(height: 6),
          StageLabels(job: job),
          if (!compact) ...[Gap.md, HoursTriplet(hours: job.hours), Gap.md, _CardActions(job: job, onViewSheet: onTap)],
        ],
      ),
    );
  }
}

/// "Start Timer" (or "Open Timer" while it runs on this job) + "View Sheet", as in the Stitch jobs list.
class _CardActions extends ConsumerWidget {
  const _CardActions({required this.job, required this.onViewSheet});

  final Job job;
  final VoidCallback onViewSheet;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = job.currentTask;
    final timer = ref.watch(activeTimerProvider).value;
    final canTime = job.status.isInProduction && current != null && !current.isMilestone;
    final viewSheet = AppButton(label: 'View Sheet', icon: Symbols.receipt_long, variant: AppButtonVariant.tonal, size: AppButtonSize.medium, onPressed: onViewSheet);
    if (!canTime) return Align(alignment: Alignment.centerRight, child: viewSheet);

    final runningHere = timer != null && timer.jobId == job.id;
    return Row(
      children: [
        Expanded(
          flex: 3,
          child: AppButton(
            label: runningHere ? 'Open Timer' : 'Start Timer',
            icon: runningHere ? Symbols.timer : Symbols.play_circle,
            size: AppButtonSize.medium,
            onPressed: runningHere ? () => context.push(Routes.taskTimer(job.id, timer.taskId)) : () => startTimerFlow(context, ref, jobId: job.id, taskId: current.id, taskName: current.name),
          ),
        ),
        Gap.sm,
        Expanded(flex: 2, child: viewSheet),
      ],
    );
  }
}
