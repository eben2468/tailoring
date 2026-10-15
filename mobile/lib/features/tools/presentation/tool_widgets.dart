import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/widgets/hero_panel.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/gap.dart';
import '../../../core/widgets/status_pill.dart';
import '../domain/tools.dart';

final _date = DateFormat('d MMM yyyy');

String toolDate(DateTime d) => _date.format(d);

/// Status pill: overdue maintenance wins over the operational status.
(String, StatusTone) toolPill(Tool t) => switch (t.status) {
      ToolStatus.outOfService => (t.status.label, StatusTone.danger),
      ToolStatus.retired => (t.status.label, StatusTone.neutral),
      ToolStatus.needsService => (t.status.label, StatusTone.danger),
      ToolStatus.operational when t.maintenanceState == MaintenanceState.overdue => ('Svc Overdue', StatusTone.danger),
      ToolStatus.operational when t.maintenanceState == MaintenanceState.dueSoon => ('Svc Due', StatusTone.warning),
      ToolStatus.operational => (t.status.label, StatusTone.success),
    };

/// Icon for a tool from its category's name (categories are the owner's own, so match by words; the design
/// uses a different icon per kind of equipment). Falls back to the machine icon.
IconData toolIcon(Tool t) {
  final c = (t.categoryName ?? '').toLowerCase();
  return switch (c) {
    _ when c.contains('iron') || c.contains('press') || c.contains('steam') => Symbols.iron,
    _ when c.contains('cut') || c.contains('shear') || c.contains('scissor') => Symbols.content_cut,
    _ when c.contains('measur') || c.contains('tape') || c.contains('rule') => Symbols.straighten,
    _ when c.contains('sew') || c.contains('machine') || c.contains('overlock') => Symbols.precision_manufacturing,
    _ => Symbols.handyman,
  };
}

Color dueColor(Tool t) => switch (t.maintenanceState) {
      MaintenanceState.overdue => AppColors.error,
      MaintenanceState.dueSoon => AppColors.warning,
      MaintenanceState.ok => AppColors.secondary,
      MaintenanceState.none => AppColors.onSurfaceVariant,
    };

/// Stitch "Equip & Calibrate" banner: dark card with the fleet counts.
class FleetBanner extends StatelessWidget {
  const FleetBanner({super.key, required this.summary});

  final ToolSummary summary;

  @override
  Widget build(BuildContext context) {
    final due = summary.dueSoon + summary.overdue;
    Widget stat(String value, String label, {Color? dot}) => Expanded(
          child: Column(children: [
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              if (dot != null) ...[Container(width: 6, height: 6, decoration: BoxDecoration(color: dot, shape: BoxShape.circle)), const SizedBox(width: 4)],
              Text(value, style: AppText.metricNum.copyWith(color: AppColors.onPrimary)),
            ]),
            const SizedBox(height: 2),
            Text(label, style: AppText.labelSm.copyWith(color: AppColors.primaryFixedDim, fontWeight: FontWeight.w500), maxLines: 1, overflow: TextOverflow.ellipsis),
          ]),
        );
    return HeroPanel(
      padding: const EdgeInsets.all(AppSpace.lg),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(width: 6, height: 6, decoration: const BoxDecoration(color: AppColors.tertiaryFixedDim, shape: BoxShape.circle)),
          const SizedBox(width: 6),
          Text('WORKSHOP EQUIPMENT', style: AppText.labelSm.copyWith(color: AppColors.primaryFixedDim, letterSpacing: 11 * 0.08)),
        ]),
        const SizedBox(height: 2),
        Text('Equip & Calibrate', style: AppText.headlineLg.copyWith(color: AppColors.onPrimary)),
        Gap.md,
        Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(color: AppColors.onPrimary.withValues(alpha: 0.08), borderRadius: AppRadius.control),
          child: Row(children: [
            stat('${summary.total}', 'Total Units'),
            stat('${summary.operational}', 'Operational', dot: AppColors.tertiaryFixedDim),
            stat('$due', 'Due Svc', dot: due > 0 ? AppColors.warningAccent : null),
            stat('${summary.outOfService}', 'Out of Svc', dot: summary.outOfService > 0 ? AppColors.error : null),
          ]),
        ),
      ]),
    );
  }
}

/// Stitch "Imminent Action": the most urgent tool, with Log Service and Change date.
class ImminentActionCard extends StatelessWidget {
  const ImminentActionCard({super.key, required this.tool, required this.onLog, required this.onChangeDate, required this.onOpen});

