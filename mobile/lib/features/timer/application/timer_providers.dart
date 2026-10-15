import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../sync/application/sync_providers.dart';
import '../data/timer_api.dart';
import '../domain/timer.dart';

final timerApiProvider = Provider<TimerApi>((ref) => TimerApi(ref.watch(syncEngineProvider)));

/// The signed-in user's running timer, app-wide (timer bar, job cards, timer screen), from the local
/// copy — so it survives the app being killed and works without a connection.
final activeTimerProvider = Provider<AsyncValue<ActiveTimer?>>((ref) {
  final offset = ref.watch(syncEngineProvider).clockOffset;
  return fromStore(ref, (p) {
    final json = p.activeTimer();
    return json == null ? null : ActiveTimer.fromJson(json, offset);
  });
});

/// Timer actions (the active timer and job sheets update from the local copy).
final timerActionsProvider = Provider<TimerActions>((ref) => TimerActions(ref));

class TimerActions {
  const TimerActions(this._ref);

  final Ref _ref;

  TimerApi get _api => _ref.read(timerApiProvider);

  Future<void> start(String taskId) => _api.start(taskId);

  /// "Pause Work" or, with [complete], "Log & Finish".
  Future<void> stop({String? note, bool complete = false}) => _api.stop(note: note, complete: complete);

  Future<void> switchTo(String taskId, {String? note}) => _api.switchTo(taskId, note: note);

  /// "+15m Adjust" on the running stage (the timer keeps running).
  Future<void> adjust(Duration duration) {
    final timer = _ref.read(activeTimerProvider).value ?? (throw StateError('No timer is running.'));
    return _api.adjust(timer.taskId, duration);
  }
}

/// Every entry of a stage (incl. voided), newest first.
final workLogsProvider = Provider.family<AsyncValue<List<WorkLogEntry>>, String>(
  (ref, taskId) => fromStore(ref, (p) => p.workLogs(taskId).map((l) => WorkLogEntry.fromJson(p.workLog(l))).toList()),
);
