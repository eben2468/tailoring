import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../app/section_scaffold.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../core/widgets/bottom_action_bar.dart';
import '../../../core/widgets/feedback.dart';
import '../../../core/widgets/gap.dart';
import '../../../core/widgets/state_views.dart';
import '../../../core/widgets/status_pill.dart';
import '../../jobs/application/job_providers.dart';
import '../../jobs/domain/job.dart';
import '../../jobs/presentation/job_sheets.dart';
import '../../sync/application/sync_providers.dart';
import '../application/timer_providers.dart';
import '../domain/timer.dart';
import 'timer_widgets.dart';

/// Work log of one stage: every timer session and manual entry; add, correct or void entries.
class WorkLogsScreen extends ConsumerWidget {
  const WorkLogsScreen({super.key, required this.jobId, required this.taskId});

  final String jobId;
  final String taskId;

  Future<void> _edit(BuildContext context, WidgetRef ref, JobTask task, {WorkLogEntry? entry}) async {
    final changed = await showModalBottomSheet<bool>(
      context: context,
      useRootNavigator: true, // above the bottom navigation and timer bar
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _EntrySheet(jobId: jobId, task: task, entry: entry),
    );
    if (changed == true) ref.invalidate(workLogsProvider(taskId));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final job = ref.watch(jobProvider(jobId)).value;
    final task = job?.tasks.where((t) => t.id == taskId).firstOrNull;
    final logs = ref.watch(workLogsProvider(taskId));
    final canAdd = task != null && job != null && !task.isMilestone && !job.status.isClosed && job.status != JobStatus.draft;

    return DetailScaffold(
      title: 'Work Log',
      bottomBar: canAdd
          ? BottomActionBar(
              child: AppButton(label: 'Add Work', icon: Symbols.more_time, expand: true, onPressed: () => _edit(context, ref, task)),
            )
          : null,
      body: RefreshIndicator(
        edgeOffset: MediaQuery.paddingOf(context).top + 64,
        onRefresh: () => ref.read(syncControllerProvider.notifier).syncNow(),
        child: ListView(
          padding: belowHeader(context, bottom: 24),
          children: [
            Text(task?.name ?? 'Work log', style: AppText.headlineLg),
            if (task != null && job != null)
              Text(
                '${job.displayNumber} · ${job.customerName} · ${Fmt.hours(task.actualSeconds)} of ${Fmt.hours(task.estimatedSeconds)} hrs logged',
                style: AppText.bodyMd.copyWith(color: AppColors.onSurfaceVariant),
              ),
            Gap.lg,
            switch (logs) {
              AsyncData(:final value) when value.isEmpty => const AppCard(
                padding: EdgeInsets.symmetric(vertical: AppSpace.xl),
                child: MessageView(icon: Symbols.timer_off, title: 'No work logged yet', message: 'Timer sessions and manual entries for this stage appear here.'),
              ),
              AsyncData(:final value) => Column(
                children: [
                  for (final entry in value) ...[
                    _EntryCard(
                      entry: entry,
                      onTap: entry.isVoided || task == null || (job?.status.isClosed ?? true) ? null : () => _edit(context, ref, task, entry: entry),
                    ),
                    Gap.sm,
                  ],
                ],
              ),
              AsyncError(:final error) => ErrorView(error: error, onRetry: () => ref.invalidate(bootstrapProvider)),
              _ => const Padding(padding: EdgeInsets.all(AppSpace.xl), child: LoadingView()),
            },
          ],
        ),
      ),
    );
  }
}

class _EntryCard extends StatelessWidget {
  const _EntryCard({required this.entry, required this.onTap});

  final WorkLogEntry entry;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final time = TimeOfDay.fromDateTime(entry.startedAt).format(context);
    final end = entry.endedAt == null ? 'now' : TimeOfDay.fromDateTime(entry.endedAt!).format(context);
    final faded = entry.isVoided ? AppColors.outline : AppColors.onSurface;

