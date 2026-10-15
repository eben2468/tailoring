import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import '../../../core/widgets/menu_row.dart';
import '../../../core/widgets/section_header.dart';
import '../../../core/widgets/state_views.dart';
import '../../../core/widgets/status_pill.dart';
import '../../sync/application/sync_providers.dart';
import '../application/job_providers.dart';
import '../domain/job.dart';
import 'job_sheets.dart';

/// Settings → Garment templates: every garment type with its stages and standard hours.
class GarmentTypesScreen extends ConsumerWidget {
  const GarmentTypesScreen({super.key});

  Future<void> _add(BuildContext context, WidgetRef ref) async {
    final name = await askText(context, title: 'New garment type', label: 'Name', hint: 'e.g. Smock (Fugu)', confirmLabel: 'Continue', maxLength: 100);
    if (name == null || !context.mounted) return;
    try {
      final types = ref.read(taskTypesProvider).value ?? const <TaskType>[];
      final work = types.where((t) => !t.isMilestone).toList();
      final ready = types.where((t) => t.code == 'ready_for_collection').firstOrNull;
      // Start from a minimal routing the owner then edits: first work stage + Ready for Collection.
      final created = await ref
          .read(jobsApiProvider)
          .createJobType(
            name: name,
            tasks: [
              if (work.isNotEmpty) PlannedTask(taskType: work.first, name: work.first.name, estimatedSeconds: 0),
              if (ready != null) PlannedTask(taskType: ready, name: ready.name, estimatedSeconds: 0),
            ],
          );
      ref
        ..invalidate(allJobTypesProvider)
        ..invalidate(jobTypesProvider);
      if (context.mounted) await context.push(Routes.garmentType(created.id));
    } on ApiException catch (e) {
      if (context.mounted) showAppSnack(context, e.message, isError: true);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final types = ref.watch(allJobTypesProvider);
    return DetailScaffold(
      title: 'Garment Templates',
      body: switch (types) {
        AsyncData(:final value) => ListView(
          padding: belowHeader(context, bottom: 32),
          children: [
            Text('Garment Templates', style: AppText.headlineLg),
            Gap.xs,
            Text('Each garment starts with these stages and standard hours. Changes apply to new jobs only.', style: AppText.bodyMd.copyWith(color: AppColors.onSurfaceVariant)),
            Gap.lg,
            MenuGroup(
              children: [
                for (final type in value)
                  MenuRow(
                    icon: Symbols.apparel,
                    title: type.name,
                    subtitle:
                        '${type.tasks.where((t) => !t.taskType.isMilestone).length} stages · '
                        '${type.estimatedSeconds == 0 ? 'hours not set' : '${Fmt.hours(type.estimatedSeconds)} h'}'
                        '${type.isActive ? '' : ' · hidden'}',
                    subtitleColor: type.estimatedSeconds == 0 ? AppColors.warning : null,
                    onTap: () => context.push(Routes.garmentType(type.id)),
                  ),
              ],
            ),
            Gap.lg,
            AppButton(label: 'Add garment type', icon: Symbols.add, variant: AppButtonVariant.tonal, expand: true, onPressed: () => _add(context, ref)),
          ],
        ),
        AsyncError(:final error) => ErrorView(error: error, onRetry: () => ref.invalidate(bootstrapProvider)),
        _ => const LoadingView(),
      },
    );
  }
}

/// Edit one garment's routing: stage names, order and standard hours; hide the garment from new jobs.
class GarmentTemplateScreen extends ConsumerWidget {
  const GarmentTemplateScreen({super.key, required this.jobTypeId});

  final int jobTypeId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final types = ref.watch(allJobTypesProvider);
    return switch (types) {
      AsyncData(:final value) => switch (value.where((t) => t.id == jobTypeId).firstOrNull) {
        final type? => _TemplateEditor(type: type),
        null => const DetailScaffold(
          title: 'Garment',
          body: MessageView(icon: Symbols.search_off, title: 'Garment not found', message: 'It may have been removed on another device.'),
        ),
      },
      AsyncError(:final error) => DetailScaffold(
        title: 'Garment',
        body: ErrorView(error: error, onRetry: () => ref.invalidate(bootstrapProvider)),
      ),
      _ => const DetailScaffold(title: 'Garment', body: LoadingView()),
    };
  }
}

class _TemplateEditor extends ConsumerStatefulWidget {
  const _TemplateEditor({required this.type});

  final JobType type;

  @override
  ConsumerState<_TemplateEditor> createState() => _TemplateEditorState();
}

class _Row {
  _Row(this.taskType, String name, int seconds) : name = TextEditingController(text: name), hours = TextEditingController(text: taskType.isMilestone ? '' : Fmt.hours(seconds));

