import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../sync/application/sync_providers.dart';
import '../../sync/domain/presenter.dart';
import '../domain/dashboard.dart';

/// The current minute, so time-dependent figures (shop open, today, overdue) move on while the app is open.
final minuteClockProvider = NotifierProvider<MinuteClock, DateTime>(MinuteClock.new);

class MinuteClock extends Notifier<DateTime> {
  @override
  DateTime build() {
    final timer = Timer.periodic(const Duration(minutes: 1), (_) => state = DateTime.now());
    ref.onDispose(timer.cancel);
    return DateTime.now();
  }
}

/// The dashboard from the local copy (Presenter.dashboard mirrors GET /dashboard), so it works offline.
final dashboardProvider = Provider<AsyncValue<Dashboard>>((ref) {
  final now = ref.watch(minuteClockProvider);
  return fromStore(ref, (p) => Dashboard.fromJson(Presenter(p.store, p.config, now: now, userId: p.userId).dashboard()));
});