    return AppCard(
      onTap: onTap,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(color: entry.isRunning ? AppColors.tertiaryFixedDim : AppColors.surfaceContainer, borderRadius: AppRadius.control),
            child: Icon(entry.isTimer ? Symbols.timer : Symbols.edit_calendar, size: 20, color: entry.isRunning ? AppColors.tertiaryContainer : AppColors.onSurfaceVariant),
          ),
          Gap.md,
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${Fmt.shortDate(entry.startedAt)} · $time – $end',
                        style: AppText.titleSm.copyWith(color: faded, decoration: entry.isVoided ? TextDecoration.lineThrough : null),
                      ),
                    ),
                    entry.isRunning
                        ? Ticker(
                            builder: (_, now) => Text(
                              clockText(now.difference(entry.startedAt)),
                              style: AppText.titleSm.copyWith(color: AppColors.onTertiaryContainer, fontFeatures: const [FontFeature.tabularFigures()]),
                            ),
                          )
                        : Text(
                            '${Fmt.hours(entry.durationSeconds)} h',
                            style: AppText.titleSm.copyWith(color: faded, fontFeatures: const [FontFeature.tabularFigures()]),
                          ),
                  ],
                ),
                if (entry.note != null) Text(entry.note!, style: AppText.bodySm.copyWith(color: AppColors.onSurfaceVariant)),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    StatusPill(label: entry.isTimer ? 'Timer' : 'Manual', tone: StatusTone.neutral, showDot: false),
                    if (entry.isRunning) const StatusPill(label: 'Running', tone: StatusTone.success),
                    if (entry.needsReview && !entry.isVoided) const StatusPill(label: 'Check: very long session', tone: StatusTone.warning),
                    if (entry.isVoided) StatusPill(label: 'Voided: ${entry.voidReason ?? ''}', tone: StatusTone.danger, showDot: false),
                    if (entry.recordedBy != null) Text(entry.recordedBy!, style: AppText.bodySm.copyWith(color: AppColors.outline)),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Add a manual entry, or correct / void an existing one.
class _EntrySheet extends ConsumerStatefulWidget {
  const _EntrySheet({required this.jobId, required this.task, this.entry});

  final String jobId;
  final JobTask task;
  final WorkLogEntry? entry;

  @override
  ConsumerState<_EntrySheet> createState() => _EntrySheetState();
}

class _EntrySheetState extends ConsumerState<_EntrySheet> {
  late DateTime _day = DateUtils.dateOnly(widget.entry?.startedAt ?? DateTime.now());
  late TimeOfDay _start = TimeOfDay.fromDateTime(widget.entry?.startedAt ?? DateTime.now().subtract(const Duration(hours: 1)));
  late TimeOfDay? _end = widget.entry == null ? TimeOfDay.now() : (widget.entry!.endedAt == null ? null : TimeOfDay.fromDateTime(widget.entry!.endedAt!));
  late final _note = TextEditingController(text: widget.entry?.note);
  String? _error;
  bool _busy = false;

  bool get _running => widget.entry?.isRunning ?? false;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  DateTime _at(TimeOfDay t) => DateTime(_day.year, _day.month, _day.day, t.hour, t.minute);