  final TaskType taskType;
  final TextEditingController name;
  final TextEditingController hours;

  void dispose() {
    name.dispose();
    hours.dispose();
  }
}

class _TemplateEditorState extends ConsumerState<_TemplateEditor> {
  late final List<_Row> _rows = [for (final t in widget.type.tasks) _Row(t.taskType, t.name, t.estimatedSeconds)];
  final Set<int> _bad = {};
  bool _saving = false;

  @override
  void dispose() {
    for (final r in _rows) {
      r.dispose();
    }
    super.dispose();
  }

  int get _total => _rows.fold(0, (sum, r) => sum + (r.taskType.isMilestone ? 0 : (Fmt.parseHours(r.hours.text) ?? 0)));

  Future<void> _addStage() async {
    final types = ref.read(taskTypesProvider).value ?? const <TaskType>[];
    if (!mounted) return;
    final picked = await showModalBottomSheet<TaskType>(
      context: context,
      useRootNavigator: true, // above the bottom navigation and timer bar
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => Padding(
        padding: const EdgeInsets.fromLTRB(AppSpace.margin, 0, AppSpace.margin, AppSpace.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Add a stage', style: AppText.headlineMd),
            Gap.md,
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  MenuGroup(
                    children: [
                      for (final t in types)
                        MenuRow(icon: t.isMilestone ? Symbols.flag : Symbols.content_cut, title: t.name, subtitle: t.isMilestone ? 'Milestone' : null, onTap: () => Navigator.of(context).pop(t)),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
    if (picked == null) return;
    setState(() {
      // Work stages go before the trailing milestones.
      var at = _rows.length;
      if (!picked.isMilestone) {
        while (at > 0 && _rows[at - 1].taskType.isMilestone) {
          at--;
        }
      }
      _rows.insert(at, _Row(picked, picked.name, 0));
    });
  }

  void _move(int i, int delta) {
    final to = i + delta;
    if (to < 0 || to >= _rows.length) return;
    setState(() => _rows.insert(to, _rows.removeAt(i)));
  }

  Future<void> _save() async {
    final tasks = <PlannedTask>[];
    _bad.clear();
    for (final (i, r) in _rows.indexed) {
      final seconds = r.taskType.isMilestone ? 0 : Fmt.parseHours(r.hours.text);
      if (seconds == null || r.name.text.trim().isEmpty) _bad.add(i);
      tasks.add(PlannedTask(taskType: r.taskType, name: r.name.text.trim(), estimatedSeconds: seconds ?? 0));
    }
    if (_bad.isNotEmpty) {
      setState(() {});
      showAppSnack(context, 'Check the highlighted stages: each needs a name and hours (e.g. 2.5).', isError: true);
      return;
    }
    setState(() => _saving = true);
    try {
      await ref.read(jobsApiProvider).saveTemplates(widget.type.id, tasks);
      ref
        ..invalidate(allJobTypesProvider)
        ..invalidate(jobTypesProvider);
      if (mounted) {
        showAppSnack(context, 'Saved. New ${widget.type.name} jobs will use these stages.');
        context.pop();
      }
    } on ApiException catch (e) {
      if (mounted) showAppSnack(context, e is ValidationException ? (e.fieldErrors.values.firstOrNull?.firstOrNull ?? e.message) : e.message, isError: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _toggleActive() async {
    try {
      await ref.read(jobsApiProvider).updateJobType(widget.type.id, isActive: !widget.type.isActive);
      ref
        ..invalidate(allJobTypesProvider)
        ..invalidate(jobTypesProvider);
      if (mounted) showAppSnack(context, widget.type.isActive ? '${widget.type.name} is hidden from new jobs.' : '${widget.type.name} is available for new jobs.');
    } on ApiException catch (e) {
      if (mounted) showAppSnack(context, e.message, isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final type = widget.type;
    return DetailScaffold(
      title: 'Garment Template',
      bottomBar: BottomActionBar(
        child: AppButton(label: 'Save Stages', icon: Symbols.check, expand: true, loading: _saving, onPressed: _save),
      ),
      body: ListView(
        padding: belowHeader(context, bottom: 24),
        children: [
          Row(
            children: [
              Expanded(child: Text(type.name, style: AppText.headlineLg)),
              if (!type.isActive) const StatusPill(label: 'Hidden', tone: StatusTone.neutral),
            ],
          ),
          if (type.components != null) Text(type.components!, style: AppText.bodyMd.copyWith(color: AppColors.onSurfaceVariant)),
          Gap.lg,
          Container(
            padding: const EdgeInsets.all(AppSpace.lg),
            decoration: BoxDecoration(color: AppColors.primaryContainer, borderRadius: AppRadius.card),
            child: Row(
              children: [
                Expanded(
                  child: Text('STANDARD WORKLOAD', style: AppText.overline.copyWith(color: AppColors.onPrimaryContainer)),
                ),
                Text('${Fmt.hours(_total)} h', style: AppText.displayLgMobile.copyWith(color: AppColors.onPrimary)),
              ],
            ),
          ),
          Gap.lg,
          AppCard(
            padding: const EdgeInsets.all(AppSpace.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Kicker(
                  'Production routing',
                  trailing: Text('Hours per stage', style: AppText.labelMd.copyWith(color: AppColors.onSurfaceVariant)),
                ),
                Gap.sm,
                for (final (i, r) in _rows.indexed) ...[
                  _EditorRow(
                    row: r,
                    bad: _bad.contains(i),
                    onChanged: () => setState(() {}),
                    onUp: i == 0 ? null : () => _move(i, -1),
                    onDown: i == _rows.length - 1 ? null : () => _move(i, 1),
                    onRemove: _rows.length == 1 ? null : () => setState(() => _rows.removeAt(i).dispose()),
                  ),
                  Gap.sm,
                ],
                Align(
                  alignment: Alignment.centerLeft,
                  child: AppButton(label: 'Add stage', icon: Symbols.add, variant: AppButtonVariant.text, size: AppButtonSize.small, onPressed: _addStage),
                ),
              ],
            ),
          ),
          Gap.lg,
          MenuGroup(
            children: [
              MenuRow(
                icon: type.isActive ? Symbols.visibility_off : Symbols.visibility,
                title: type.isActive ? 'Hide from new jobs' : 'Show for new jobs',
                subtitle: 'Existing jobs are not affected',
                onTap: _toggleActive,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _EditorRow extends StatelessWidget {
  const _EditorRow({required this.row, required this.bad, required this.onChanged, this.onUp, this.onDown, this.onRemove});

  final _Row row;
  final bool bad;
  final VoidCallback onChanged;
  final VoidCallback? onUp;
  final VoidCallback? onDown;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    InputDecoration deco({String? hint}) => InputDecoration(
      isDense: true,
      hintText: hint,
      filled: true,
      fillColor: AppColors.surfaceContainerLowest,
      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      border: OutlineInputBorder(
        borderRadius: AppRadius.small,
        borderSide: bad ? const BorderSide(color: AppColors.error) : BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: AppRadius.small,
        borderSide: bad ? const BorderSide(color: AppColors.error) : BorderSide.none,
      ),
    );

    return Container(
      padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.sm, AppSpace.xs, AppSpace.sm),
      decoration: BoxDecoration(color: AppColors.surfaceContainerLow, borderRadius: AppRadius.control),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(controller: row.name, style: AppText.bodyMd, decoration: deco(), textCapitalization: TextCapitalization.sentences),
              ),
              const SizedBox(width: 6),
              if (row.taskType.isMilestone)
                SizedBox(
                  width: 80,
                  child: Text(
                    'Milestone',
                    textAlign: TextAlign.center,
                    style: AppText.labelSm.copyWith(color: AppColors.outline),
                  ),
                )
              else ...[
                SizedBox(
                  width: 60,
                  child: TextField(
                    controller: row.hours,
                    onChanged: (_) => onChanged(),
                    textAlign: TextAlign.right,
                    style: AppText.titleSm.copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
                    decoration: deco(hint: '0.0'),
                  ),
                ),
                const SizedBox(width: 4),
                SizedBox(
                  width: 16,
                  child: Text('h', style: AppText.bodyMd.copyWith(color: AppColors.onSurfaceVariant)),
                ),
              ],
            ],
          ),
          Row(
            children: [
              Expanded(
                child: Text(row.taskType.name, style: AppText.labelSm.copyWith(color: AppColors.onSurfaceVariant)),
              ),
              _IconAction(icon: Symbols.arrow_upward, tooltip: 'Move up', onTap: onUp),
              _IconAction(icon: Symbols.arrow_downward, tooltip: 'Move down', onTap: onDown),
              _IconAction(icon: Symbols.close, tooltip: 'Remove stage', onTap: onRemove),
            ],
          ),
        ],
      ),
    );
  }
}

class _IconAction extends StatelessWidget {
  const _IconAction({required this.icon, required this.tooltip, required this.onTap});

  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: tooltip,
    onPressed: onTap,
    visualDensity: VisualDensity.compact,
    icon: Icon(icon, size: 18, color: onTap == null ? AppColors.outlineVariant : AppColors.onSurfaceVariant),
  );
}
