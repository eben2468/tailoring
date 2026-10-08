import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../../customers/application/customer_providers.dart';
import '../data/jobs_api.dart';
import '../domain/job.dart';

final jobsApiProvider = Provider<JobsApi>((ref) => JobsApi(ref.watch(apiClientProvider)));

/// Active garment types with their routing templates (create-job screen).
final jobTypesProvider = FutureProvider.autoDispose<List<JobType>>((ref) => ref.watch(jobsApiProvider).jobTypes());

/// All garment types incl. inactive (settings).
final allJobTypesProvider = FutureProvider.autoDispose<List<JobType>>((ref) => ref.watch(jobsApiProvider).jobTypes(includeInactive: true));

final taskTypesProvider = FutureProvider.autoDispose<List<TaskType>>((ref) => ref.watch(jobsApiProvider).taskTypes());

/// Filter-chip counts; `null` = all customers.
final jobCountsProvider = FutureProvider.autoDispose.family<JobCounts, String?>((ref, customerId) => ref.watch(jobsApiProvider).counts(customerId: customerId));

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
  const JobListState({required this.items, required this.total, required this.page, required this.hasMore, this.loadingMore = false});

  final List<Job> items;
  final int total;
  final int page;
  final bool hasMore;
  final bool loadingMore;

  JobListState copyWith({List<Job>? items, int? page, bool? hasMore, bool? loadingMore}) => JobListState(
        items: items ?? this.items,
        total: total,
        page: page ?? this.page,
        hasMore: hasMore ?? this.hasMore,
        loadingMore: loadingMore ?? this.loadingMore,
      );
}

final jobListProvider = AsyncNotifierProvider.autoDispose.family<JobListController, JobListState, JobQuery>(JobListController.new);

class JobListController extends AsyncNotifier<JobListState> {
  JobListController(this.query);

  final JobQuery query;

  @override
  Future<JobListState> build() async {
    final first = await ref.read(jobsApiProvider).list(filter: query.filter, query: query.text, customerId: query.customerId);
    return JobListState(items: first.items, total: first.total, page: first.page, hasMore: first.hasMore);
  }

  Future<void> loadMore() async {
    final current = state.value;
    if (current == null || !current.hasMore || current.loadingMore) return;
    state = AsyncData(current.copyWith(loadingMore: true));
    try {
      final next = await ref.read(jobsApiProvider).list(filter: query.filter, query: query.text, customerId: query.customerId, page: current.page + 1);
      state = AsyncData(current.copyWith(items: [...current.items, ...next.items], page: next.page, hasMore: next.hasMore, loadingMore: false));
    } catch (_) {
      state = AsyncData(current.copyWith(loadingMore: false));
      rethrow;
    }
  }
}

/// The job sheet. Every mutation returns the recalculated sheet from the server, which replaces the
/// state directly (no refetch); lists, counts and the customer summary are refreshed afterwards.
final jobProvider = AsyncNotifierProvider.autoDispose.family<JobController, Job, String>(JobController.new);

class JobController extends AsyncNotifier<Job> {
  JobController(this.jobId);

  final String jobId;

  JobsApi get _api => ref.read(jobsApiProvider);

  @override
  Future<Job> build() => ref.read(jobsApiProvider).get(jobId);

  /// Runs a mutation; on failure the previous sheet stays and the error is rethrown for the screen.
  Future<Job> run(Future<Job> Function(JobsApi api) mutation) async {
    final job = await mutation(_api);
    state = AsyncData(job);
    invalidateJobLists(ref, customerId: job.customerId);
    return job;
  }

  /// A fresher sheet from elsewhere (timer and work-log calls return the job too).
  void replace(Job job) => state = AsyncData(job);

  Future<Job> setStatus(JobStatus status, {String? reason, bool force = false}) => run((api) => api.setStatus(jobId, status, reason: reason, force: force));

  Future<Job> setTaskStatus(JobTask task, TaskStatus status) => run((api) => api.setTaskStatus(task, status));

  Future<Job> toggleChecklist(ChecklistItem item) => run((api) => api.setChecklistDone(item, done: !item.isDone));
}

/// Lists, chip counts and the customer's summary change whenever a job does.
void invalidateJobLists(Ref ref, {String? customerId}) {
  ref
    ..invalidate(jobListProvider)
    ..invalidate(jobCountsProvider);
  if (customerId != null) ref.invalidate(customerProvider(customerId));
}

/// [invalidateJobLists] for screens (after creating or deleting a job).
void invalidateJobListsFromWidget(WidgetRef ref, {String? customerId}) {
  ref
    ..invalidate(jobListProvider)
    ..invalidate(jobCountsProvider);
  if (customerId != null) ref.invalidate(customerProvider(customerId));
}
