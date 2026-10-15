import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/local/local_store.dart';
import '../../../core/network/api_exception.dart';
import '../../sync/application/sync_providers.dart';
import '../data/jobs_api.dart';
import '../domain/job.dart';

final jobsApiProvider = Provider<JobsApi>((ref) => JobsApi(ref.watch(syncEngineProvider)));

/// Active garment types with their routing templates (create-job screen).
final jobTypesProvider = Provider<AsyncValue<List<JobType>>>(
  (ref) => fromStore(ref, (p) => p.config.jobTypes.where((t) => t['is_active'] != false).map(JobType.fromJson).toList()),
);

/// All garment types incl. hidden ones (settings).
final allJobTypesProvider = Provider<AsyncValue<List<JobType>>>((ref) => fromStore(ref, (p) => p.config.jobTypes.map(JobType.fromJson).toList()));

/// Active production stages.
final taskTypesProvider = Provider<AsyncValue<List<TaskType>>>(
  (ref) => fromStore(ref, (p) => p.config.taskTypes.where((t) => t['is_active'] != false).map(TaskType.fromJson).toList()),
);

/// Filter-chip counts; `null` = all customers.
final jobCountsProvider = Provider.family<AsyncValue<JobCounts>, String?>((ref, customerId) => fromStore(ref, (p) => JobCounts(p.jobCounts(customerId: customerId))));

/// The list chips, in display order (API filter → label).
const jobFilters = <(String, String)>[
  ('open', 'All'),
  ('active', 'Active'),
  ('pending', 'Pending'),
  ('due_soon', 'Due Soon'),
  ('overdue', 'Overdue'),
  ('ready', 'Ready'),
  ('completed', 'Collected'),
  ('cancelled', 'Cancelled'),
];

class JobQuery {
  const JobQuery({this.filter = 'open', this.text = '', this.customerId});

  final String filter;
  final String text;
  final String? customerId;

  @override
  bool operator ==(Object other) => other is JobQuery && other.filter == filter && other.text == text && other.customerId == customerId;

  @override
  int get hashCode => Object.hash(filter, text, customerId);
}

class JobListState {
  const JobListState({required this.items});

  final List<Job> items;

  int get total => items.length;
}

final jobListProvider = Provider.family<AsyncValue<JobListState>, JobQuery>((ref, q) => fromStore(
      ref,
      (p) => JobListState(items: p.jobs(filter: q.filter, query: q.text.trim(), customerId: q.customerId).map(Job.fromJson).toList()),
    ));

/// The job sheet, from the local copy, plus its actions. Every action applies the change (online or
/// offline) and the sheet updates from the local copy.
final jobProvider = NotifierProvider.family<JobController, AsyncValue<Job>, String>(JobController.new);

class JobController extends Notifier<AsyncValue<Job>> {
  JobController(this.jobId);

  final String jobId;

  JobsApi get _api => ref.read(jobsApiProvider);

  @override
  AsyncValue<Job> build() => fromStore(ref, (p) {
        final row = p.store.get(Tables.jobs, jobId);
        if (row == null || row['deleted_at'] != null) throw const NotFoundException('This job was not found. It may have been removed on another device.');
        return Job.fromJson(p.job(row, detail: true));
      });

  /// Runs an action; errors are rethrown for the screen.
  Future<Job> run(Future<Job> Function(JobsApi api) mutation) => mutation(_api);

  Future<Job> setStatus(JobStatus status, {String? reason, bool force = false}) => _api.setStatus(jobId, status, reason: reason, force: force);

  Future<Job> setTaskStatus(JobTask task, TaskStatus status) => _api.setTaskStatus(task, status);

  Future<Job> toggleChecklist(ChecklistItem item) => _api.setChecklistDone(item, done: !item.isDone);
}
