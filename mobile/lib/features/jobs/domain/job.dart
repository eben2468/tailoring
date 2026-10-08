/// Jobs, production stages and configuration (docs/API_REFERENCE.md §7–9).
/// Hours are integer seconds; hours and progress are calculated by the server and only displayed here.
library;

enum JobStatus {
  draft('Draft'),
  queued('Queued'),
  inProgress('In production'),
  onHold('On hold'),
  readyForCollection('Ready for collection'),
  completed('Collected'),
  cancelled('Cancelled');

  const JobStatus(this.label);

  final String label;

  String get api => switch (this) {
        inProgress => 'in_progress',
        onHold => 'on_hold',
        readyForCollection => 'ready_for_collection',
        _ => name,
      };

  static JobStatus parse(String value) => values.firstWhere((s) => s.api == value, orElse: () => queued);

  bool get isClosed => this == completed || this == cancelled;

  /// Stage status changes are allowed (queued, in production, on hold).
  bool get isInProduction => this == queued || this == inProgress || this == onHold;
}

enum JobPriority {
  normal('Normal'),
  high('High Priority'),
  urgent('Urgent Rush');

  const JobPriority(this.label);

  final String label;

  static JobPriority parse(String? value) => values.firstWhere((p) => p.name == value, orElse: () => normal);
}

enum TaskStatus {
  pending('Pending'),
  inProgress('Active'),
  completed('Done'),
  skipped('Skipped');

  const TaskStatus(this.label);

  final String label;

  String get api => this == inProgress ? 'in_progress' : name;

  static TaskStatus parse(String value) => values.firstWhere((s) => s.api == value, orElse: () => pending);

  bool get isClosed => this == completed || this == skipped;
}

class TaskType {
  const TaskType({required this.id, required this.code, required this.name, required this.isMilestone, this.isFitting = false, this.colorKey, this.isActive = true});

  factory TaskType.fromJson(Map<String, dynamic> json) => TaskType(
        id: (json['id'] as num).toInt(),
        code: json['code'] as String,
        name: json['name'] as String,
        isMilestone: json['kind'] == 'milestone',
        isFitting: json['is_fitting'] as bool? ?? false,
        colorKey: json['color_key'] as String?,
        isActive: json['is_active'] as bool? ?? true,
      );

  final int id;
  final String code;
  final String name;
  final bool isMilestone;
  final bool isFitting;
  final String? colorKey;
  final bool isActive;
}

/// One step of a garment's default routing.
class TemplateTask {
  const TemplateTask({required this.taskType, required this.name, required this.estimatedSeconds, this.customName});

  factory TemplateTask.fromJson(Map<String, dynamic> json) => TemplateTask(
        taskType: TaskType.fromJson(json['task_type'] as Map<String, dynamic>),
        name: json['name'] as String,
        customName: json['custom_name'] as String?,
        estimatedSeconds: (json['default_estimated_seconds'] as num?)?.toInt() ?? 0,
      );

  final TaskType taskType;
  final String name;
  final String? customName;
  final int estimatedSeconds;
}

/// Garment type (3-Piece Suit, Kaftan …) with its routing template.
class JobType {
  const JobType({required this.id, required this.name, required this.tasks, this.components, this.defaultQuantity = 1, this.isActive = true});

  factory JobType.fromJson(Map<String, dynamic> json) => JobType(
        id: (json['id'] as num).toInt(),
        name: json['name'] as String,
        components: json['components'] as String?,
        defaultQuantity: (json['default_quantity'] as num?)?.toInt() ?? 1,
        isActive: json['is_active'] as bool? ?? true,
        tasks: (json['tasks'] as List<dynamic>? ?? const []).cast<Map<String, dynamic>>().map(TemplateTask.fromJson).toList(),
      );

  final int id;
  final String name;
  final String? components;
  final int defaultQuantity;
  final bool isActive;
  final List<TemplateTask> tasks;

  int get estimatedSeconds => tasks.fold(0, (sum, t) => sum + t.estimatedSeconds);
}

class JobHours {
  const JobHours({
    this.estimatedSeconds = 0,
    this.actualSeconds = 0,
    this.remainingSeconds = 0,
    this.overrunSeconds = 0,
    this.progressPercent = 0,
    this.isProgressManual = false,
    this.hasRunningTimer = false,
    this.taskCount = 0,
    this.completedTaskCount = 0,
  });

