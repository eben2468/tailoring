import 'package:uuid/uuid.dart';

import '../../../core/local/local_store.dart';
import '../../../core/network/api_exception.dart';
import '../../sync/data/sync_engine.dart';

/// Timer and work-log writes (docs/API_REFERENCE.md §10). Online the server's clock is used; when a
/// call is queued offline it carries the device time (`occurred_at`), so a timer started in a
/// workshop without signal keeps its real start and stop times.
class TimerApi {
  const TimerApi(this._sync);

  final SyncEngine _sync;

  String get _now => DateTime.now().toUtc().toIso8601String();

  String _taskName(String taskId) => _sync.store.get(Tables.tasks, taskId)?['task_name'] as String? ?? 'stage';

  /// The signed-in user's running session id (from the local copy).
  String? get _runningId => _sync.presenter()?.activeTimer()?['id'] as String?;

  Future<void> start(String taskId) {
    final body = {'id': const Uuid().v7()};
    return _sync.perform(
      label: 'Start timer on ${_taskName(taskId)}',
      method: 'POST',
      path: '/tasks/$taskId/timer/start',
      body: body,
      queuedBody: {...body, 'occurred_at': _now},
    );
  }

  /// "Pause Work" or, with [complete], "Log & Finish". The session id makes a replay harmless.
  Future<void> stop({String? note, bool complete = false}) {
    final entry = _runningId ?? (throw const ConflictException('No timer is running.', code: 'NO_TIMER_RUNNING'));
    final taskId = _sync.store.get(Tables.workLogs, entry)?['job_task_id'] as String? ?? '';
    final body = {'entry_id': entry, 'note': ?_blank(note), if (complete) 'complete_task': true};
    return _sync.perform(
      label: '${complete ? 'Finish' : 'Pause'} ${_taskName(taskId)}',
      method: 'POST',
      path: '/timers/stop',
      body: body,
      queuedBody: {...body, 'occurred_at': _now},
    );
  }

  Future<void> switchTo(String taskId, {String? note}) {
    final body = {'task_id': taskId, 'id': const Uuid().v7(), 'note': ?_blank(note)};
    return _sync.perform(
      label: 'Switch timer to ${_taskName(taskId)}',
      method: 'POST',
      path: '/timers/switch',
      body: body,
      queuedBody: {...body, 'occurred_at': _now},
    );
  }

  /// "+15m Adjust": placed right before the running session.
  Future<void> adjust(String taskId, Duration duration, {String? note}) {
    final body = {'id': const Uuid().v7(), 'duration_seconds': duration.inSeconds, 'note': ?_blank(note)};
    return _sync.perform(
      label: '+${duration.inMinutes}m on ${_taskName(taskId)}',
      method: 'POST',
      path: '/tasks/$taskId/work-logs',
      body: body,
      queuedBody: {...body, 'occurred_at': _now},
    );
  }

  Future<void> addEntry(String taskId, {required DateTime start, required DateTime end, String? note}) => _sync.perform(
        label: 'Add work on ${_taskName(taskId)}',
        method: 'POST',
        path: '/tasks/$taskId/work-logs',
        body: {
          'id': const Uuid().v7(),
          'started_at': start.toUtc().toIso8601String(),
          'ended_at': end.toUtc().toIso8601String(),
          'note': _blank(note),
        },
      );

  Future<void> updateEntry(String entryId, int version, {DateTime? start, DateTime? end, String? note}) => _sync.perform(
        label: 'Correct a work entry',
        method: 'PATCH',
        path: '/work-logs/$entryId',
        body: {
          'version': version,
          if (start != null) 'started_at': start.toUtc().toIso8601String(),
          if (end != null) 'ended_at': end.toUtc().toIso8601String(),
          if (note != null) 'note': _blank(note),
        },
      );

  Future<void> voidEntry(String entryId, String reason) => _sync.perform(label: 'Void a work entry', method: 'POST', path: '/work-logs/$entryId/void', body: {'reason': reason});

  static String? _blank(String? value) => value == null || value.trim().isEmpty ? null : value.trim();
}
