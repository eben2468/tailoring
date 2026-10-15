import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/hero_panel.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/gap.dart';
import '../../ai/domain/ai.dart';
import '../../inventory/domain/inventory.dart';
import '../../jobs/domain/job.dart';
import '../../jobs/presentation/job_widgets.dart';
import '../../timer/domain/timer.dart';
import '../../timer/presentation/timer_widgets.dart';
import '../../tools/domain/tools.dart';
import '../../tools/presentation/tool_widgets.dart';
import '../domain/dashboard.dart';

/// "30 mins", "1 hr", "2.5 hrs".
String durationLabel(int seconds) {
  if (seconds < 3600) return '${(seconds / 60).round()} mins';
  final hours = seconds / 3600;
  if (hours == hours.roundToDouble()) return '${hours.round()} hr${hours == 1 ? '' : 's'}';
  return '${hours.toStringAsFixed(1)} hrs';
}

/// Uppercase section caption used inside dashboard cards.
TextStyle get _caption => AppText.labelSm.copyWith(color: AppColors.onSurfaceVariant, letterSpacing: 11 * 0.08);

/// "● SHOP OPEN" / "OPENS 09:00" / "SHOP CLOSED" (Stitch header pill).
class ShopPill extends StatelessWidget {
  const ShopPill({super.key, required this.shop, required this.now});

  final ShopStatus shop;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final time = DateFormat('HH:mm').format(now);
    final opensLater = !shop.isOpen && shop.opensAt != null && time.compareTo(shop.opensAt!) < 0;
    final (label, dot, color) = shop.isOpen
        ? ('Shop Open', AppColors.tertiaryFixedDim, AppColors.onTertiaryContainer)
        : opensLater
        ? ('Opens ${shop.opensAt}', AppColors.warningAccent, AppColors.warning)
        : ('Shop Closed', AppColors.outline, AppColors.onSurfaceVariant);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.md, vertical: 6),
      decoration: BoxDecoration(color: AppColors.surfaceContainerHigh, borderRadius: AppRadius.full, boxShadow: AppShadows.card),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            label.toUpperCase(),
            style: AppText.labelSm.copyWith(color: color, letterSpacing: 11 * 0.06),
          ),
        ],
      ),
    );
  }
}

/// KPI tile from the 2×2 grid: caption, icon box, big number, footer.
class KpiTile extends StatelessWidget {
  const KpiTile({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    required this.footer,
    this.iconColor = AppColors.secondary,
    this.iconBackground = AppColors.surfaceContainer,
    this.onTap,
  });

  final String label;
  final int value;
  final IconData icon;
  final Color iconColor;
  final Color iconBackground;
  final Widget footer;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.all(AppSpace.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(label.toUpperCase(), style: _caption, maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(color: iconBackground, borderRadius: AppRadius.control),
                child: Icon(icon, size: 18, color: iconColor),
              ),
            ],
          ),
          Gap.sm,
          Text('$value', style: AppText.displayLgMobile),
          const SizedBox(height: 2),
          footer,
        ],
      ),
    );
  }
}

/// Footer line of a KPI tile.
class KpiNote extends StatelessWidget {
  const KpiNote(this.text, {super.key, this.color = AppColors.onSurfaceVariant});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: AppText.bodySm.copyWith(color: color, fontWeight: FontWeight.w500),
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
  );
}

/// Footer chip of a KPI tile ("● 1 FITTING, 1 COLLECTION").
class KpiChip extends StatelessWidget {
  const KpiChip(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(color: AppColors.surfaceContainerHighest, borderRadius: AppRadius.small),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: const BoxDecoration(color: AppColors.secondary, shape: BoxShape.circle),
          ),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              text.toUpperCase(),
              style: AppText.labelSm.copyWith(fontSize: 10, color: AppColors.onSurfaceVariant),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

/// Today's Workload: remaining hours on the bench per stage against today's bench time.
class WorkloadCard extends StatelessWidget {
  const WorkloadCard({super.key, required this.workload});

  final Workload workload;

  /// One colour per stage, in order (Stitch: secondary-container, secondary, tertiary-fixed-dim …).
  static const palette = [AppColors.secondaryContainer, AppColors.secondary, AppColors.tertiaryFixedDim, AppColors.onSecondaryFixedVariant, AppColors.warningAccent, AppColors.primaryFixedDim];

