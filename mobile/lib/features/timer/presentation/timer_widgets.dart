import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../app/routes.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/widgets/feedback.dart';
import '../../../core/widgets/gap.dart';
import '../application/timer_providers.dart';
import '../domain/timer.dart';

/// "02:35:44"
String clockText(Duration d) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(d.inHours)}:${two(d.inMinutes.remainder(60))}:${two(d.inSeconds.remainder(60))}';
}

/// Rebuilds every second while [enabled] (live timer displays).
class Ticker extends StatefulWidget {
  const Ticker({super.key, required this.builder, this.enabled = true});

  final Widget Function(BuildContext context, DateTime now) builder;
  final bool enabled;

  @override
  State<Ticker> createState() => _TickerState();
}

class _TickerState extends State<Ticker> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(Ticker oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  void _sync() {
    if (widget.enabled && _timer == null) {
      _timer = Timer.periodic(const Duration(seconds: 1), (_) => setState(() {}));
    } else if (!widget.enabled) {
      _timer?.cancel();
      _timer = null;
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, DateTime.now());
}

/// Starts the timer on a stage and opens the timer screen. If another stage is running, offers to switch.
Future<void> startTimerFlow(BuildContext context, WidgetRef ref, {required String jobId, required String taskId, required String taskName}) async {
  final controller = ref.read(activeTimerProvider.notifier);
  try {
    await controller.start(taskId);
  } on ConflictException catch (e) {
    if (e.code != 'TIMER_ALREADY_RUNNING' || !context.mounted) {
      if (context.mounted) showAppSnack(context, e.message, isError: true);
      return;
    }
    final running = ref.read(activeTimerProvider).value;
    final ok = await confirmAction(
      context,
      title: 'Switch the timer?',
      message: 'The timer is running on ${running?.taskName ?? 'another stage'}. Its time is logged and the timer moves to $taskName.',
      confirmLabel: 'Switch to $taskName',
    );
    if (!ok || !context.mounted) return;
    try {
      await controller.switchTo(taskId);
    } on ApiException catch (e) {
      if (context.mounted) showAppSnack(context, e.message, isError: true);
      return;
    }
  } on ApiException catch (e) {
    if (context.mounted) showAppSnack(context, e.message, isError: true);
    return;
  }
  if (context.mounted) await context.push(Routes.taskTimer(jobId, taskId));
}

/// "Timer running" strip above the bottom navigation; opens the timer screen.
class TimerBar extends ConsumerWidget {
  const TimerBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final timer = ref.watch(activeTimerProvider).value;
    if (timer == null) return const SizedBox.shrink();
    return _TimerStrip(timer: timer);
  }
}

class _TimerStrip extends StatelessWidget {
  const _TimerStrip({required this.timer});

  final ActiveTimer timer;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.primaryContainer,
      child: InkWell(
        onTap: () => context.push(Routes.taskTimer(timer.jobId, timer.taskId)),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpace.margin, vertical: AppSpace.sm + 2),
          child: Row(children: [
            Container(width: 8, height: 8, decoration: const BoxDecoration(color: AppColors.tertiaryFixedDim, shape: BoxShape.circle)),
            Gap.sm,
            Ticker(
              builder: (_, now) => Text(
                clockText(timer.elapsed(now)),
                style: AppText.titleSm.copyWith(color: AppColors.onPrimary, fontFeatures: const [FontFeature.tabularFigures()]),
              ),
            ),
            Gap.md,
            Expanded(
              child: Text(
                '${timer.taskName} · ${timer.jobNumber == null ? timer.customerName : '#${timer.jobNumber} ${timer.customerName}'}',
                style: AppText.bodySm.copyWith(color: AppColors.inverseOnSurface),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const Icon(Symbols.chevron_right, size: 20, color: AppColors.inverseOnSurface),
          ]),
        ),
      ),
    );
  }
}
