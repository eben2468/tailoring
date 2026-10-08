import 'package:uuid/uuid.dart';

import '../../../core/network/api_client.dart';
import '../domain/job.dart';

/// /jobs, /tasks, /checklist-items, /job-types and /task-types (docs/API_REFERENCE.md §7–9).
/// Every job and stage mutation returns the full job sheet.
class JobsApi {
  const JobsApi(this._client);

  final ApiClient _client;

  // ---- Configuration

  Future<List<JobType>> jobTypes({bool includeInactive = false}) async =>
      (await _client.get('/job-types', query: {if (includeInactive) 'include_inactive': 1}) as List<dynamic>).cast<Map<String, dynamic>>().map(JobType.fromJson).toList();

  Future<List<TaskType>> taskTypes() async => (await _client.get('/task-types') as List<dynamic>).cast<Map<String, dynamic>>().map(TaskType.fromJson).toList();

  Future<JobType> saveTemplates(int jobTypeId, List<PlannedTask> tasks) async =>
      JobType.fromJson(await _client.put('/job-types/$jobTypeId/templates', body: {'tasks': tasks.map((t) => t.toTemplateJson()).toList()}) as Map<String, dynamic>);

  Future<JobType> createJobType({required String name, String? components, required List<PlannedTask> tasks}) async => JobType.fromJson(
        await _client.post('/job-types', body: {
          'type_name': name,
          'components': components == null || components.trim().isEmpty ? null : components.trim(),
          'tasks': tasks.map((t) => t.toTemplateJson()).toList(),
        }) as Map<String, dynamic>,
      );

  Future<JobType> updateJobType(int id, {String? name, String? components, bool? isActive}) async => JobType.fromJson(
        await _client.patch('/job-types/$id', body: {'type_name': ?name, 'components': ?components, 'is_active': ?isActive}) as Map<String, dynamic>,
      );

  Future<TaskType> createTaskType(String name) async => TaskType.fromJson(await _client.post('/task-types', body: {'type_name': name}) as Map<String, dynamic>);

  // ---- Jobs

  Future<Paged<Job>> list({String filter = 'open', String? query, String? customerId, int page = 1}) =>
      _client.getPaged('/jobs', Job.fromJson, query: {'filter': filter, 'q': query, 'customer_id': customerId, 'page': page, 'per_page': 20});

  Future<JobCounts> counts({String? customerId}) async => JobCounts.fromJson(await _client.get('/jobs/counts', query: {'customer_id': customerId}) as Map<String, dynamic>);

  Future<Job> get(String id) => _job(_client.get('/jobs/$id'));

  /// The id is generated here, so a retried request never creates the job twice.
  Future<Job> create({
    required String customerId,
    required int jobTypeId,
    required bool draft,
    required JobDraft fields,
    required List<PlannedTask> tasks,
  }) =>
      _job(_client.post('/jobs', body: {
        'id': const Uuid().v7(),
        'customer_id': customerId,
        'job_type_id': jobTypeId,
        'status': draft ? 'draft' : 'queued',
        ...fields.toJson(),
        'tasks': tasks.map((t) => t.toJson()).toList(),
      }));

  Future<Job> update(String id, int version, JobDraft fields) => _job(_client.patch('/jobs/$id', body: {'version': version, ...fields.toJson()}));

  /// [force] confirms "ready for collection" while stages are unfinished.
  Future<Job> setStatus(String id, JobStatus status, {String? reason, bool force = false}) =>
      _job(_client.post('/jobs/$id/status', body: {'status': status.api, 'reason': ?reason, if (force) 'force': true}));

  Future<Job> setProgressOverride(String id, double? percent) => _job(_client.post('/jobs/$id/progress-override', body: {'progress_percent': percent}));

  Future<void> deleteDraft(String id) => _client.delete('/jobs/$id');

  // ---- Stages and subtasks

  Future<Job> addTask(String jobId, {required int taskTypeId, String? name, int estimatedSeconds = 0}) => _job(_client.post('/jobs/$jobId/tasks', body: {
        'id': const Uuid().v7(),
        'task_type_id': taskTypeId,
        'task_name': name,
        'estimated_seconds': estimatedSeconds,
      }));

  Future<Job> reorderTasks(String jobId, List<String> taskIds) => _job(_client.put('/jobs/$jobId/tasks/order', body: {'task_ids': taskIds}));

  Future<Job> updateTask(JobTask task, {String? name, int? estimatedSeconds, String? notes}) => _job(_client.patch('/tasks/${task.id}', body: {
        'version': task.version,
        'task_name': ?name,
        'estimated_seconds': ?estimatedSeconds,
        if (notes != null) 'notes': notes.trim().isEmpty ? null : notes.trim(),
      }));

  Future<Job> setTaskStatus(JobTask task, TaskStatus status) => _job(_client.post('/tasks/${task.id}/status', body: {'status': status.api, 'version': task.version}));

  Future<Job> deleteTask(String taskId) => _job(_client.delete('/tasks/$taskId'));

  Future<Job> addChecklistItem(String taskId, String label) => _job(_client.post('/tasks/$taskId/checklist', body: {'id': const Uuid().v7(), 'label': label}));

  Future<Job> setChecklistDone(ChecklistItem item, {required bool done}) =>
      _job(_client.patch('/checklist-items/${item.id}', body: {'is_done': done, 'version': item.version}));

  Future<Job> deleteChecklistItem(String itemId) => _job(_client.delete('/checklist-items/$itemId'));

  Future<Job> _job(Future<dynamic> request) async => Job.fromJson(await request as Map<String, dynamic>);
}