  @override
  Widget build(BuildContext context) {
    final w = workload;
    final free = w.capacitySeconds - w.remainingSeconds;
    final caption = w.capacitySeconds == 0
        ? 'The shop is closed today.'
        : free >= 0
        ? '${Fmt.hours(w.capacitySeconds)}h of bench time today · ${Fmt.hours(free)}h free'
        : '${Fmt.hours(-free)}h more than today\'s ${Fmt.hours(w.capacitySeconds)}h of bench time';
    return AppCard(
      padding: const EdgeInsets.all(AppSpace.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Symbols.timelapse, size: 18, color: AppColors.secondary),
              Gap.xs,
              Expanded(child: Text("Today's Workload", style: AppText.titleSm)),
              Text(
                '${Fmt.hours(w.remainingSeconds)}h remaining',
                style: AppText.labelMd.copyWith(color: AppColors.secondary, fontWeight: FontWeight.w700),
              ),
            ],
          ),
          Gap.sm,
          ClipRRect(
            borderRadius: AppRadius.full,
            child: SizedBox(
              height: 10,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final (i, s) in w.byStage.indexed)
                    if (s.remainingSeconds > 0)
                      Expanded(
                        flex: (s.remainingSeconds / 60).ceil(),
                        child: ColoredBox(color: palette[i % palette.length]),
                      ),
                  if (free > 0 || w.remainingSeconds == 0)
                    Expanded(
                      flex: free > 0 ? (free / 60).ceil() : 1,
                      child: const ColoredBox(color: AppColors.surfaceContainer),
                    ),
                ],
              ),
            ),
          ),
          Gap.sm,
          if (w.byStage.isEmpty)
            Text(
              'No stage is in progress or planned for today.',
              style: AppText.labelSm.copyWith(color: AppColors.onSurfaceVariant, fontWeight: FontWeight.w500),
            )
          else
            Wrap(
              spacing: AppSpace.md,
              runSpacing: 4,
              children: [
                // Stages whose estimate is used up add nothing to the bar; leave them out of the legend too.
                for (final (i, s) in w.byStage.indexed)
                  if (s.remainingSeconds > 0)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(color: palette[i % palette.length], shape: BoxShape.circle),
                        ),
                        const SizedBox(width: 6),
                        Text('${s.name} (${Fmt.hours(s.remainingSeconds)}h)', style: AppText.labelSm.copyWith(color: AppColors.onSurfaceVariant)),
                      ],
                    ),
              ],
            ),
          const SizedBox(height: 6),
          Text(caption, style: AppText.bodySm.copyWith(color: free < 0 ? AppColors.error : AppColors.onSurfaceVariant)),
        ],
      ),
    );
  }
}

/// Dark AI insight card (Stitch "AI velocity insight"): the most important open card.
class InsightBanner extends StatelessWidget {
  const InsightBanner({super.key, required this.insight, required this.onAct, required this.onDetail});

  final Insight insight;
  final VoidCallback onAct;
  final VoidCallback onDetail;

