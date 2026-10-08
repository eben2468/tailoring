import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../../auth/application/session_controller.dart';
import '../../jobs/application/job_providers.dart';
import '../../jobs/domain/job.dart';
import '../data/timer_api.dart';
import '../domain/timer.dart';

final timerApiProvider = Provider<TimerApi>((ref) => TimerApi(ref.watch(apiClientProvider)));

/// The signed-in user's running timer, app-wide (timer bar, job cards, timer screen).
/// Restored from the server on sign-in / app start, so it survives the app being killed.
final activeTimerProvider = AsyncNotifierProvider<ActiveTimerController, ActiveTimer?>(ActiveTimerController.new);

class ActiveTimerController extends AsyncNotifier<ActiveTimer?> {
  TimerApi get _api => ref.read(timerApiProvider);

  @override
  Future<ActiveTimer?> build() async {
    final signedIn = ref.watch(sessionControllerProvider.select((s) => s.value?.user.id));
    if (signedIn == null) return null;
    return (await ref.read(timerApiProvider).active()).timer;
  }

  Future<TimerResult> start(String taskId) => _apply(_api.start(taskId));

  /// "Pause Work" or, with [complete], "Log & Finish".
  Future<TimerResult> stop({String? note, bool complete = false}) => _apply(_api.stop(note: note, complete: complete));

  Future<TimerResult> switchTo(String taskId, {String? note}) => _apply(_api.switchTo(taskId, note: note));

  /// "+15m Adjust" on the running stage (the timer itself keeps running).
  Future<WorkLogResult> adjust(Duration duration) async {
    final timer = state.value;
    if (timer == null) throw StateError('No timer is running.');
    final result = await _api.adjust(timer.taskId, duration);
    publishJob(ref, result.job);
    return result;
  }

  Future<TimerResult> _apply(Future<TimerResult> call) async {
    final result = await call;
    state = AsyncData(result.timer);
    if (result.job != null) publishJob(ref, result.job!);
    return result;
  }
}

/// Pushes a job sheet returned by a timer / work-log call into an open job screen and refreshes lists.
void publishJob(Ref ref, Job job) {
  if (ref.exists(jobProvider(job.id))) ref.read(jobProvider(job.id).notifier).replace(job);
  invalidateJobLists(ref, customerId: job.customerId);
}

/// Every entry of a stage (incl. voided), newest first.
final workLogsProvider = FutureProvider.autoDispose.family<List<WorkLogEntry>, String>((ref, taskId) => ref.watch(timerApiProvider).logs(taskId));
