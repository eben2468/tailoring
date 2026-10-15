import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../core/widgets/feedback.dart';
import '../../../core/widgets/filter_pills.dart';
import '../../../core/widgets/gap.dart';
import '../../../core/widgets/section_header.dart';
import '../../../core/widgets/state_views.dart';
import '../application/tool_providers.dart';
import '../domain/tools.dart';
import 'tool_widgets.dart';

/// Log maintenance done on a tool. Returns true when saved.
Future<bool?> showMaintenanceSheet(BuildContext context, {required String toolId}) => showModalBottomSheet<bool>(
      context: context,
      useRootNavigator: true, // above the bottom navigation and timer bar
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _MaintenanceSheet(toolId: toolId),
    );

/// Sets or clears a manual next-service date. Returns true when changed.
Future<bool> changeNextServiceDate(BuildContext context, WidgetRef ref, Tool tool) async {
  final today = DateTime.now();
  final picked = await showDatePicker(
    context: context,
    initialDate: tool.nextMaintenance != null && !tool.nextMaintenance!.isBefore(DateTime(today.year, today.month, today.day)) ? tool.nextMaintenance! : today,
    firstDate: DateTime(today.year, today.month, today.day),
    lastDate: today.add(const Duration(days: 3650)),
    helpText: 'Next service date',
  );
  if (picked == null || !context.mounted) return false;
  try {
    await ref.read(toolsApiProvider).setNextDate(tool, picked);
    if (context.mounted) showAppSnack(context, 'Next service set for ${toolDate(picked)}.');
    return true;
  } on ApiException catch (e) {
    if (context.mounted) showAppSnack(context, e is ValidationException ? (e.fieldErrors.values.firstOrNull?.first ?? e.message) : e.message, isError: true);
    return false;
  }
}

class _MaintenanceSheet extends ConsumerStatefulWidget {
  const _MaintenanceSheet({required this.toolId});

  final String toolId;

  @override
  ConsumerState<_MaintenanceSheet> createState() => _MaintenanceSheetState();
}

class _MaintenanceSheetState extends ConsumerState<_MaintenanceSheet> {
  MaintenanceType _type = MaintenanceType.routine;
  DateTime _day = DateTime.now();
  ToolCondition? _condition;
  ToolStatus? _status;
  bool _statusInitialised = false;
  final _description = TextEditingController();
  final _by = TextEditingController();
  Map<String, String> _errors = const {};
  bool _saving = false;

  @override
  void dispose() {
    _description.dispose();
    _by.dispose();
    super.dispose();
  }

  Future<void> _save(Tool tool) async {
    setState(() {
      _saving = true;
      _errors = const {};
    });
    try {
      await ref.read(toolsApiProvider).logMaintenance(
            tool,
            type: _type,
            performedOn: _day,
            description: _description.text,
            performedBy: _by.text,
            conditionAfter: _condition,
            status: _status == tool.status ? null : _status,
          );
      if (mounted) Navigator.of(context).pop(true);
    } on ValidationException catch (e) {
      if (mounted) setState(() => _errors = {for (final entry in e.fieldErrors.entries) entry.key: entry.value.first});
    } on ApiException catch (e) {
      if (mounted) showAppSnack(context, e.message, isError: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tool = ref.watch(toolProvider(widget.toolId)).value;
    if (tool == null) return const SizedBox(height: 240, child: LoadingView());
    if (!_statusInitialised) {
      // A tool waiting for service is usually back in order after it.
      _status = tool.status == ToolStatus.needsService || tool.status == ToolStatus.outOfService ? ToolStatus.operational : tool.status;
      _statusInitialised = true;
    }
    final today = DateTime.now();
    final isToday = _day.year == today.year && _day.month == today.month && _day.day == today.day;
    const statuses = [ToolStatus.operational, ToolStatus.needsService, ToolStatus.outOfService];

    return Padding(
      padding: EdgeInsets.fromLTRB(AppSpace.margin, 0, AppSpace.margin, AppSpace.lg + MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Record maintenance', style: AppText.headlineMd),
          Text(tool.name, style: AppText.bodyMd.copyWith(color: AppColors.onSurfaceVariant), maxLines: 1, overflow: TextOverflow.ellipsis),
          Gap.md,
          FilterPills(labels: [for (final t in MaintenanceType.values) t.label], selected: MaintenanceType.values.indexOf(_type), onChanged: (i) => setState(() => _type = MaintenanceType.values[i])),
          Gap.md,
          Material(
            color: AppColors.surfaceContainerLow,
            borderRadius: AppRadius.control,
            child: InkWell(
              borderRadius: AppRadius.control,
              onTap: () async {
                final picked = await showDatePicker(context: context, initialDate: _day, firstDate: today.subtract(const Duration(days: 3650)), lastDate: today, helpText: 'Done on');
                if (picked != null) setState(() => _day = picked);
              },
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(children: [
                  const Icon(Symbols.event, size: 18, color: AppColors.onSurfaceVariant),
                  Gap.sm,
                  Expanded(child: Text('Done ${isToday ? 'today' : 'on ${toolDate(_day)}'}', style: AppText.bodyMd)),
                  const Icon(Symbols.expand_more, size: 20, color: AppColors.outline),
                ]),
              ),
            ),
          ),
          if (_errors['performed_on'] != null) Padding(padding: const EdgeInsets.only(top: 4), child: Text(_errors['performed_on']!, style: AppText.bodySm.copyWith(color: AppColors.error))),
          Gap.md,
          AppTextField(label: 'What was done', hint: 'e.g. Oil flush, needle-bar alignment', controller: _description, maxLines: 2, minLines: 1, maxLength: 2000, textCapitalization: TextCapitalization.sentences, errorText: _errors['description']),
          Gap.md,
          AppTextField(label: 'Done by (optional)', hint: 'e.g. Owner, or the technician', controller: _by, maxLength: 120, textCapitalization: TextCapitalization.words, errorText: _errors['performed_by']),
          Gap.md,
          const Kicker('Condition after'),
          Gap.sm,
          FilterPills(
            labels: ['Unchanged', for (final c in ToolCondition.values) c.label],
            selected: _condition == null ? 0 : ToolCondition.values.indexOf(_condition!) + 1,
            onChanged: (i) => setState(() => _condition = i == 0 ? null : ToolCondition.values[i - 1]),
          ),
          if (tool.status != ToolStatus.retired) ...[
            Gap.md,
            const Kicker('Status after'),
            Gap.sm,
            FilterPills(
              labels: [for (final s in statuses) s.choiceLabel],
              selected: statuses.indexOf(_status ?? tool.status),
              onChanged: (i) => setState(() => _status = statuses[i]),
            ),
          ],
          if (tool.intervalDays != null) ...[
            Gap.md,
            InsetTile(
              child: Text(
                'Next service: ${toolDate(_day.add(Duration(days: tool.intervalDays!)))} (every ${tool.intervalDays} days)',
                style: AppText.bodySm.copyWith(color: AppColors.onSurfaceVariant),
              ),
            ),
          ],
          Gap.lg,
          AppButton(label: 'Save maintenance', icon: Symbols.build, expand: true, loading: _saving, onPressed: () => _save(tool)),
        ]),
      ),
    );
  }
}
