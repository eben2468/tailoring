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
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/feedback.dart';
import '../../../core/widgets/gap.dart';
import '../../../core/widgets/header_icon_button.dart';
import '../../../core/widgets/section_header.dart';
import '../../../core/widgets/state_views.dart';
import '../../../core/widgets/status_pill.dart';
import '../../sync/application/sync_providers.dart';
import '../application/tool_providers.dart';
import '../domain/tools.dart';
import 'maintenance_sheet.dart';
import 'tool_widgets.dart';

/// One tool: status and service dates, actions, details, and its maintenance history.
class ToolScreen extends ConsumerWidget {
  const ToolScreen({super.key, required this.toolId});

  final String toolId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return switch (ref.watch(toolProvider(toolId))) {
      AsyncData(:final value) => _ToolView(tool: value),
      AsyncError(:final error) => DetailScaffold(title: 'Tool', body: ErrorView(error: error, onRetry: () => ref.invalidate(bootstrapProvider))),
      _ => const DetailScaffold(title: 'Tool', body: LoadingView()),
    };
  }
}

class _ToolView extends ConsumerWidget {
  const _ToolView({required this.tool});

  final Tool tool;

  Future<void> _act(BuildContext context, Future<void> Function() action, String done) async {
    try {
      await action();
      if (context.mounted) showAppSnack(context, done);
    } on ApiException catch (e) {
      if (context.mounted) showAppSnack(context, e.message, isError: true);
    }
  }

