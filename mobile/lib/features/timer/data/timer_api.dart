import 'package:uuid/uuid.dart';

import '../../../core/network/api_client.dart';
import '../domain/timer.dart';

/// /timers and /work-logs (docs/API_REFERENCE.md §10). Client-generated ids make retries harmless.
class TimerApi {
  const TimerApi(this._client);

  final ApiClient _client;

  Future<TimerResult> active() => _timer(_client.get('/timers/active'));

  Future<TimerResult> start(String taskId, {String? note}) => _timer(_client.post('/tasks/$taskId/timer/start', body: {'id': const Uuid().v7(), 'note': ?note}));

  /// "Pause Work" ([complete] false) or "Log & Finish" ([complete] true).
  Future<TimerResult> stop({String? note, bool complete = false}) =>
      _timer(_client.post('/timers/stop', body: {'note': ?_blank(note), if (complete) 'complete_task': true}));

  Future<TimerResult> switchTo(String taskId, {String? note}) =>
      _timer(_client.post('/timers/switch', body: {'task_id': taskId, 'id': const Uuid().v7(), 'note': ?_blank(note)}));

  Future<List<WorkLogEntry>> logs(String taskId) async =>
      (await _client.get('/tasks/$taskId/work-logs') as List<dynamic>).cast<Map<String, dynamic>>().map(WorkLogEntry.fromJson).toList();

  /// "+15m Adjust": placed right before the running session by the server.
  Future<WorkLogResult> adjust(String taskId, Duration duration, {String? note}) =>
      _log(_client.post('/tasks/$taskId/work-logs', body: {'id': const Uuid().v7(), 'duration_seconds': duration.inSeconds, 'note': ?_blank(note)}));

  Future<WorkLogResult> addEntry(String taskId, {required DateTime start, required DateTime end, String? note}) => _log(_client.post('/tasks/$taskId/work-logs', body: {
        'id': const Uuid().v7(),
        'started_at': start.toUtc().toIso8601String(),
        'ended_at': end.toUtc().toIso8601String(),
        'note': _blank(note),
      }));

  Future<WorkLogResult> updateEntry(WorkLogEntry entry, {DateTime? start, DateTime? end, String? note}) => _log(_client.patch('/work-logs/${entry.id}', body: {
        'version': entry.version,
        if (start != null) 'started_at': start.toUtc().toIso8601String(),
        if (end != null) 'ended_at': end.toUtc().toIso8601String(),
        if (note != null) 'note': _blank(note),
      }));

  Future<WorkLogResult> voidEntry(String entryId, String reason) => _log(_client.post('/work-logs/$entryId/void', body: {'reason': reason}));

  Future<TimerResult> _timer(Future<dynamic> request) async => TimerResult.fromJson(await request as Map<String, dynamic>, receivedAt: DateTime.now());

  Future<WorkLogResult> _log(Future<dynamic> request) async => WorkLogResult.fromJson(await request as Map<String, dynamic>);

  static String? _blank(String? value) => value == null || value.trim().isEmpty ? null : value.trim();
}
