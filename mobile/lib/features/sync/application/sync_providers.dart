import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/local/local_store.dart';
import '../../../core/providers.dart';
import '../../auth/application/session_controller.dart';
import '../data/sync_engine.dart';
import '../domain/presenter.dart';

/// The device database. main() overrides it with the file in app-private storage; the in-memory
/// default serves tests and previews.
final localStoreProvider = Provider<LocalStore>((ref) {
  final store = LocalStore.memory();
  ref.onDispose(store.dispose);
  return store;
});

final syncEngineProvider = Provider<SyncEngine>((ref) {
  final store = ref.watch(localStoreProvider);
  return SyncEngine(
    client: ref.watch(apiClientProvider),
    store: store,
    actor: () {
      final user = ref.read(sessionControllerProvider).value?.user;
      return user == null ? null : (id: user.id, name: user.fullName);
    },
  );
});

/// Increments on every change to the local copy: everything that reads it recomputes.
final storeTickProvider = NotifierProvider<StoreTick, int>(StoreTick.new);

class StoreTick extends Notifier<int> {
  @override
  int build() {
    final sub = ref.watch(localStoreProvider).changes.listen((_) => state++);
    ref.onDispose(sub.cancel);
    return 0;
  }
}

/// First sync for the signed-in account. Another account's data is removed from the phone first.
final bootstrapProvider = FutureProvider<void>((ref) async {
  final userId = ref.watch(sessionControllerProvider.select((s) => s.value?.user.id));
  if (userId == null) return;
  final store = ref.read(localStoreProvider);
  if (store.meta('user_id') != '$userId') {
    store.wipe();
    store.setMeta('user_id', '$userId');
  }
  final engine = ref.read(syncEngineProvider);
  if (engine.config == null) {
    await engine.sync();
  } else {
    // After this provider has built: syncNow updates the sync status, and providers may not change
    // other providers while they build.
    final controller = ref.read(syncControllerProvider.notifier);
    unawaited(Future<void>.microtask(controller.syncNow));
  }
});

/// Snapshot of the local copy for screens. Loading until the first download; an error (e.g. offline
/// on the very first start) is shown with Retry.
final presenterProvider = Provider<AsyncValue<Presenter>>((ref) {
  ref.watch(storeTickProvider);
  final boot = ref.watch(bootstrapProvider);
  ref.watch(sessionControllerProvider.select((s) => s.value?.user.id));
  final presenter = ref.read(syncEngineProvider).presenter();
  if (presenter != null) return AsyncData(presenter);
  return switch (boot) {
    AsyncError(:final error, :final stackTrace) => AsyncError(error, stackTrace),
    _ => const AsyncLoading(),
  };
});

/// Reads one thing from the local copy as an AsyncValue (errors such as "not found" become AsyncError).
AsyncValue<T> fromStore<T>(Ref ref, T Function(Presenter p) read) {
  return ref.watch(presenterProvider).whenData((p) => read(p));
}

class SyncStatus {
  const SyncStatus({required this.online, required this.syncing, required this.pending, required this.failed, this.lastSync});

  final bool online;
  final bool syncing;
  final int pending;
  final int failed;
  final DateTime? lastSync;
}

/// Sync state for the banner, plus when to sync: on start, every 30 s while changes wait, every
/// 2 minutes otherwise, and when the app comes back to the foreground.
final syncControllerProvider = NotifierProvider<SyncController, SyncStatus>(SyncController.new);

class SyncController extends Notifier<SyncStatus> {
  bool _syncing = false;

  SyncEngine get _engine => ref.read(syncEngineProvider);

  @override
  SyncStatus build() {
    // Built once: store changes only refresh the counts (rebuilding would restart the timer).
    ref.listen(storeTickProvider, (_, _) => state = _status());
    final timer = Timer.periodic(const Duration(seconds: 30), (_) => _tick());
    final lifecycle = AppLifecycleListener(onResume: () => unawaited(syncNow()));
    ref.onDispose(() {
      timer.cancel();
      lifecycle.dispose();
    });
    return _status();
  }

  SyncStatus _status() => SyncStatus(
        online: _engine.online,
        syncing: _syncing,
        pending: _engine.pending.length,
        failed: _engine.failed.length,
        lastSync: _engine.lastSync,
      );

  void _tick() {
    if (ref.read(sessionControllerProvider).value == null) return;
    final last = _engine.lastSync;
    if (_engine.pending.isNotEmpty || last == null || DateTime.now().difference(last) > const Duration(minutes: 2)) {
      unawaited(syncNow());
    }
  }

  /// Push and pull now (pull-to-refresh, app resume). Never throws.
  Future<void> syncNow() async {
    if (ref.read(sessionControllerProvider).value == null) return;
    _syncing = true;
    state = _status();
    try {
      await _engine.sync();
    } catch (_) {
      // Offline or server busy: the status shows it and the timer tries again.
    } finally {
      _syncing = false;
      state = _status();
    }
  }
}
