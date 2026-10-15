import 'package:uuid/uuid.dart';

import '../../../core/local/local_store.dart';
import '../../../core/network/api_exception.dart';
import '../../sync/data/sync_engine.dart';
import '../domain/job.dart';

/// Job, stage and subtask writes (docs/API_REFERENCE.md §8–9). They work offline; each returns the
/// job sheet from the local copy. Garment templates and stage types are configuration and need a
/// connection (§7).
class JobsApi {
  const JobsApi(this._sync);

  final SyncEngine _sync;

  Job _sheet(String jobId) {
    final presenter = _sync.presenter();
    final row = _sync.store.get(Tables.jobs, jobId);
    if (presenter == null || row == null || row['deleted_at'] != null) throw const NotFoundException('This job was not found.');
    return Job.fromJson(presenter.job(row, detail: true));
  }

  String _jobOfTask(String taskId) => _sync.store.get(Tables.tasks, taskId)?['job_id'] as String? ?? (throw const NotFoundException('This stage was not found.'));

  String _label(String jobId) {
    final job = _sync.store.get(Tables.jobs, jobId);
    final number = job?['job_number'];
    return number == null ? (job?['title'] as String? ?? 'job') : '#$number';
  }

  Future<Job> _do(String jobId, String label, String method, String path, [Map<String, dynamic> body = const {}]) async {
    await _sync.perform(label: label, method: method, path: path, body: body);
    return _sheet(jobId);
  }

  // ---- Configuration (online only; refreshes the downloaded configuration)

  Future<void> saveTemplates(int jobTypeId, List<PlannedTask> tasks) async {
    await _sync.client.put('/job-types/$jobTypeId/templates', body: {'tasks': tasks.map((t) => t.toTemplateJson()).toList()});
    await _sync.refreshConfig();
  }

  Future<JobType> createJobType({required String name, String? components, required List<PlannedTask> tasks}) async {
    final created = JobType.fromJson(await _sync.client.post('/job-types', body: {
      'type_name': name,
      'components': components == null || components.trim().isEmpty ? null : components.trim(),
      'tasks': tasks.map((t) => t.toTemplateJson()).toList(),
    }) as Map<String, dynamic>);
    await _sync.refreshConfig();
    return created;
  }

  Future<void> updateJobType(int id, {String? name, String? components, bool? isActive}) async {
    await _sync.client.patch('/job-types/$id', body: {'type_name': ?name, 'components': ?components, 'is_active': ?isActive});
    await _sync.refreshConfig();
  }

  Future<TaskType> createTaskType(String name) async {
    final created = TaskType.fromJson(await _sync.client.post('/task-types', body: {'type_name': name}) as Map<String, dynamic>);
    await _sync.refreshConfig();
    return created;
  }

  // ---- Jobs

  /// The job and stage ids are generated here, so a retry (or an offline replay) never duplicates them.
  Future<Job> create({
    required String customerId,
    required int jobTypeId,
    required bool draft,
    required JobDraft fields,
    required List<PlannedTask> tasks,
  }) async {
    final id = const Uuid().v7();
    final customer = _sync.store.get(Tables.customers, customerId)?['full_name'] ?? 'customer';
    await _sync.perform(label: '${draft ? 'Draft job' : 'New job'} for $customer', method: 'POST', path: '/jobs', body: {
      'id': id,
      'customer_id': customerId,
      'job_type_id': jobTypeId,
      'status': draft ? 'draft' : 'queued',
      ...fields.toJson(),
      'tasks': [for (final t in tasks) {'id': const Uuid().v7(), ...t.toJson()}],
    });
    return _sheet(id);
  }

  Future<Job> update(String id, int version, JobDraft fields) => _do(id, 'Edit job ${_label(id)}', 'PATCH', '/jobs/$id', {'version': version, ...fields.toJson()});

