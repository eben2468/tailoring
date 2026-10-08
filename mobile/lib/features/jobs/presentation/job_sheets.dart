import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../app/routes.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../core/widgets/feedback.dart';
import '../../../core/widgets/gap.dart';
import '../../../core/widgets/menu_row.dart';
import '../../../core/widgets/state_views.dart';
import '../../../core/widgets/status_pill.dart';
import '../application/job_providers.dart';
import '../data/jobs_api.dart';
import '../domain/job.dart';

/// Bottom sheet asking for one line of text. Returns the trimmed text, or null when cancelled.
Future<String?> askText(
  BuildContext context, {
  required String title,
  required String label,
  required String confirmLabel,
  String? hint,
  String? initial,
  int maxLength = 255,
  bool destructive = false,
}) {
  final controller = TextEditingController(text: initial);
  return showModalBottomSheet<String>(
    context: context,
    useRootNavigator: true, // above the bottom navigation and timer bar
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) {
      void submit() {
        final text = controller.text.trim();
        if (text.isNotEmpty) Navigator.of(context).pop(text);
      }

      return Padding(
        padding: EdgeInsets.fromLTRB(AppSpace.margin, 0, AppSpace.margin, AppSpace.lg + MediaQuery.viewInsetsOf(context).bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: AppText.headlineMd),
            Gap.lg,
            AppTextField(
              label: label,
              hint: hint,
              controller: controller,
              autofocus: true,
              maxLength: maxLength,
              textCapitalization: TextCapitalization.sentences,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => submit(),
            ),
            Gap.lg,
            AppButton(label: confirmLabel, expand: true, variant: destructive ? AppButtonVariant.danger : AppButtonVariant.primary, onPressed: submit),
          ],
        ),
      );
    },
  ).whenComplete(controller.dispose);
}

/// Manual progress prompt. Returns the percentage, NaN to return to calculated progress, or null if cancelled.
Future<double?> askProgress(BuildContext context, {required double current, required bool manual}) {
  var value = current.clamp(0, 100).roundToDouble();
  return showModalBottomSheet<double>(
    context: context,
    useRootNavigator: true, // above the bottom navigation and timer bar
    useSafeArea: true,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => Padding(
        padding: const EdgeInsets.fromLTRB(AppSpace.margin, 0, AppSpace.margin, AppSpace.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Set progress manually', style: AppText.headlineMd),
            Gap.sm,
            Text('Progress normally follows the hours logged. Set it by hand when hours do not tell the full story.', style: AppText.bodyMd.copyWith(color: AppColors.onSurfaceVariant)),
            Gap.lg,
            Center(
              child: Text('${value.round()}%', style: AppText.displayLg.copyWith(fontFeatures: const [FontFeature.tabularFigures()])),
            ),
            Slider(value: value, max: 100, divisions: 20, onChanged: (v) => setState(() => value = v)),
            Gap.sm,
            AppButton(label: 'Save ${value.round()}%', expand: true, onPressed: () => Navigator.of(context).pop(value)),
            if (manual) ...[Gap.sm, AppButton(label: 'Use calculated progress', expand: true, variant: AppButtonVariant.outline, onPressed: () => Navigator.of(context).pop(double.nan))],
          ],
        ),
      ),
    ),
  );
}

/// Edit one production stage: status, name, hours, notes, position; delete when no hours are logged.
Future<void> showTaskSheet(BuildContext context, {required String jobId, required String taskId}) => showModalBottomSheet<void>(
  context: context,
  useRootNavigator: true, // above the bottom navigation and timer bar
  isScrollControlled: true,
  useSafeArea: true,
  builder: (_) => _TaskSheet(jobId: jobId, taskId: taskId),
);

class _TaskSheet extends ConsumerStatefulWidget {
  const _TaskSheet({required this.jobId, required this.taskId});

  final String jobId;
  final String taskId;

  @override
  ConsumerState<_TaskSheet> createState() => _TaskSheetState();
}