  factory JobHours.fromJson(Map<String, dynamic>? json) => json == null
      ? const JobHours()
      : JobHours(
          estimatedSeconds: (json['estimated_seconds'] as num?)?.toInt() ?? 0,
          actualSeconds: (json['actual_seconds'] as num?)?.toInt() ?? 0,
          remainingSeconds: (json['remaining_seconds'] as num?)?.toInt() ?? 0,
          overrunSeconds: (json['overrun_seconds'] as num?)?.toInt() ?? 0,
          progressPercent: (json['progress_percent'] as num?)?.toDouble() ?? 0,
          isProgressManual: json['is_progress_manual'] as bool? ?? false,
          hasRunningTimer: json['has_running_timer'] as bool? ?? false,
          taskCount: (json['task_count'] as num?)?.toInt() ?? 0,
          completedTaskCount: (json['completed_task_count'] as num?)?.toInt() ?? 0,
        );

  final int estimatedSeconds;
  final int actualSeconds;
  final int remainingSeconds;
  final int overrunSeconds;
  final double progressPercent;
  final bool isProgressManual;
  final bool hasRunningTimer;
  final int taskCount;
  final int completedTaskCount;
}

/// Compact stage for the list card's stage bar.
class JobStage {
  const JobStage({required this.id, required this.name, required this.typeName, required this.isMilestone, required this.status});

  factory JobStage.fromJson(Map<String, dynamic> json) => JobStage(
        id: json['id'] as String,
        name: json['name'] as String,
        typeName: json['type_name'] as String? ?? json['name'] as String,
        isMilestone: json['kind'] == 'milestone',
        status: TaskStatus.parse(json['status'] as String),
      );

  final String id;
  final String name;
  final String typeName;
  final bool isMilestone;
  final TaskStatus status;
}

class CurrentTask {
  const CurrentTask({required this.id, required this.name, required this.status, required this.isMilestone, required this.typeName, this.colorKey});

  factory CurrentTask.fromJson(Map<String, dynamic> json) => CurrentTask(
        id: json['id'] as String,
        name: json['name'] as String,
        status: TaskStatus.parse(json['status'] as String),
        isMilestone: json['kind'] == 'milestone',
        typeName: json['task_type_name'] as String? ?? json['name'] as String,
        colorKey: json['color_key'] as String?,
      );

  final String id;
  final String name;
  final TaskStatus status;
  final bool isMilestone;
  final String typeName;
  final String? colorKey;
}

class ChecklistItem {
  const ChecklistItem({required this.id, required this.label, required this.isDone, required this.version, this.doneAt});

  factory ChecklistItem.fromJson(Map<String, dynamic> json) => ChecklistItem(
        id: json['id'] as String,
        label: json['label'] as String,
        isDone: json['is_done'] as bool? ?? false,
        doneAt: DateTime.tryParse(json['done_at'] as String? ?? '')?.toLocal(),
        version: (json['version'] as num).toInt(),
      );

  final String id;
  final String label;
  final bool isDone;
  final DateTime? doneAt;
  final int version;
}

/// A production stage of a job, with calculated hours.
class JobTask {
  const JobTask({
    required this.id,
    required this.taskType,
    required this.name,
    required this.sortOrder,
    required this.status,
    required this.estimatedSeconds,
    required this.version,
    this.actualSeconds = 0,
    this.remainingSeconds = 0,
    this.overrunSeconds = 0,
    this.progressPercent = 0,
    this.isProgressManual = false,
    this.isRunning = false,
    this.logCount = 0,
    this.actualStart,
    this.actualEnd,
    this.scheduledStart,
    this.scheduledEnd,
    this.completedAt,
    this.notes,
    this.checklist = const [],
  });

  factory JobTask.fromJson(Map<String, dynamic> json) => JobTask(
        id: json['id'] as String,
        taskType: TaskType.fromJson(json['task_type'] as Map<String, dynamic>),
        name: json['name'] as String,
        sortOrder: (json['sort_order'] as num).toInt(),
        status: TaskStatus.parse(json['status'] as String),
        estimatedSeconds: (json['estimated_seconds'] as num?)?.toInt() ?? 0,
        actualSeconds: (json['actual_seconds'] as num?)?.toInt() ?? 0,
        remainingSeconds: (json['remaining_seconds'] as num?)?.toInt() ?? 0,
        overrunSeconds: (json['overrun_seconds'] as num?)?.toInt() ?? 0,
        progressPercent: (json['progress_percent'] as num?)?.toDouble() ?? 0,
        isProgressManual: json['is_progress_manual'] as bool? ?? false,
        isRunning: json['is_running'] as bool? ?? false,
        logCount: (json['log_count'] as num?)?.toInt() ?? 0,
        actualStart: _date(json['actual_start']),
        actualEnd: _date(json['actual_end']),
        scheduledStart: _date(json['scheduled_start']),
        scheduledEnd: _date(json['scheduled_end']),
        completedAt: _date(json['completed_at']),
        notes: json['notes'] as String?,
        checklist: (json['checklist'] as List<dynamic>? ?? const []).cast<Map<String, dynamic>>().map(ChecklistItem.fromJson).toList(),
        version: (json['version'] as num).toInt(),
      );