  /// [force] confirms "ready for collection" while stages are unfinished.
  Future<Job> setStatus(String id, JobStatus status, {String? reason, bool force = false}) =>
      _do(id, '${_label(id)}: ${status.label.toLowerCase()}', 'POST', '/jobs/$id/status', {'status': status.api, 'reason': ?reason, if (force) 'force': true});

  Future<Job> setProgressOverride(String id, double? percent) => _do(id, '${_label(id)}: progress', 'POST', '/jobs/$id/progress-override', {'progress_percent': percent});

  Future<void> deleteDraft(String id) => _sync.perform(label: 'Delete draft ${_label(id)}', method: 'DELETE', path: '/jobs/$id');

  // ---- Stages and subtasks

  Future<Job> addTask(String jobId, {required int taskTypeId, String? name, int estimatedSeconds = 0}) =>
      _do(jobId, '${_label(jobId)}: add stage', 'POST', '/jobs/$jobId/tasks', {'id': const Uuid().v7(), 'task_type_id': taskTypeId, 'task_name': name, 'estimated_seconds': estimatedSeconds});

  Future<Job> reorderTasks(String jobId, List<String> taskIds) => _do(jobId, '${_label(jobId)}: reorder stages', 'PUT', '/jobs/$jobId/tasks/order', {'task_ids': taskIds});

  Future<Job> updateTask(JobTask task, {String? name, int? estimatedSeconds, String? notes}) {
    final jobId = _jobOfTask(task.id);
    return _do(jobId, '${_label(jobId)}: edit ${task.name}', 'PATCH', '/tasks/${task.id}', {
      'version': task.version,
      'task_name': ?name,
      'estimated_seconds': ?estimatedSeconds,
      if (notes != null) 'notes': notes.trim().isEmpty ? null : notes.trim(),
    });
  }

  /// Plans the stage as a block in the calendar ([start] null clears the plan).
  Future<Job> planTask(JobTask task, {DateTime? start, DateTime? end}) {
    final jobId = _jobOfTask(task.id);
    return _do(jobId, start == null ? '${task.name}: unplanned' : '${task.name}: planned', 'PATCH', '/tasks/${task.id}', {
      'version': task.version,
      'scheduled_start': start?.toUtc().toIso8601String(),
      'scheduled_end': end?.toUtc().toIso8601String(),
    });
  }

  /// No version is sent: a status change is safe to apply on top of other edits (last change wins).
  Future<Job> setTaskStatus(JobTask task, TaskStatus status) {
    final jobId = _jobOfTask(task.id);
    return _do(jobId, '${task.name}: ${status.label.toLowerCase()}', 'POST', '/tasks/${task.id}/status', {'status': status.api});
  }

  Future<Job> deleteTask(String taskId) {
    final jobId = _jobOfTask(taskId);
    return _do(jobId, '${_label(jobId)}: remove stage', 'DELETE', '/tasks/$taskId');
  }

  Future<Job> addChecklistItem(String taskId, String label) {
    final jobId = _jobOfTask(taskId);
    return _do(jobId, 'Subtask: $label', 'POST', '/tasks/$taskId/checklist', {'id': const Uuid().v7(), 'label': label});
  }

  Future<Job> setChecklistDone(ChecklistItem item, {required bool done}) {
    final taskId = _sync.store.get(Tables.checklist, item.id)?['job_task_id'] as String? ?? (throw const NotFoundException('This subtask was not found.'));
    return _do(_jobOfTask(taskId), '${item.label}: ${done ? 'done' : 'not done'}', 'PATCH', '/checklist-items/${item.id}', {'is_done': done});
  }

  Future<Job> deleteChecklistItem(String itemId) {
    final taskId = _sync.store.get(Tables.checklist, itemId)?['job_task_id'] as String? ?? (throw const NotFoundException('This subtask was not found.'));
    return _do(_jobOfTask(taskId), 'Remove subtask', 'DELETE', '/checklist-items/$itemId');
  }
}