class _TaskSheetState extends ConsumerState<_TaskSheet> {
  final _name = TextEditingController();
  final _hours = TextEditingController();
  final _notes = TextEditingController();
  String? _hoursError;
  String? _nameError;
  bool _busy = false;
  int? _loadedVersion;

  @override
  void dispose() {
    _name.dispose();
    _hours.dispose();
    _notes.dispose();
    super.dispose();
  }

  void _load(JobTask task) {
    if (_loadedVersion == task.version) return;
    _loadedVersion = task.version;
    _name.text = task.name;
    _hours.text = task.isMilestone ? '' : Fmt.hours(task.estimatedSeconds);
    _notes.text = task.notes ?? '';
  }

  Future<void> _run(Future<Job> Function(JobsApi api) call, {String? success, bool close = false}) async {
    setState(() => _busy = true);
    try {
      await ref.read(jobProvider(widget.jobId).notifier).run(call);
      if (!mounted) return;
      if (success != null) showAppSnack(context, success);
      if (close) Navigator.of(context).pop();
    } on ValidationException catch (e) {
      if (mounted) {
        setState(() {
          _nameError = e.forField('task_name');
          _hoursError = e.forField('estimated_seconds');
        });
        if (_nameError == null && _hoursError == null) showAppSnack(context, e.message, isError: true);
      }
    } on ApiException catch (e) {
      if (mounted) showAppSnack(context, e.message, isError: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save(JobTask task) async {
    final seconds = task.isMilestone ? null : Fmt.parseHours(_hours.text);
    setState(() {
      _nameError = _name.text.trim().isEmpty ? 'Enter a name.' : null;
      _hoursError = !task.isMilestone && seconds == null ? 'Enter hours, e.g. 2.5' : null;
    });
    if (_nameError != null || _hoursError != null) return;
    await _run(
      (api) => api.updateTask(task, name: _name.text.trim(), estimatedSeconds: seconds, notes: _notes.text),
      success: 'Stage saved.',
      close: true,
    );
  }

  Future<void> _move(Job job, JobTask task, int delta) async {
    final ids = job.tasks.map((t) => t.id).toList();
    final from = ids.indexOf(task.id);
    final to = from + delta;
    if (to < 0 || to >= ids.length) return;
    ids
      ..removeAt(from)
      ..insert(to, task.id);
    await _run((api) => api.reorderTasks(job.id, ids));
  }

  @override
  Widget build(BuildContext context) {
    final job = ref.watch(jobProvider(widget.jobId)).value;
    final task = job?.tasks.where((t) => t.id == widget.taskId).firstOrNull;
    if (job == null || task == null) return const SizedBox(height: 200, child: LoadingView());
    _load(task);

    final editable = !job.status.isClosed;
    final canWork = job.status.isInProduction && !task.isMilestone;
    final index = job.tasks.indexOf(task);

    final statusActions = <Widget>[
      if (canWork && task.status == TaskStatus.pending)
        AppButton(label: 'Start stage', icon: Symbols.play_arrow, variant: AppButtonVariant.tonal, loading: _busy, onPressed: () => _run((api) => api.setTaskStatus(task, TaskStatus.inProgress))),
      if (canWork && !task.status.isClosed)
        AppButton(
          label: 'Mark complete',
          icon: Symbols.check_circle,
          loading: _busy,
          onPressed: () => _run((api) => api.setTaskStatus(task, TaskStatus.completed), success: '${task.name} completed.', close: true),
        ),
      if (canWork && task.status.isClosed)
        AppButton(label: 'Reopen stage', icon: Symbols.undo, variant: AppButtonVariant.outline, loading: _busy, onPressed: () => _run((api) => api.setTaskStatus(task, TaskStatus.pending))),
    ];

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(AppSpace.margin, 0, AppSpace.margin, AppSpace.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(child: Text(task.name, style: AppText.headlineMd)),
                StatusPill(
                  label: task.isMilestone ? 'Milestone' : task.status.label,
                  tone: switch (task.status) {
                    TaskStatus.completed => StatusTone.success,
                    TaskStatus.inProgress => StatusTone.info,
                    _ => StatusTone.neutral,
                  },
                ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              task.isMilestone
                  ? 'Follows the job status: it is reached when the job is marked ready or collected.'
                  : '${task.taskType.name} · ${Fmt.hours(task.actualSeconds)} of ${Fmt.hours(task.estimatedSeconds)} hrs logged'
                        '${task.logCount > 0 ? ' · ${task.logCount} work log${task.logCount == 1 ? '' : 's'}' : ''}',
              style: AppText.bodySm.copyWith(color: AppColors.onSurfaceVariant),
            ),
            if (!task.isMilestone && !job.status.isInProduction && editable) ...[
              Gap.md,
              InsetTile(
                padding: const EdgeInsets.all(AppSpace.md),
                child: Text(
                  job.status == JobStatus.draft ? 'Queue this job for production to start work on its stages.' : 'Move the job back to production to change its stages.',
                  style: AppText.bodySm.copyWith(color: AppColors.onSurfaceVariant),
                ),
              ),
            ],
            if (statusActions.isNotEmpty) ...[
              Gap.lg,
              Row(
                children: [
                  for (final (i, action) in statusActions.indexed) ...[if (i > 0) Gap.sm, Expanded(child: action)],
                ],
              ),
              if (canWork && !task.status.isClosed)
                Align(
                  alignment: Alignment.centerRight,
                  child: AppButton(
                    label: 'Skip this stage',
                    variant: AppButtonVariant.text,
                    size: AppButtonSize.small,
                    onPressed: _busy ? null : () => _run((api) => api.setTaskStatus(task, TaskStatus.skipped), success: '${task.name} skipped.', close: true),
                  ),
                ),
            ],
            if (!task.isMilestone) ...[
              Gap.sm,
              Row(
                children: [
                  if (canWork && !task.status.isClosed) ...[
                    Expanded(
                      child: AppButton(
                        label: 'Timer',
                        icon: Symbols.timer,
                        variant: AppButtonVariant.outline,
                        size: AppButtonSize.medium,
                        onPressed: () {
                          Navigator.of(context).pop();
                          context.push(Routes.taskTimer(job.id, task.id));
                        },
                      ),
                    ),
                    Gap.sm,
                  ],
                  Expanded(
                    child: AppButton(
                      label: 'Work log${task.logCount > 0 ? ' (${task.logCount})' : ''}',
                      icon: Symbols.history,
                      variant: AppButtonVariant.outline,
                      size: AppButtonSize.medium,
                      onPressed: () {
                        Navigator.of(context).pop();
                        context.push(Routes.taskLogs(job.id, task.id));
                      },
                    ),
                  ),
                ],
              ),
            ],
            if (editable) ...[
              Gap.lg,
              AppTextField(label: 'Stage name', controller: _name, errorText: _nameError, maxLength: 120, textCapitalization: TextCapitalization.sentences),
              if (!task.isMilestone) ...[
                Gap.md,
                AppTextField(
                  label: 'Estimated hours',
                  controller: _hours,
                  errorText: _hoursError,
                  suffixText: 'h',
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
                ),
              ],
              Gap.md,
              AppTextField(label: 'Notes', controller: _notes, maxLines: 4, minLines: 2, textCapitalization: TextCapitalization.sentences),
              Gap.lg,
              AppButton(label: 'Save stage', expand: true, loading: _busy, onPressed: () => _save(task)),
              Gap.sm,
              Row(
                children: [
                  Expanded(
                    child: AppButton(
                      label: 'Move up',
                      icon: Symbols.arrow_upward,
                      variant: AppButtonVariant.outline,
                      size: AppButtonSize.medium,
                      onPressed: _busy || index == 0 ? null : () => _move(job, task, -1),
                    ),
                  ),
                  Gap.sm,
                  Expanded(
                    child: AppButton(
                      label: 'Move down',
                      icon: Symbols.arrow_downward,
                      variant: AppButtonVariant.outline,
                      size: AppButtonSize.medium,
                      onPressed: _busy || index == job.tasks.length - 1 ? null : () => _move(job, task, 1),
                    ),
                  ),
                ],
              ),
              if (task.logCount == 0) ...[
                Gap.sm,
                AppButton(
                  label: 'Remove stage',
                  icon: Symbols.delete,
                  variant: AppButtonVariant.danger,
                  size: AppButtonSize.medium,
                  expand: true,
                  onPressed: _busy
                      ? null
                      : () async {
                          final ok = await confirmAction(context, title: 'Remove ${task.name}?', message: 'The stage is removed from this job only.', confirmLabel: 'Remove stage', destructive: true);
                          if (ok) await _run((api) => api.deleteTask(task.id), success: 'Stage removed.', close: true);
                        },
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

/// Pick a production stage to add to a job, then open it to set its hours.
Future<void> showAddStageSheet(BuildContext context, {required String jobId}) async {
  final added = await showModalBottomSheet<String>(
    context: context,
    useRootNavigator: true, // above the bottom navigation and timer bar
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _AddStageSheet(jobId: jobId),
  );
  if (added != null && context.mounted) await showTaskSheet(context, jobId: jobId, taskId: added);
}

class _AddStageSheet extends ConsumerStatefulWidget {
  const _AddStageSheet({required this.jobId});

  final String jobId;

  @override
  ConsumerState<_AddStageSheet> createState() => _AddStageSheetState();
}

class _AddStageSheetState extends ConsumerState<_AddStageSheet> {
  bool _busy = false;

  Future<void> _add(TaskType type) async {
    setState(() => _busy = true);
    try {
      final before = ref.read(jobProvider(widget.jobId)).value?.tasks.map((t) => t.id).toSet() ?? {};
      final job = await ref.read(jobProvider(widget.jobId).notifier).run((api) => api.addTask(widget.jobId, taskTypeId: type.id));
      final added = job.tasks.where((t) => !before.contains(t.id)).firstOrNull;
      if (mounted) Navigator.of(context).pop(added?.id);
    } on ApiException catch (e) {
      if (mounted) showAppSnack(context, e.message, isError: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _newType() async {
    final name = await askText(context, title: 'New production stage', label: 'Stage name', hint: 'e.g. Embroidery', confirmLabel: 'Create stage', maxLength: 80);
    if (name == null || !mounted) return;
    try {
      final type = await ref.read(jobsApiProvider).createTaskType(name);
      ref.invalidate(taskTypesProvider);
      await _add(type);
    } on ApiException catch (e) {
      if (mounted) showAppSnack(context, e.message, isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final types = ref.watch(taskTypesProvider);
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpace.margin, 0, AppSpace.margin, AppSpace.lg),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Add a stage', style: AppText.headlineMd),
          Gap.md,
          Flexible(
            child: switch (types) {
              AsyncData(:final value) => ListView(
                shrinkWrap: true,
                children: [
                  MenuGroup(
                    children: [
                      for (final type in value.where((t) => !t.isMilestone))
                        MenuRow(icon: type.isFitting ? Symbols.accessibility_new : Symbols.content_cut, title: type.name, onTap: _busy ? null : () => _add(type)),
                      MenuRow(icon: Symbols.add, title: 'New stage type…', subtitle: 'Add a stage the list does not have', onTap: _busy ? null : _newType),
                    ],
                  ),
                ],
              ),
              AsyncError(:final error) => ErrorView(error: error, onRetry: () => ref.invalidate(taskTypesProvider)),
              _ => const SizedBox(height: 160, child: LoadingView()),
            },
          ),
        ],
      ),
    );
  }
}