  final String id;
  final TaskType taskType;
  final String name;
  final int sortOrder;
  final TaskStatus status;
  final int estimatedSeconds;
  final int actualSeconds;
  final int remainingSeconds;
  final int overrunSeconds;
  final double progressPercent;
  final bool isProgressManual;
  final bool isRunning;
  final int logCount;
  final DateTime? actualStart;
  final DateTime? actualEnd;
  final DateTime? scheduledStart;
  final DateTime? scheduledEnd;
  final DateTime? completedAt;
  final String? notes;
  final List<ChecklistItem> checklist;
  final int version;

  bool get isMilestone => taskType.isMilestone;
}

class JobFlags {
  const JobFlags({this.isOverdue = false, this.isDueSoon = false, this.daysUntilDue});

  factory JobFlags.fromJson(Map<String, dynamic>? json) => JobFlags(
        isOverdue: json?['is_overdue'] as bool? ?? false,
        isDueSoon: json?['is_due_soon'] as bool? ?? false,
        daysUntilDue: (json?['days_until_due'] as num?)?.toInt(),
      );

  final bool isOverdue;
  final bool isDueSoon;
  final int? daysUntilDue;
}

/// A job: list card fields always; sheet fields ([tasks], notes …) from GET /jobs/{id} and mutations.
class Job {
  const Job({
    required this.id,
    required this.title,
    required this.quantity,
    required this.priority,
    required this.status,
    required this.customerId,
    required this.customerName,
    required this.jobTypeId,
    required this.jobTypeName,
    required this.orderDate,
    required this.hours,
    required this.stepIndex,
    required this.stepTotal,
    required this.stages,
    required this.flags,
    required this.allowedTransitions,
    required this.version,
    this.jobNumber,
    this.customerPhone,
    this.components,
    this.dueDate,
    this.collectionDate,
    this.completedAt,
    this.currentTask,
    this.description,
    this.fabricNote,
    this.notes,
    this.cancelReason,
    this.progressOverride,
    this.measurementSetId,
    this.measuredAt,
    this.tasks = const [],
  });

  factory Job.fromJson(Map<String, dynamic> json) {
    final customer = json['customer'] as Map<String, dynamic>;
    final type = json['job_type'] as Map<String, dynamic>;
    final step = json['step'] as Map<String, dynamic>? ?? const {};
    final set = json['measurement_set'] as Map<String, dynamic>?;
    return Job(
      id: json['id'] as String,
      jobNumber: json['job_number'] as String?,
      title: json['title'] as String,
      quantity: (json['quantity'] as num?)?.toInt() ?? 1,
      priority: JobPriority.parse(json['priority'] as String?),
      status: JobStatus.parse(json['status'] as String),
      customerId: customer['id'] as String,
      customerName: customer['full_name'] as String,
      customerPhone: customer['phone'] as String?,
      jobTypeId: (type['id'] as num).toInt(),
      jobTypeName: type['name'] as String,
      components: type['components'] as String?,
      orderDate: DateTime.parse(json['order_date'] as String),
      dueDate: DateTime.tryParse(json['due_date'] as String? ?? ''),
      collectionDate: DateTime.tryParse(json['collection_date'] as String? ?? ''),
      completedAt: _date(json['completed_at']),
      hours: JobHours.fromJson(json['hours'] as Map<String, dynamic>?),
      currentTask: json['current_task'] is Map<String, dynamic> ? CurrentTask.fromJson(json['current_task'] as Map<String, dynamic>) : null,
      stepIndex: (step['index'] as num?)?.toInt() ?? 0,
      stepTotal: (step['total'] as num?)?.toInt() ?? 0,
      stages: (json['stages'] as List<dynamic>? ?? const []).cast<Map<String, dynamic>>().map(JobStage.fromJson).toList(),
      flags: JobFlags.fromJson(json['flags'] as Map<String, dynamic>?),
      allowedTransitions: (json['allowed_transitions'] as List<dynamic>? ?? const []).cast<String>().map(JobStatus.parse).toList(),
      version: (json['version'] as num).toInt(),
      description: json['description'] as String?,
      fabricNote: json['fabric_note'] as String?,
      notes: json['notes'] as String?,
      cancelReason: json['cancel_reason'] as String?,
      progressOverride: (json['progress_override'] as num?)?.toDouble(),
      measurementSetId: set?['id'] as String?,
      measuredAt: _date(set?['measured_at']),
      tasks: (json['tasks'] as List<dynamic>? ?? const []).cast<Map<String, dynamic>>().map(JobTask.fromJson).toList(),
    );
  }