  @override
  Widget build(BuildContext context) {
    final badge = switch (insight.severity) {
      'critical' || 'warning' => 'Action Advised',
      'advice' => 'Suggestion',
      _ => 'For Your Information',
    };
    final actionLabel = insight.action?['label'] as String?;
    Widget button(String label, VoidCallback onTap, {required bool primary}) => Material(
      color: primary ? AppColors.surfaceContainerLowest : AppColors.onPrimary.withValues(alpha: 0.1),
      borderRadius: AppRadius.control,
      child: InkWell(
        borderRadius: AppRadius.control,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpace.md, vertical: AppSpace.sm),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: AppText.labelMd.copyWith(color: primary ? AppColors.onSurface : AppColors.primaryFixed, fontWeight: primary ? FontWeight.w700 : FontWeight.w600),
          ),
        ),
      ),
    );

    return HeroPanel(
      padding: const EdgeInsets.all(AppSpace.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Symbols.auto_awesome, size: 18, color: AppColors.tertiaryFixed, fill: 1),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'NUTƆFE AI INSIGHT',
                  style: AppText.labelSm.copyWith(color: AppColors.primaryFixed, letterSpacing: 11 * 0.08),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(color: AppColors.onPrimary.withValues(alpha: 0.1), borderRadius: AppRadius.full),
                child: Text(badge.toUpperCase(), style: AppText.labelSm.copyWith(fontSize: 10, color: AppColors.primaryFixed)),
              ),
            ],
          ),
          Gap.sm,
          Text(insight.title, style: AppText.titleSm.copyWith(color: AppColors.onPrimary)),
          const SizedBox(height: 2),
          Text(
            insight.body,
            style: AppText.bodyMd.copyWith(color: AppColors.inverseOnSurface),
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
          ),
          Gap.md,
          Row(
            children: [
              if (actionLabel != null) ...[Expanded(child: button(actionLabel, onAct, primary: true)), Gap.sm],
              if (actionLabel == null) const Spacer(),
              button('View Detail', onDetail, primary: false),
            ],
          ),
        ],
      ),
    );
  }
}

/// Small square badge at the top of a schedule entry ("● IN PROGRESS", "UP NEXT").
class _Badge extends StatelessWidget {
  const _Badge(this.label, {required this.foreground, required this.background, this.dot});

