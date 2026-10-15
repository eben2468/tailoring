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
import '../../../core/widgets/hero_panel.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/feedback.dart';
import '../../../core/widgets/gap.dart';
import '../../../core/widgets/header_icon_button.dart';
import '../../../core/widgets/menu_row.dart';
import '../../../core/widgets/state_views.dart';
import '../../../core/widgets/status_pill.dart';
import '../../calendar/application/calendar_providers.dart';
import '../../jobs/application/job_providers.dart';
import '../../jobs/domain/job.dart';
import '../../jobs/presentation/job_sheets.dart';
import '../../sync/application/sync_providers.dart';
import '../application/timer_providers.dart';
import '../domain/timer.dart';
import 'timer_widgets.dart';

/// Work timer for one stage — Stitch "Work Timer / Time Tracker": live session, task budget,
/// Pause / Log & Finish, +15m adjust, switch task, quick note.
class TimerScreen extends ConsumerStatefulWidget {
  const TimerScreen({super.key, required this.jobId, required this.taskId});

  final String jobId;
  final String taskId;

  @override
  ConsumerState<TimerScreen> createState() => _TimerScreenState();
}

class _TimerScreenState extends ConsumerState<TimerScreen> {
  final _note = TextEditingController();
  bool _busy = false;

  TimerActions get _timer => ref.read(timerActionsProvider);

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<bool> _act(Future<Object?> Function() action, {String? success}) async {
    if (_busy) return false;
    setState(() => _busy = true);
    try {
      await action();
      if (mounted && success != null) showAppSnack(context, success);
      return true;
    } on ApiException catch (e) {
      if (mounted) showAppSnack(context, e.message, isError: true);
      return false;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pause() async {
    if (await _act(() => _timer.stop(note: _note.text), success: 'Paused. Work logged.')) _note.clear();
  }

  Future<void> _finish(JobTask task) async {
    final done = await _act(() => _timer.stop(note: _note.text, complete: true), success: '${task.name} completed. Work logged.');
    if (done && mounted) context.pop();
  }

  Future<void> _start(JobTask task) async {
    final running = ref.read(activeTimerProvider).value;
    if (running != null && running.taskId != task.id) {
      await _act(() => _timer.switchTo(task.id, note: _note.text), success: 'Switched to ${task.name}.');
    } else {
      await _act(() => _timer.start(task.id));
    }
  }

  Future<void> _switch(Job job, JobTask current) async {
    final options = job.workTasks.where((t) => t.id != current.id && !t.status.isClosed).toList();
    if (options.isEmpty) {
      showAppSnack(context, 'There is no other open stage on this job.');
      return;
    }
    final picked = await showModalBottomSheet<JobTask>(
      context: context,
      useRootNavigator: true, // above the bottom navigation and timer bar
      useSafeArea: true,
      builder: (context) => Padding(
        padding: const EdgeInsets.fromLTRB(AppSpace.margin, 0, AppSpace.margin, AppSpace.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Switch to another stage', style: AppText.headlineMd),
            Gap.xs,
            Text('Time so far is logged on ${current.name}.', style: AppText.bodyMd.copyWith(color: AppColors.onSurfaceVariant)),
            Gap.md,
            MenuGroup(
              children: [
                for (final t in options)
                  MenuRow(
                    icon: Symbols.content_cut,
                    title: t.name,
                    subtitle: '${Fmt.hours(t.actualSeconds)} of ${Fmt.hours(t.estimatedSeconds)} hrs logged',
                    onTap: () => Navigator.of(context).pop(t),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
    if (picked == null || !mounted) return;
    final switched = await _act(() => _timer.switchTo(picked.id, note: _note.text), success: 'Switched to ${picked.name}.');
    if (switched && mounted) {
      _note.clear();
      context.pushReplacement(Routes.taskTimer(job.id, picked.id));
    }
  }

  Future<void> _more(String action, ActiveTimer? timer) async {
    switch (action) {
      case 'logs':
        await context.push(Routes.taskLogs(widget.jobId, widget.taskId));
      case 'discard':
        if (timer == null) return;
        final reason = await askText(context, title: 'Discard this session?', label: 'Reason', hint: 'e.g. Started by mistake', confirmLabel: 'Discard session', destructive: true);
        if (reason == null) return;
        await _act(() => ref.read(timerApiProvider).voidEntry(timer.entry.id, reason), success: 'Session discarded. It does not count towards the hours.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final jobAsync = ref.watch(jobProvider(widget.jobId));
    final timer = ref.watch(activeTimerProvider).value;
    final runningHere = timer != null && timer.taskId == widget.taskId;

    return DetailScaffold(
      title: 'Work Timer',
      actions: [
        PopupMenuButton<String>(
          tooltip: 'More',
          padding: EdgeInsets.zero,
          shape: RoundedRectangleBorder(borderRadius: AppRadius.card),
          onSelected: (a) => _more(a, runningHere ? timer : null),
          itemBuilder: (_) => [const PopupMenuItem(value: 'logs', child: Text('Work log for this stage')), if (runningHere) const PopupMenuItem(value: 'discard', child: Text('Discard this session'))],
          child: const HeaderIconButton(icon: Symbols.more_vert),
        ),
      ],
      body: switch (jobAsync) {
        AsyncData(value: final job) => switch (job.tasks.where((t) => t.id == widget.taskId).firstOrNull) {
          final task? => _body(job, task, timer, runningHere),
          null => const MessageView(icon: Symbols.search_off, title: 'Stage not found', message: 'It may have been removed on another device.'),
        },
        AsyncError(:final error) => ErrorView(error: error, onRetry: () => ref.invalidate(bootstrapProvider)),
        _ => const LoadingView(),
      },
    );
  }

  Widget _body(Job job, JobTask task, ActiveTimer? timer, bool runningHere) {
    final number = job.tasks.where((t) => t.status != TaskStatus.skipped).toList().indexOf(task) + 1;
    return ListView(
      padding: belowHeader(context, bottom: 32),
      children: [
        _SessionCard(job: job, task: task, number: number, running: runningHere),
        Gap.lg,
        Ticker(
          enabled: runningHere,
          builder: (_, now) => _ClockCard(task: task, timer: runningHere ? timer : null, now: now),
        ),
        Gap.lg,
        Ticker(
          enabled: runningHere,
          builder: (_, now) => _BudgetCard(task: task, session: runningHere ? timer!.elapsed(now) : Duration.zero),
        ),
        Gap.lg,
        ..._actions(job, task, timer, runningHere),
        if (!task.isMilestone && !task.status.isClosed && job.status.isInProduction) ...[
          Gap.lg,
          AppCard(
            padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.xs, AppSpace.md, AppSpace.xs),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: const BoxDecoration(color: AppColors.secondaryFixed, shape: BoxShape.circle),
                  child: const Icon(Symbols.edit_note, size: 22, color: AppColors.onSecondaryFixedVariant),
                ),
                Gap.md,
                Expanded(
                  child: TextField(
                    controller: _note,
                    maxLength: 500,
                    textCapitalization: TextCapitalization.sentences,
                    style: AppText.bodyMd,
                    decoration: InputDecoration(
                      hintText: 'Quick note: e.g. Left sleeve pitched 3mm',
                      hintStyle: AppText.bodyMd.copyWith(color: AppColors.outline),
                      filled: false,
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      counterText: '',
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: AppSpace.xs, left: AppSpace.xs),
            child: Text('Saved with the session when you pause, finish or switch.', style: AppText.bodySm.copyWith(color: AppColors.onSurfaceVariant)),
          ),
        ],
        const _NextUpCard(),
      ],
    );
  }

  List<Widget> _actions(Job job, JobTask task, ActiveTimer? timer, bool runningHere) {
    if (runningHere) {
      return [
        Row(
          children: [
            Expanded(
              child: AppButton(label: 'Pause Work', icon: Symbols.pause_circle, variant: AppButtonVariant.tonal, loading: _busy, onPressed: _pause),
            ),
            Gap.sm,
            Expanded(
              child: AppButton(label: 'Log & Finish', icon: Symbols.check_circle, onPressed: _busy ? null : () => _finish(task)),
            ),
          ],
        ),
        Gap.sm,
        Row(
          children: [
            Expanded(
              child: AppButton(
                label: '+15m Adjust',
                icon: Symbols.add_circle,
                variant: AppButtonVariant.outline,
                size: AppButtonSize.medium,
                onPressed: _busy ? null : () => _act(() => _timer.adjust(const Duration(minutes: 15)), success: '15 minutes added to ${task.name}.'),
              ),
            ),
            Gap.sm,
            Expanded(
              child: AppButton(label: 'Switch Task', icon: Symbols.swap_horiz, variant: AppButtonVariant.outline, size: AppButtonSize.medium, onPressed: _busy ? null : () => _switch(job, task)),
            ),
          ],
        ),
      ];
    }

    final String? blocked = switch (job.status) {
      _ when task.isMilestone => 'Milestones have no work to time.',
      JobStatus.draft => 'Queue this job for production before timing work.',
      JobStatus.readyForCollection => 'This job is ready for collection. Move it back to production to log more work.',
      JobStatus.completed || JobStatus.cancelled => 'This job is ${job.status.label.toLowerCase()}.',
      _ when task.status.isClosed => '${task.name} is ${task.status == TaskStatus.completed ? 'completed' : 'skipped'}. Reopen it on the job sheet to log more work.',
      _ => null,
    };
    if (blocked != null) {
      return [
        InsetTile(
          padding: const EdgeInsets.all(AppSpace.md),
          child: Text(blocked, style: AppText.bodyMd.copyWith(color: AppColors.onSurfaceVariant)),
        ),
        Gap.sm,
        AppButton(label: 'Work log', icon: Symbols.history, variant: AppButtonVariant.outline, expand: true, onPressed: () => context.push(Routes.taskLogs(job.id, task.id))),
      ];
    }

    return [
      if (timer != null) ...[
        InsetTile(
          padding: const EdgeInsets.all(AppSpace.md),
          child: Row(
            children: [
              const Icon(Symbols.timer, size: 20, color: AppColors.secondary),
              Gap.sm,
              Expanded(child: Text('The timer is running on ${timer.taskName} (${timer.customerName}).', style: AppText.bodySm)),
              AppButton(label: 'Open', variant: AppButtonVariant.text, size: AppButtonSize.small, onPressed: () => context.pushReplacement(Routes.taskTimer(timer.jobId, timer.taskId))),
            ],
          ),
        ),
        Gap.sm,
      ],
      AppButton(
        label: timer != null ? 'Switch Timer Here' : (task.actualSeconds > 0 ? 'Resume Work' : 'Start Work'),
        icon: Symbols.play_circle,
        expand: true,
        loading: _busy,
        onPressed: () => _start(task),
      ),
      Gap.sm,
      Row(
        children: [
          Expanded(
            child: AppButton(label: 'Work log', icon: Symbols.history, variant: AppButtonVariant.outline, size: AppButtonSize.medium, onPressed: () => context.push(Routes.taskLogs(job.id, task.id))),
          ),
          Gap.sm,
          Expanded(
            child: AppButton(
              label: 'Mark Complete',
              icon: Symbols.check_circle,
              variant: AppButtonVariant.outline,
              size: AppButtonSize.medium,
              onPressed: _busy
                  ? null
                  : () async {
                      final done = await _act(() => ref.read(jobProvider(job.id).notifier).setTaskStatus(task, TaskStatus.completed), success: '${task.name} completed.');
                      if (done && mounted) context.pop();
                    },
            ),
          ),
        ],
      ),
    ];
  }
}

class _SessionCard extends StatelessWidget {
  const _SessionCard({required this.job, required this.task, required this.number, required this.running});

  final Job job;
  final JobTask task;
  final int number;
  final bool running;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.all(AppSpace.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              if (running)
                const StatusPill(label: 'ACTIVE SESSION', tone: StatusTone.success)
              else
                StatusPill(label: task.status.isClosed ? task.status.label.toUpperCase() : (task.actualSeconds > 0 ? 'PAUSED' : 'NOT STARTED'), tone: StatusTone.neutral),
              const Spacer(),
              Text('JOB ${job.displayNumber}', style: AppText.labelMd.copyWith(color: AppColors.onSurfaceVariant)),
            ],
          ),
          Gap.md,
          Text(job.customerName, style: AppText.headlineMd),
          Text(
            [job.title, ?job.fabricNote].join(' — '),
            style: AppText.bodyMd.copyWith(color: AppColors.onSurfaceVariant),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          Gap.md,
          Material(
            color: AppColors.surfaceContainerLow,
            borderRadius: AppRadius.control,
            child: InkWell(
              borderRadius: AppRadius.control,
              onTap: () => context.push(Routes.job(job.id)),
              child: Padding(
                padding: const EdgeInsets.all(AppSpace.md),
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: const BoxDecoration(color: AppColors.secondary, shape: BoxShape.circle),
                      child: const Icon(Symbols.straighten, size: 20, color: AppColors.onSecondary),
                    ),
                    Gap.md,
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('STAGE $number • ${task.taskType.name.toUpperCase()}', style: AppText.labelMd.copyWith(color: AppColors.secondary)),
                          Text(task.name, style: AppText.titleSm, maxLines: 1, overflow: TextOverflow.ellipsis),
                        ],
                      ),
                    ),
                    const Icon(Symbols.info, size: 22, color: AppColors.onSurfaceVariant),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Dark live-clock card.
class _ClockCard extends StatelessWidget {
  const _ClockCard({required this.task, required this.timer, required this.now});

  final JobTask task;
  final ActiveTimer? timer;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final elapsed = timer?.elapsed(now) ?? Duration.zero;
    final parts = clockText(elapsed).split(':');
    final logged = task.actualSeconds + elapsed.inSeconds;
    final digit = AppText.displayLg.copyWith(fontSize: 52, height: 1.1, color: timer == null ? AppColors.onPrimaryContainer : AppColors.onPrimary, fontFeatures: const [FontFeature.tabularFigures()]);
    Widget caption(String text) => SizedBox(
      width: 92,
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: AppText.overline.copyWith(color: AppColors.onPrimaryContainer),
      ),
    );

    return HeroPanel(
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.lg, vertical: AppSpace.xl),
      watermark: Symbols.timer,
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Symbols.schedule, size: 16, color: timer == null ? AppColors.onPrimaryContainer : AppColors.tertiaryFixedDim),
              const SizedBox(width: 6),
              Text(
                timer == null ? 'TIMER NOT RUNNING' : 'STARTED ${TimeOfDay.fromDateTime(timer!.entry.startedAt).format(context).toUpperCase()}',
                style: AppText.labelMd.copyWith(color: AppColors.inverseOnSurface, letterSpacing: 0.8),
              ),
            ],
          ),
          Gap.lg,
          FittedBox(
            child: Row(
              children: [
                SizedBox(
                  width: 92,
                  child: Text(parts[0], textAlign: TextAlign.center, style: digit),
                ),
                Text(':', style: digit),
                SizedBox(
                  width: 92,
                  child: Text(parts[1], textAlign: TextAlign.center, style: digit),
                ),
                Text(':', style: digit),
                SizedBox(
                  width: 92,
                  child: Text(parts[2], textAlign: TextAlign.center, style: digit),
                ),
              ],
            ),
          ),
          Gap.xs,
          FittedBox(child: Row(children: [caption('HOURS'), const SizedBox(width: 14), caption('MINS'), const SizedBox(width: 14), caption('SECS')])),
          Gap.lg,
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(color: AppColors.inverseSurface, borderRadius: AppRadius.full),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(color: task.estimatedSeconds > 0 && logged > task.estimatedSeconds ? AppColors.warningAccent : AppColors.tertiaryFixedDim, shape: BoxShape.circle),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    task.estimatedSeconds == 0 ? 'No estimate set for this stage' : '${(logged / task.estimatedSeconds * 100).round()}% of the ${Fmt.hours(task.estimatedSeconds)} h estimate used',
                    style: AppText.labelMd.copyWith(color: AppColors.inverseOnSurface),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// "Task Metrics & Budget": prior work + this session against the estimate.
class _BudgetCard extends StatelessWidget {
  const _BudgetCard({required this.task, required this.session});

  final JobTask task;
  final Duration session;

  @override
  Widget build(BuildContext context) {
    final est = task.estimatedSeconds;
    final prior = task.actualSeconds;
    final logged = prior + session.inSeconds;
    final remaining = (est - logged).clamp(0, est);
    final over = logged - est;

    Widget tile(String caption, String value, {Color? color}) => Expanded(
      child: InsetTile(
        padding: const EdgeInsets.all(AppSpace.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(caption, style: AppText.overline.copyWith(fontSize: 10), maxLines: 1),
            const SizedBox(height: 2),
            Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: value,
                    style: AppText.metricNum.copyWith(color: color),
                  ),
                  TextSpan(
                    text: ' hrs',
                    style: AppText.bodySm.copyWith(color: AppColors.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );

    return AppCard(
      padding: const EdgeInsets.all(AppSpace.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Symbols.schedule, size: 20, color: AppColors.onSurface),
              Gap.sm,
              Expanded(child: Text('Task Metrics & Budget', style: AppText.titleSm)),
              StatusPill(label: est == 0 ? 'No estimate' : '${Fmt.hours(est)} hrs est.', tone: StatusTone.info, showDot: false),
            ],
          ),
          Gap.md,
          ClipRRect(
            borderRadius: AppRadius.full,
            child: SizedBox(
              height: 10,
              child: LayoutBuilder(
                builder: (context, c) {
                  final total = est > 0 ? est.toDouble() : (logged == 0 ? 1.0 : logged.toDouble());
                  final scale = logged > total ? logged.toDouble() : total;
                  return Stack(
                    children: [
                      const Positioned.fill(child: ColoredBox(color: AppColors.surfaceContainer)),
                      Positioned(
                        left: 0,
                        top: 0,
                        bottom: 0,
                        width: c.maxWidth * (logged / scale),
                        child: const ColoredBox(color: AppColors.secondary),
                      ),
                      Positioned(
                        left: 0,
                        top: 0,
                        bottom: 0,
                        width: c.maxWidth * (prior / scale),
                        child: const ColoredBox(color: AppColors.outline),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
          Gap.sm,
          Row(
            children: [
              Expanded(
                child: Text(
                  est == 0 ? 'Logged: ${Fmt.hours(logged)}h' : 'Logged: ${Fmt.hours(logged)}h (${(logged / est * 100).round()}%)',
                  style: AppText.labelMd.copyWith(color: AppColors.onSurfaceVariant),
                ),
              ),
              if (est > 0) Text(over > 0 ? 'Over by ${_short(over)}' : '${_short(remaining)} left', style: AppText.labelMd.copyWith(color: over > 0 ? AppColors.error : AppColors.onTertiaryContainer)),
            ],
          ),
          Gap.md,
          Row(
            children: [
              tile('PRIOR WORK', Fmt.hours(prior)),
              Gap.sm,
              tile('THIS SESSION', Fmt.hours(session.inSeconds), color: AppColors.secondary),
              Gap.sm,
              tile('REMAINING', Fmt.hours(remaining)),
            ],
          ),
        ],
      ),
    );
  }

  static String _short(int seconds) {
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    return h > 0 ? '${h}h ${m}m' : '${m}m';
  }
}

/// "Next up in the salon": the next open appointment (Stitch timer screen).
class _NextUpCard extends ConsumerWidget {
  const _NextUpCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final next = ref.watch(nextAppointmentProvider);
    if (next == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: AppSpace.lg),
      child: Material(
        color: AppColors.surfaceContainerLow,
        borderRadius: AppRadius.card,
        child: InkWell(
          borderRadius: AppRadius.card,
          onTap: () => context.push(Routes.appointment(next.id)),
          child: Padding(
            padding: const EdgeInsets.all(AppSpace.lg),
            child: Row(children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(color: AppColors.surfaceContainerLowest, borderRadius: AppRadius.control),
                child: const Icon(Symbols.calendar_month, size: 22, color: AppColors.secondary),
              ),
              Gap.md,
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('NEXT UP IN THE SALON', style: AppText.overline),
                  Text(
                    '${next.type.label}${next.customerName == null ? '' : ' with ${next.customerName}'} at ${TimeOfDay.fromDateTime(next.startsAt).format(context)}',
                    style: AppText.titleSm,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ]),
              ),
              Gap.sm,
              Ticker(
                builder: (_, now) {
                  final d = next.startsAt.difference(now);
                  final label = d.isNegative
                      ? 'now'
                      : d.inDays > 0
                          ? 'in ${d.inDays}d'
                          : 'in ${d.inHours > 0 ? '${d.inHours}h ' : ''}${d.inMinutes.remainder(60)}m';
                  return StatusPill(label: label, tone: StatusTone.info, showDot: false);
                },
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