  Future<void> _run(Future<void> Function() call, String success) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await call();
      if (mounted) {
        showAppSnack(context, success);
        Navigator.of(context).pop(true);
      }
    } on ValidationException catch (e) {
      if (mounted) setState(() => _error = e.fieldErrors.values.firstOrNull?.firstOrNull ?? e.message);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    final api = ref.read(timerApiProvider);
    final entry = widget.entry;
    if (_running) {
      await _run(() => api.updateEntry(entry!.id, entry.version, note: _note.text), 'Note saved.');
      return;
    }
    final start = _at(_start);
    var end = _at(_end!);
    if (!end.isAfter(start)) end = end.add(const Duration(days: 1)); // crosses midnight
    if (entry == null) {
      await _run(() => api.addEntry(widget.task.id, start: start, end: end, note: _note.text), 'Work added to ${widget.task.name}.');
    } else {
      await _run(() => api.updateEntry(entry.id, entry.version, start: start, end: end, note: _note.text), 'Entry corrected.');
    }
  }

  Future<void> _void() async {
    final reason = await askText(context, title: 'Void this entry?', label: 'Reason', hint: 'e.g. Logged on the wrong job', confirmLabel: 'Void entry', destructive: true);
    if (reason == null) return;
    await _run(() => ref.read(timerApiProvider).voidEntry(widget.entry!.id, reason), 'Entry voided.');
  }

  @override
  Widget build(BuildContext context) {
    Widget tile(String caption, String value, VoidCallback? onTap) => Expanded(
      child: Material(
        color: AppColors.surfaceContainerLow,
        borderRadius: AppRadius.control,
        child: InkWell(
          borderRadius: AppRadius.control,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(AppSpace.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(caption, style: AppText.labelSm.copyWith(color: AppColors.secondary)),
                const SizedBox(height: 4),
                Text(value, style: AppText.titleSm.copyWith(color: onTap == null ? AppColors.outline : AppColors.onSurface)),
              ],
            ),
          ),
        ),
      ),
    );

    final start = _at(_start);
    var end = _end == null ? null : _at(_end!);
    if (end != null && !end.isAfter(start)) end = end.add(const Duration(days: 1));

    return Padding(
      padding: EdgeInsets.fromLTRB(AppSpace.margin, 0, AppSpace.margin, AppSpace.lg + MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(widget.entry == null ? 'Add work' : (_running ? 'Running session' : 'Correct entry'), style: AppText.headlineMd),
          Text(widget.task.name, style: AppText.bodyMd.copyWith(color: AppColors.onSurfaceVariant)),
          Gap.lg,
          Row(
            children: [
              tile(
                'DAY',
                Fmt.date(_day),
                _running
                    ? null
                    : () async {
                        final picked = await showDatePicker(context: context, initialDate: _day, firstDate: DateTime.now().subtract(const Duration(days: 365)), lastDate: DateTime.now());
                        if (picked != null) setState(() => _day = picked);
                      },
              ),
            ],
          ),
          Gap.sm,
          Row(
            children: [
              tile(
                'FROM',
                _start.format(context),
                _running
                    ? null
                    : () async {
                        final picked = await showTimePicker(context: context, initialTime: _start);
                        if (picked != null) setState(() => _start = picked);
                      },
              ),
              Gap.sm,
              tile(
                'TO',
                _end?.format(context) ?? 'Running',
                _running
                    ? null
                    : () async {
                        final picked = await showTimePicker(context: context, initialTime: _end ?? TimeOfDay.now());
                        if (picked != null) setState(() => _end = picked);
                      },
              ),
            ],
          ),
          if (end != null) ...[
            Gap.sm,
            Text(
              '${Fmt.hours(end.difference(start).inSeconds)} h',
              style: AppText.labelMd.copyWith(color: AppColors.onSurfaceVariant),
              textAlign: TextAlign.right,
            ),
          ],
          Gap.md,
          AppTextField(label: 'Note', controller: _note, maxLines: 3, minLines: 1, maxLength: 500, textCapitalization: TextCapitalization.sentences),
          if (_error != null) ...[Gap.sm, Text(_error!, style: AppText.bodySm.copyWith(color: AppColors.error))],
          Gap.lg,
          AppButton(label: widget.entry == null ? 'Add work' : 'Save', expand: true, loading: _busy, onPressed: _save),
          if (widget.entry != null) ...[
            Gap.sm,
            AppButton(label: _running ? 'Discard session' : 'Void entry', icon: Symbols.block, variant: AppButtonVariant.danger, expand: true, onPressed: _busy ? null : _void),
          ],
        ],
      ),
    );
  }
}