  final String id;
  final String? jobNumber;
  final String title;
  final int quantity;
  final JobPriority priority;
  final JobStatus status;
  final String customerId;
  final String customerName;
  final String? customerPhone;
  final int jobTypeId;
  final String jobTypeName;
  final String? components;

  /// Business-local calendar dates (no time of day).
  final DateTime orderDate;
  final DateTime? dueDate;
  final DateTime? collectionDate;
  final DateTime? completedAt;
  final JobHours hours;
  final CurrentTask? currentTask;
  final int stepIndex;
  final int stepTotal;
  final List<JobStage> stages;
  final JobFlags flags;
  final List<JobStatus> allowedTransitions;
  final int version;
  final String? description;
  final String? fabricNote;
  final String? notes;
  final String? cancelReason;
  final double? progressOverride;
  final String? measurementSetId;
  final DateTime? measuredAt;
  final List<JobTask> tasks;

  /// "#024" (or "Unnumbered" before the server assigned one).
  String get displayNumber => jobNumber == null ? 'New' : '#$jobNumber';

  bool canMoveTo(JobStatus status) => allowedTransitions.contains(status);

  List<JobTask> get workTasks => tasks.where((t) => !t.isMilestone).toList();

  JobTask? get currentJobTask => currentTask == null ? null : tasks.where((t) => t.id == currentTask!.id).firstOrNull;

  /// Every work stage is completed or skipped.
  bool get allWorkDone => tasks.isNotEmpty && workTasks.every((t) => t.status.isClosed);
}

/// Numbers for the list filter chips.
class JobCounts {
  const JobCounts(this.values);

  factory JobCounts.fromJson(Map<String, dynamic> json) => JobCounts(json.map((k, v) => MapEntry(k, (v as num).toInt())));

  final Map<String, int> values;

  int operator [](String filter) => values[filter] ?? 0;
}

/// A stage in the create-job routing (template copy, hours editable).
class PlannedTask {
  const PlannedTask({required this.taskType, required this.name, required this.estimatedSeconds});

  final TaskType taskType;
  final String name;
  final int estimatedSeconds;

  PlannedTask copyWith({int? estimatedSeconds, String? name}) =>
      PlannedTask(taskType: taskType, name: name ?? this.name, estimatedSeconds: estimatedSeconds ?? this.estimatedSeconds);

  Map<String, dynamic> toJson() => {'task_type_id': taskType.id, 'task_name': name, 'estimated_seconds': estimatedSeconds};

  Map<String, dynamic> toTemplateJson() => {'task_type_id': taskType.id, 'task_name': name, 'default_estimated_seconds': estimatedSeconds};
}

/// Fields of the create / edit job forms.
class JobDraft {
  const JobDraft({
    this.title,
    this.quantity,
    this.priority = JobPriority.normal,
    this.dueDate,
    this.collectionDate,
    this.fabricNote,
    this.notes,
    this.description,
    this.measurementSetId,
  });

  final String? title;
  final int? quantity;
  final JobPriority priority;
  final DateTime? dueDate;
  final DateTime? collectionDate;
  final String? fabricNote;
  final String? notes;
  final String? description;
  final String? measurementSetId;

  Map<String, dynamic> toJson() => {
        'title': _blank(title),
        'quantity': ?quantity,
        'priority': priority.name,
        'due_date': dueDate == null ? null : dateOnly(dueDate!),
        'collection_date': collectionDate == null ? null : dateOnly(collectionDate!),
        'fabric_note': _blank(fabricNote),
        'notes': _blank(notes),
        'description': _blank(description),
        'measurement_set_id': measurementSetId,
      };

  static String? _blank(String? value) => value == null || value.trim().isEmpty ? null : value.trim();
}

/// Y-m-d for business dates.
String dateOnly(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

DateTime? _date(Object? value) => value is String ? DateTime.tryParse(value)?.toLocal() : null;
