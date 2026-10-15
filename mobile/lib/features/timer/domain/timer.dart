
/// One labour-ledger entry (timer session or manual entry).
class WorkLogEntry {
  const WorkLogEntry({
    required this.id,
    required this.taskId,
    required this.isTimer,
    required this.startedAt,
    required this.durationSeconds,
    required this.isRunning,
    required this.version,
    this.endedAt,
    this.note,
    this.needsReview = false,
    this.isVoided = false,
    this.voidReason,
    this.recordedBy,
  });

  factory WorkLogEntry.fromJson(Map<String, dynamic> json) => WorkLogEntry(
        id: json['id'] as String,
        taskId: json['task_id'] as String,
        isTimer: json['entry_type'] == 'timer',
        startedAt: DateTime.parse(json['started_at'] as String).toLocal(),
        endedAt: DateTime.tryParse(json['ended_at'] as String? ?? '')?.toLocal(),
        durationSeconds: (json['duration_seconds'] as num?)?.toInt() ?? 0,
        isRunning: json['is_running'] as bool? ?? false,
        note: json['note'] as String?,
        needsReview: json['needs_review'] as bool? ?? false,
        isVoided: json['is_voided'] as bool? ?? false,
        voidReason: json['void_reason'] as String?,
        recordedBy: json['recorded_by'] as String?,
        version: (json['version'] as num).toInt(),
      );

  final String id;
  final String taskId;
  final bool isTimer;
  final DateTime startedAt;
  final DateTime? endedAt;
  final int durationSeconds;
  final bool isRunning;
  final String? note;
  final bool needsReview;
  final bool isVoided;
  final String? voidReason;
  final String? recordedBy;
  final int version;
}

/// The running timer with what it is for. Elapsed time uses the server clock: [clockOffset] is
/// server time minus device time when the response arrived, so a wrong phone clock does not matter.
class ActiveTimer {
  const ActiveTimer({
    required this.entry,
    required this.taskId,
    required this.taskName,
    required this.typeName,
    required this.jobId,
    required this.jobTitle,
    required this.customerName,
    required this.clockOffset,
    this.jobNumber,
  });

  factory ActiveTimer.fromJson(Map<String, dynamic> json, Duration clockOffset) {
    final task = json['task'] as Map<String, dynamic>;
    return ActiveTimer(
      entry: WorkLogEntry.fromJson(json),
      taskId: task['id'] as String,
      taskName: task['name'] as String,
      typeName: task['type_name'] as String? ?? task['name'] as String,
      jobId: task['job_id'] as String,
      jobNumber: task['job_number'] as String?,
      jobTitle: task['job_title'] as String,
      customerName: task['customer_name'] as String,
      clockOffset: clockOffset,
    );
  }

  final WorkLogEntry entry;
  final String taskId;
  final String taskName;
  final String typeName;
  final String jobId;
  final String? jobNumber;
  final String jobTitle;
  final String customerName;
  final Duration clockOffset;

  /// Elapsed time of this session at [now] (device time).
  Duration elapsed([DateTime? now]) {
    final serverNow = (now ?? DateTime.now()).add(clockOffset);
    final d = serverNow.difference(entry.startedAt);
    return d.isNegative ? Duration.zero : d;
  }
}