  final String label;
  final Color foreground;
  final Color background;
  final Color? dot;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(color: background, borderRadius: AppRadius.small),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (dot != null) ...[
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
            ),
            const SizedBox(width: 4),
          ],
          Flexible(
            child: Text(
              label.toUpperCase(),
              style: AppText.labelSm.copyWith(fontSize: 10, color: foreground),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

/// One entry of the production schedule: time column with connector, then the card.
class ScheduleRow extends StatelessWidget {
  const ScheduleRow({super.key, required this.item, required this.position, required this.isLast, required this.onTap, this.timer, this.onPause, this.pausing = false});

  final ScheduleItem item;

  /// 1-based place in the "up next" queue.
  final int position;
  final bool isLast;
  final VoidCallback onTap;

  /// The running timer (for the live clock) when this is the timer entry.
  final ActiveTimer? timer;
  final VoidCallback? onPause;
  final bool pausing;

  @override
  Widget build(BuildContext context) {
    final running = item.kind == ScheduleKind.timer;
    final start = item.startsAt;
    final (main, sub) = start == null ? ('#$position', 'Queue') : (DateFormat('hh:mm').format(start), DateFormat('a').format(start));
    final badge = switch (item.kind) {
      ScheduleKind.timer => const _Badge('In Progress', foreground: AppColors.onSecondaryFixedVariant, background: AppColors.secondaryFixed, dot: AppColors.secondary),
      ScheduleKind.stage => const _Badge('Planned', foreground: AppColors.onSurfaceVariant, background: AppColors.surfaceContainerHighest),
      ScheduleKind.appointment => _Badge(item.location ?? item.appointmentType?.label ?? 'Appointment', foreground: AppColors.secondary, background: AppColors.surfaceContainerHigh),
      ScheduleKind.next => const _Badge('Up Next', foreground: AppColors.onSurfaceVariant, background: AppColors.surfaceContainerHighest),
    };
    final duration = switch (item.kind) {
      ScheduleKind.appointment => item.estimatedSeconds == null ? null : durationLabel(item.estimatedSeconds!),
      _ => item.remainingSeconds == null || item.remainingSeconds == 0 ? null : '${durationLabel(item.remainingSeconds!)} left',
    };
    final subtitle = [
      if (item.jobNumber != null) '#${item.jobNumber}',
      if (item.jobTitle != null) item.jobTitle!,
      if (item.kind == ScheduleKind.appointment && item.appointmentType != null && item.location != null) item.appointmentType!.label,
    ].join(' • ');

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 56,
          child: Column(
            children: [
              const SizedBox(height: 2),
              Text(main, style: AppText.metricNum.copyWith(fontSize: 18)),
              Text(sub.toUpperCase(), style: AppText.labelSm.copyWith(fontSize: 10, color: AppColors.onSurfaceVariant)),
              if (!isLast)
                Container(
                  width: 2,
                  height: 40,
                  margin: const EdgeInsets.only(top: AppSpace.sm),
                  color: running ? AppColors.secondary.withValues(alpha: 0.3) : AppColors.surfaceContainerHighest,
                ),
            ],
          ),
        ),
        Gap.md,
        Expanded(
          child: Material(
            color: running ? AppColors.surfaceContainerLow : AppColors.surface,
            borderRadius: AppRadius.control,
            child: InkWell(
              borderRadius: AppRadius.control,
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.all(AppSpace.sm),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Flexible(child: badge),
                        const Spacer(),
                        if (duration != null) Text(duration, style: AppText.labelSm.copyWith(color: AppColors.onSurfaceVariant)),
                      ],
                    ),
                    const SizedBox(height: AppSpace.xs),
                    Text(item.customerName == null ? item.title : '${item.title} — ${item.customerName}', style: AppText.titleSm, maxLines: 1, overflow: TextOverflow.ellipsis),
                    if (subtitle.isNotEmpty)
                      Text(
                        subtitle,
                        style: AppText.bodySm.copyWith(color: AppColors.onSurfaceVariant),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    if (running && timer != null) ...[
                      const SizedBox(height: AppSpace.xs),
                      Row(
                        children: [
                          _PauseButton(onPressed: pausing ? null : onPause),
                          Gap.sm,
                          Expanded(
                            child: Align(
                              alignment: Alignment.centerRight,
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Ticker(
                                  builder: (_, now) => Text(clockText(timer!.elapsed(now)), style: AppText.metricNum.copyWith(color: AppColors.secondary)),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _PauseButton extends StatelessWidget {
  const _PauseButton({required this.onPressed});

  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: onPressed == null ? AppColors.outline : AppColors.secondary,
      borderRadius: AppRadius.small,
      child: InkWell(
        borderRadius: AppRadius.small,
        onTap: onPressed,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Symbols.pause, size: 15, color: AppColors.onSecondary),
              const SizedBox(width: 4),
              Text('Pause Timer', style: AppText.labelSm.copyWith(color: AppColors.onSecondary)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Priority job card: number, customer, step, progress and the logged · remaining · due tiles.
class PriorityJobCard extends StatelessWidget {
  const PriorityJobCard({super.key, required this.job, required this.onTap});

  final Job job;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final stage = job.currentTask;
    final step = job.stepTotal == 0 ? null : 'Step ${job.stepIndex} of ${job.stepTotal}${stage == null ? '' : ' (${stage.typeName})'}';
    Widget tile(String caption, String value, {Color color = AppColors.onSurface, TextStyle? style}) => Expanded(
      child: InsetTile(
        padding: const EdgeInsets.all(AppSpace.sm),
        child: Column(
          children: [
            Text(caption, style: AppText.labelSm.copyWith(fontSize: 10, color: AppColors.onSurfaceVariant)),
            const SizedBox(height: 2),
            Text(value, style: (style ?? AppText.metricNum).copyWith(color: color), maxLines: 1),
          ],
        ),
      ),
    );

    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.all(AppSpace.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(job.displayNumber, style: AppText.labelSm.copyWith(color: AppColors.secondary)),
                        Gap.sm,
                        Expanded(
                          child: Text(job.customerName, style: AppText.titleSm, maxLines: 1, overflow: TextOverflow.ellipsis),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text([job.title, ?step].join(' • '), style: AppText.bodySm.copyWith(color: AppColors.onSurfaceVariant)),
                  ],
                ),
              ),
              Gap.sm,
              jobHeadlinePill(job),
            ],
          ),
          Gap.sm,
          Row(
            children: [
              Expanded(
                child: Text('Overall Progress', style: AppText.labelSm.copyWith(color: AppColors.onSurfaceVariant)),
              ),
              Text('${job.hours.progressPercent.round()}%', style: AppText.labelSm.copyWith(color: AppColors.onSurface)),
            ],
          ),
          const SizedBox(height: 6),
          JobProgressBar(percent: job.hours.progressPercent),
          Gap.sm,
          Row(
            children: [
              tile('LOGGED', '${Fmt.hours(job.hours.actualSeconds)}h'),
              Gap.sm,
              tile('REMAINING', '${Fmt.hours(job.hours.remainingSeconds)}h', color: AppColors.secondary),
              Gap.sm,
              tile('DUE DATE', job.dueDate == null ? '—' : Fmt.shortDate(job.dueDate!), color: job.flags.isOverdue ? AppColors.error : AppColors.onSurface, style: AppText.titleSm),
            ],
          ),
        ],
      ),
    );
  }
}

/// A material or tool that needs attention, with its quick action.
class AlertRow extends StatelessWidget {
  const AlertRow({super.key, required this.icon, required this.title, required this.subtitle, required this.subtitleColor, required this.actionLabel, required this.onAction, required this.onTap});

  factory AlertRow.material(InventoryItem item, {required VoidCallback onRestock, required VoidCallback onTap}) => AlertRow(
    icon: Symbols.layers,
    title: item.name,
    subtitle: switch (item.status) {
      StockStatus.negative => 'Below zero (${item.onHandLabel}): count the stock',
      StockStatus.out => 'Out of stock (Min: ${item.format(item.minStockLevel)})',
      _ => '${item.onHandLabel} left (Min: ${item.format(item.minStockLevel)})',
    },
    subtitleColor: AppColors.error,
    actionLabel: 'Restock',
    onAction: onRestock,
    onTap: onTap,
  );

  factory AlertRow.tool(Tool tool, {required VoidCallback onLog, required VoidCallback onTap}) => AlertRow(
    icon: toolIcon(tool),
    title: tool.name,
    subtitle: switch (tool) {
      Tool(maintenanceState: MaintenanceState.overdue) => 'Maintenance ${tool.dueLabel.toLowerCase()}',
      Tool(status: ToolStatus.outOfService) => 'Out of service',
      Tool(status: ToolStatus.needsService) => 'Needs service',
      _ => 'Maintenance ${tool.dueLabel.toLowerCase()}',
    },
    subtitleColor: tool.maintenanceState == MaintenanceState.overdue || tool.status == ToolStatus.outOfService ? AppColors.error : AppColors.onSurfaceVariant,
    actionLabel: 'Log',
    onAction: onLog,
    onTap: onTap,
  );

  final IconData icon;
  final String title;
  final String subtitle;
  final Color subtitleColor;
  final String actionLabel;
  final VoidCallback onAction;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.all(AppSpace.md),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(color: AppColors.surfaceContainerHigh, borderRadius: AppRadius.control),
            child: Icon(icon, size: 20, color: AppColors.onSurface),
          ),
          Gap.sm,
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AppText.titleSm, maxLines: 1, overflow: TextOverflow.ellipsis),
                Text(
                  subtitle,
                  style: AppText.bodySm.copyWith(color: subtitleColor, fontWeight: FontWeight.w500),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          Gap.md,
          AppButton(label: actionLabel, variant: AppButtonVariant.tonal, size: AppButtonSize.small, onPressed: onAction),
        ],
      ),
    );
  }
}

/// Section title row: headline, optional count pill, optional link on the right.
class DashboardSection extends StatelessWidget {
  const DashboardSection({super.key, required this.title, this.badge, this.trailing});

  final String title;
  final String? badge;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Row(
            children: [
              Flexible(
                child: Text(title, style: AppText.headlineMd, maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
              if (badge != null) ...[
                Gap.sm,
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(color: AppColors.surfaceContainer, borderRadius: AppRadius.full),
                  child: Text(badge!, style: AppText.labelSm.copyWith(color: AppColors.onSurfaceVariant)),
                ),
              ],
            ],
          ),
        ),
        ?trailing,
      ],
    );
  }
}

/// Text link with a trailing arrow ("Start Next →", "View All 14").
class DashboardLink extends StatelessWidget {
  const DashboardLink({super.key, required this.label, required this.onTap, this.arrow = false});

  final String label;
  final VoidCallback? onTap;
  final bool arrow;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: AppRadius.small,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label, style: AppText.labelMd.copyWith(color: AppColors.secondary)),
            if (arrow) ...[const SizedBox(width: 4), const Icon(Symbols.arrow_forward, size: 16, color: AppColors.secondary)],
          ],
        ),
      ),
    );
  }
}