  Future<void> _status(BuildContext context, WidgetRef ref) async {
    final picked = await showModalBottomSheet<ToolStatus>(
      context: context,
      useRootNavigator: true,
      useSafeArea: true,
      builder: (context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Status', style: AppText.headlineMd),
          Gap.md,
          for (final s in ToolStatus.values)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(s.choiceLabel, style: AppText.bodyLg),
              subtitle: Text(switch (s) {
                ToolStatus.operational => 'In working order',
                ToolStatus.needsService => 'Works, but needs attention soon',
                ToolStatus.outOfService => 'Cannot be used until repaired',
                ToolStatus.retired => 'No longer used; no service reminders',
              }, style: AppText.bodySm.copyWith(color: AppColors.onSurfaceVariant)),
              trailing: s == tool.status ? const Icon(Symbols.check, color: AppColors.secondary) : null,
              onTap: () => Navigator.of(context).pop(s),
            ),
        ]),
      ),
    );
    if (picked == null || picked == tool.status || !context.mounted) return;
    await _act(context, () => ref.read(toolsApiProvider).setStatus(tool, picked), 'Status: ${picked.choiceLabel.toLowerCase()}.');
  }

  Future<void> _archive(BuildContext context, WidgetRef ref) async {
    final archiving = !tool.isArchived;
    if (archiving &&
        !await confirmAction(
          context,
          title: 'Archive ${tool.name}?',
          message: 'It leaves the roster and service reminders. Its history is kept, and you can restore it at any time.',
          confirmLabel: 'Archive',
        )) {
      return;
    }
    if (!context.mounted) return;
    await _act(context, () => ref.read(toolsApiProvider).setArchived(tool, archived: archiving), archiving ? 'Tool archived.' : 'Tool restored.');
  }

  Future<void> _removeLog(BuildContext context, WidgetRef ref, MaintenanceLog log) async {
    final ok = await confirmAction(
      context,
      title: 'Remove this entry?',
      message: '${log.type.label} on ${toolDate(log.performedOn)} will no longer count, and the service dates are worked out again from the other entries.',
      confirmLabel: 'Remove',
      destructive: true,
    );
    if (!ok || !context.mounted) return;
    await _act(context, () => ref.read(toolsApiProvider).deleteLog(log, tool.name), 'Maintenance entry removed.');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final logs = ref.watch(toolLogsProvider(tool.id)).value ?? const <MaintenanceLog>[];
    final (pill, tone) = toolPill(tool);

    return DetailScaffold(
      title: tool.name,
      actions: [
        PopupMenuButton<String>(
          tooltip: 'More',
          padding: EdgeInsets.zero,
          shape: RoundedRectangleBorder(borderRadius: AppRadius.card),
          child: const HeaderIconButton(icon: Symbols.more_vert),
          onSelected: (v) => switch (v) {
            'edit' => context.push(Routes.toolEdit(tool.id)),
            'status' => _status(context, ref),
            _ => _archive(context, ref),
          },
          itemBuilder: (_) => [
            if (!tool.isArchived) const PopupMenuItem(value: 'edit', child: Text('Edit details')),
            if (!tool.isArchived) const PopupMenuItem(value: 'status', child: Text('Change status')),
            PopupMenuItem(value: 'archive', child: Text(tool.isArchived ? 'Restore tool' : 'Archive tool')),
          ],
        ),
      ],
      body: ListView(padding: belowHeader(context), children: [
        if (tool.isArchived) ...[
          AppCard(
            color: AppColors.surfaceContainerHigh,
            child: Row(children: [
              const Icon(Symbols.archive, size: 20, color: AppColors.onSurfaceVariant),
              Gap.sm,
              Expanded(child: Text('Archived. Restore it to log maintenance.', style: AppText.bodyMd)),
              AppButton(label: 'Restore', size: AppButtonSize.small, variant: AppButtonVariant.outline, onPressed: () => _archive(context, ref)),
            ]),
          ),
          Gap.md,
        ],
        AppCard(
          padding: const EdgeInsets.all(AppSpace.lg),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(color: AppColors.surfaceContainerHigh, borderRadius: AppRadius.control),
                child: Icon(toolIcon(tool), size: 26, color: AppColors.onPrimaryFixedVariant),
              ),
              Gap.md,
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text([tool.categoryName?.toUpperCase(), tool.storageLocation].whereType<String>().join('  •  '), style: AppText.overline, maxLines: 1, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 2),
                  Text(tool.name, style: AppText.headlineMd),
                  if (tool.brandModel != null) Text(tool.brandModel!, style: AppText.bodySm.copyWith(color: AppColors.onSurfaceVariant)),
                ]),
              ),
              Gap.sm,
              StatusPill(label: pill, tone: tone),
            ]),
            Gap.lg,
            InsetTile(
              padding: const EdgeInsets.all(AppSpace.md),
              child: Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Next service', style: AppText.bodySm.copyWith(color: AppColors.onSurfaceVariant)),
                    Text(tool.nextMaintenance == null ? '—' : toolDate(tool.nextMaintenance!), style: AppText.titleSm),
                    Text(tool.dueLabel, style: AppText.labelMd.copyWith(color: dueColor(tool))),
                  ]),
                ),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Last service', style: AppText.bodySm.copyWith(color: AppColors.onSurfaceVariant)),
                    Text(tool.lastMaintenance == null ? 'Never logged' : toolDate(tool.lastMaintenance!), style: AppText.titleSm),
                    Text(tool.intervalDays == null ? 'No service cycle' : 'Every ${tool.intervalDays} days', style: AppText.labelMd.copyWith(color: AppColors.onSurfaceVariant)),
                  ]),
                ),
              ]),
            ),
            if (tool.nextOverride != null) ...[
              Gap.sm,
              Text('Next date set by hand. Logging maintenance returns to the service cycle.', style: AppText.bodySm.copyWith(color: AppColors.onSurfaceVariant)),
            ],
            if (!tool.isArchived) ...[
              Gap.lg,
              Row(children: [
                Expanded(child: AppButton(label: 'Record Maintenance', icon: Symbols.build, size: AppButtonSize.medium, expand: true, onPressed: () async {
                  final saved = await showMaintenanceSheet(context, toolId: tool.id);
                  if (saved == true && context.mounted) showAppSnack(context, 'Maintenance logged for ${tool.name}.');
                })),
                Gap.sm,
                AppButton(label: 'Change Date', icon: Symbols.event, size: AppButtonSize.medium, variant: AppButtonVariant.tonal, onPressed: () => changeNextServiceDate(context, ref, tool)),
              ]),
            ],
          ]),
        ),
        Gap.md,
        AppCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Kicker('Details'),
            Gap.sm,
            _Detail(icon: Symbols.verified, label: 'Condition', value: tool.condition.label),
            _Detail(icon: Symbols.toggle_on, label: 'Status', value: tool.status.choiceLabel),
            _Detail(icon: Symbols.tag, label: 'Serial number', value: tool.serialNumber),
            _Detail(icon: Symbols.shopping_cart, label: 'Purchased', value: tool.purchaseDate == null ? null : toolDate(tool.purchaseDate!)),
            _Detail(icon: Symbols.shelves, label: 'Location', value: tool.storageLocation),
            if (tool.notes != null) ...[Gap.sm, Text(tool.notes!, style: AppText.bodyMd)],
          ]),
        ),
        Gap.md,
        AppCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            SectionHeader(title: 'Service history', count: '${logs.length}'),
            if (logs.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpace.md),
                child: Text('No maintenance logged yet.', style: AppText.bodyMd.copyWith(color: AppColors.onSurfaceVariant)),
              )
            else
              for (final (i, log) in logs.indexed) ...[
                if (i > 0) const Divider(height: 1, color: AppColors.surfaceContainer),
                InkWell(
                  onLongPress: tool.isArchived ? null : () => _removeLog(context, ref, log),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(color: AppColors.surfaceContainerLow, borderRadius: AppRadius.control),
                        child: Icon(log.type.icon, size: 18, color: AppColors.onPrimaryFixedVariant),
                      ),
                      Gap.md,
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(log.type.label, style: AppText.labelMd),
                          if (log.description != null) Text(log.description!, style: AppText.bodySm.copyWith(color: AppColors.onSurfaceVariant)),
                          Text(
                            [if (log.performedBy != null) 'By ${log.performedBy}', if (log.conditionAfter != null) 'Condition: ${log.conditionAfter!.label.toLowerCase()}'].join(' · '),
                            style: AppText.labelSm.copyWith(color: AppColors.outline, fontWeight: FontWeight.w500),
                          ),
                        ]),
                      ),
                      Gap.sm,
                      Text(toolDate(log.performedOn), style: AppText.labelMd.copyWith(color: AppColors.onSurfaceVariant)),
                      if (!tool.isArchived)
                        IconButton(
                          tooltip: 'Remove entry',
                          visualDensity: VisualDensity.compact,
                          icon: const Icon(Symbols.delete, size: 18, color: AppColors.outline),
                          onPressed: () => _removeLog(context, ref, log),
                        ),
                    ]),
                  ),
                ),
              ],
          ]),
        ),
      ]),
    );
  }
}

class _Detail extends StatelessWidget {
  const _Detail({required this.icon, required this.label, required this.value});

  final IconData icon;
  final String label;
  final String? value;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(children: [
          Icon(icon, size: 18, color: AppColors.onSurfaceVariant),
          Gap.sm,
          SizedBox(width: 112, child: Text(label, style: AppText.bodySm.copyWith(color: AppColors.onSurfaceVariant))),
          Expanded(child: Text(value ?? '—', style: AppText.labelMd.copyWith(color: value == null ? AppColors.outline : AppColors.onSurface))),
        ]),
      );
}