  final Tool tool;
  final VoidCallback onLog;
  final VoidCallback onChangeDate;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final overdue = tool.maintenanceState == MaintenanceState.overdue;
    final badge = switch (tool) {
      _ when overdue => '${-tool.daysUntilDue!} Days Overdue',
      _ when tool.status == ToolStatus.outOfService => 'Out of Service',
      _ when tool.status == ToolStatus.needsService => 'Needs Service',
      _ when tool.daysUntilDue == 0 => 'Due Today',
      _ => '${tool.daysUntilDue} Days Left',
    };
    final detail = [
      if (tool.lastMaintenance != null) 'Last service ${toolDate(tool.lastMaintenance!)}' else 'No service logged yet',
      if (tool.intervalDays != null) 'every ${tool.intervalDays} days',
      if (tool.nextMaintenance != null) 'due ${toolDate(tool.nextMaintenance!)}',
    ].join(', ');
    return Material(
      color: AppColors.errorContainer,
      borderRadius: AppRadius.card,
      child: InkWell(
        borderRadius: AppRadius.card,
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.all(AppSpace.lg),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(color: AppColors.error, borderRadius: AppRadius.small),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Symbols.alarm, size: 14, color: AppColors.onError),
                  const SizedBox(width: 4),
                  Text('IMMINENT ACTION', style: AppText.labelSm.copyWith(color: AppColors.onError)),
                ]),
              ),
              Gap.sm,
              Flexible(child: Text(badge, style: AppText.labelMd.copyWith(color: AppColors.onErrorContainer), maxLines: 1, overflow: TextOverflow.ellipsis)),
              const Spacer(),
              const Icon(Symbols.priority_high, size: 24, color: AppColors.error),
            ]),
            Gap.sm,
            Text(tool.name, style: AppText.headlineMd.copyWith(color: AppColors.onErrorContainer)),
            const SizedBox(height: 2),
            Text(detail, style: AppText.bodyMd.copyWith(color: AppColors.onErrorContainer)),
            Gap.md,
            Row(children: [
              Expanded(child: AppButton(label: 'Log Service', size: AppButtonSize.medium, expand: true, onPressed: onLog)),
              Gap.sm,
              Expanded(child: AppButton(label: 'Change Date', size: AppButtonSize.medium, variant: AppButtonVariant.outline, expand: true, onPressed: onChangeDate)),
            ]),
          ]),
        ),
      ),
    );
  }
}

/// Roster card: icon, category · location, name, status; condition and service dates; cycle and actions.
class ToolCard extends StatelessWidget {
  const ToolCard({super.key, required this.tool, required this.onTap, required this.onLog});

  final Tool tool;
  final VoidCallback onTap;
  final VoidCallback onLog;

  @override
  Widget build(BuildContext context) {
    final (pill, tone) = toolPill(tool);
    final urgent = tool.needsAttention && tool.status != ToolStatus.retired;
    final card = AppCard(
      padding: const EdgeInsets.all(AppSpace.lg),
      onTap: onTap,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(color: AppColors.surfaceContainerHigh, borderRadius: AppRadius.control),
            child: Icon(toolIcon(tool), size: 22, color: AppColors.onPrimaryFixedVariant),
          ),
          Gap.md,
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Flexible(flex: 3, child: Text((tool.categoryName ?? '').toUpperCase(), style: AppText.overline, maxLines: 1, overflow: TextOverflow.ellipsis)),
                if (tool.storageLocation != null) ...[
                  Text('  •  ', style: AppText.labelSm.copyWith(color: AppColors.outlineVariant)),
                  Flexible(flex: 2, child: Text(tool.storageLocation!, style: AppText.labelSm.copyWith(color: AppColors.onTertiaryContainer), maxLines: 1, overflow: TextOverflow.ellipsis)),
                ],
              ]),
              const SizedBox(height: 2),
              Text(tool.name, style: AppText.titleSm, maxLines: 1, overflow: TextOverflow.ellipsis),
              if (tool.brandModel != null) Text(tool.brandModel!, style: AppText.bodySm.copyWith(color: AppColors.onSurfaceVariant), maxLines: 1, overflow: TextOverflow.ellipsis),
            ]),
          ),
          Gap.sm,
          StatusPill(label: pill, tone: tone),
        ]),
        Gap.md,
        InsetTile(
          padding: const EdgeInsets.all(10),
          child: Column(children: [
            Row(children: [
              Expanded(child: _Field(label: 'Condition', value: tool.condition.label, color: tool.condition == ToolCondition.poor ? AppColors.error : AppColors.onTertiaryContainer)),
              Expanded(child: _Field(label: 'Serial', value: tool.serialNumber ?? '—')),
            ]),
            Gap.sm,
            Row(children: [
              Expanded(
                child: Text(
                  tool.lastMaintenance == null ? 'No service logged' : 'Last Svc: ${toolDate(tool.lastMaintenance!)}',
                  style: AppText.bodySm.copyWith(color: AppColors.onSurfaceVariant),
                ),
              ),
              Text(tool.dueLabel, style: AppText.labelMd.copyWith(color: dueColor(tool))),
            ]),
          ]),
        ),
        Gap.md,
        if (urgent && !tool.isArchived)
          AppButton(label: 'Record Maintenance', icon: Symbols.build, size: AppButtonSize.medium, expand: true, onPressed: onLog)
        else
          Row(children: [
            const Icon(Symbols.schedule, size: 16, color: AppColors.onSurfaceVariant),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                tool.intervalDays == null ? 'No service cycle set' : 'Service Cycle: ${tool.intervalDays} Days',
                style: AppText.bodySm.copyWith(color: AppColors.onSurfaceVariant),
              ),
            ),
            Text('Details', style: AppText.labelMd.copyWith(color: AppColors.secondary)),
            const Icon(Symbols.chevron_right, size: 18, color: AppColors.secondary),
          ]),
      ]),
    );
    if (!urgent) return card;
    // Accent bar on the left, like the Stitch "Svc Pending" card.
    return ClipRRect(
      borderRadius: AppRadius.card,
      child: Stack(children: [
        card,
        Positioned(left: 0, top: 0, bottom: 0, child: Container(width: 4, color: tool.maintenanceState == MaintenanceState.dueSoon && tool.status == ToolStatus.operational ? AppColors.warningAccent : AppColors.error)),
      ]),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({required this.label, required this.value, this.color});

  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: AppText.bodySm.copyWith(color: AppColors.onSurfaceVariant)),
        Text(value, style: AppText.labelMd.copyWith(color: color ?? AppColors.onSurface), maxLines: 1, overflow: TextOverflow.ellipsis),
      ]);
}
