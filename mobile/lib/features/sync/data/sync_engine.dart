import 'dart:async';
import 'dart:convert';

import 'package:uuid/uuid.dart';

import '../../../core/local/local_store.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';
import '../domain/config_bundle.dart';
import '../domain/local_ops.dart';
import '../domain/presenter.dart';

/// Who is acting (for offline rows: created_by / recorded_by).
typedef Actor = ({int id, String name});

/// Keeps the device's copy of the business data in step with the server (ARCHITECTURE §21).
///
/// - Pull: GET /sync/pull with the stored cursor; rows replace local rows (the server is the authority).
/// - Writes: tried online first (validation and conflicts show straight away). Without a connection the
///   change is applied to the local copy with the server's rules ([LocalOps]) and queued; queued calls
///   are replayed in order when the connection returns. Calls are idempotent (client ids, entry ids,
///   device time in `occurred_at`), so a replay after a lost response does no harm.
/// - A replay the server refuses (conflict, validation) stays in the queue as "failed" for the owner
///   to resolve; the next pull shows the server's version of the data.
class SyncEngine {
  SyncEngine({required this.client, required this.store, required this.actor});

  final ApiClient client;
  final LocalStore store;
  final Actor? Function() actor;

  Future<void>? _running;
  bool _online = true;
  DateTime? _lastSync;

  static const _cursorKey = 'sync_cursor';
  static const _configKey = 'config';
  static const _offsetKey = 'clock_offset_ms';
  static const _tablesKey = 'sync_tables';

  ConfigBundle? _config;
  String? _configJson;

  /// The last downloaded configuration (null before the first sync).
  ConfigBundle? get config {
    final raw = store.meta(_configKey);
    if (raw == null) return null;
    if (raw != _configJson) {
      _configJson = raw;
      _config = ConfigBundle.fromJson((jsonDecode(raw) as Map).cast<String, dynamic>());
    }
    return _config;
  }

  bool get online => _online;

  DateTime? get lastSync => _lastSync;

  /// Server time minus device time, measured at the last pull (timers display server time).
  Duration get clockOffset => Duration(milliseconds: int.tryParse(store.meta(_offsetKey) ?? '') ?? 0);

  int get cursor => int.tryParse(store.meta(_cursorKey) ?? '') ?? 0;

  List<OutboxItem> get pending => store.outbox.where((o) => o.status == OutboxStatus.pending).toList();

  List<OutboxItem> get failed => store.outbox.where((o) => o.status == OutboxStatus.failed).toList();

  Presenter? presenter() {
    final c = config;
    return c == null ? null : Presenter(store, c, userId: actor()?.id, now: DateTime.now().add(clockOffset));
  }

  /// Push queued changes, then pull. Concurrent calls share one run.
  Future<void> sync() => _running ??= _sync().whenComplete(() => _running = null);

  Future<void> _sync() async {
    await _push();
    if (pending.isNotEmpty && !_online) return; // still offline
    if (store.meta(_rebuildKey) != null) {
      await _rebuild();
    } else {
      await pull();
    }
  }

  /// Downloads every change since the cursor (and the configuration when it changed).
  Future<void> pull() async {
    // A table added to sync in a newer app version: its older rows lie before the stored cursor,
    // so download everything once.
    // The configuration of an older app version may lack what the new tables need (e.g. inventory
    // categories), so it is downloaded again too.
    final tables = Tables.all.join(',');
    final newTables = store.meta(_tablesKey) != tables;
    if (newTables) store.setMeta(_cursorKey, '0');
    try {
      var more = true;
      var configVersion = -1;
      while (more) {
        final sentAt = DateTime.now();
        final data = await client.get('/sync/pull', query: {'cursor': cursor, 'limit': 500}) as Map<String, dynamic>;
        final serverTime = DateTime.tryParse(data['server_time'] as String? ?? '');
        if (serverTime != null) {
          final mid = sentAt.add(DateTime.now().difference(sentAt) ~/ 2);
          store.setMeta(_offsetKey, serverTime.difference(mid).inMilliseconds.toString());
        }
        final changes = (data['changes'] as Map).cast<String, dynamic>();
        store.batch(() {
          for (final table in Tables.all) {
            for (final row in (changes[table] as List? ?? const []).cast<Map<String, dynamic>>()) {
              store.put(table, row);
            }
          }
          store.setMeta(_cursorKey, '${data['cursor']}');
        });
        more = data['has_more'] == true;
        configVersion = (data['config_version'] as num?)?.toInt() ?? configVersion;
      }
      if (newTables || config == null || config!.version != configVersion) await refreshConfig();
      store.setMeta(_tablesKey, tables);
      _online = true;
      _lastSync = DateTime.now();
    } on NetworkException {
      _online = false;
      rethrow;
    } on TimeoutApiException {
      _online = false;
      rethrow;
    }
  }

  /// GET /sync/config (also after the owner edits garment templates).
  Future<void> refreshConfig() async {
    final data = await client.get('/sync/config') as Map<String, dynamic>;
    store.setMeta(_configKey, jsonEncode(data));
  }

  /// Sends queued changes in order. Stops at the first connection problem.
  Future<void> _push() async {
    for (final item in pending) {
      try {
        await client.send(item.method, item.path, body: item.body);
        store.removeOutbox(item.seq);
        _online = true;
      } on NetworkException {
        _online = false;
        return;
      } on TimeoutApiException {
        _online = false;
        return;
      } on ServerException {
        return; // try again later
      } on RateLimitedException {
        return;
      } on UnauthorizedException {
        return; // the session is renewed or the owner signs in again; nothing is lost
      } on ApiException catch (e) {
        store.updateOutbox(item.copyWith(status: OutboxStatus.failed, errorCode: e.code, errorMessage: e.message));
      }
    }
  }

  /// A write. Online: the API call, then a pull (validation and conflict errors are thrown as usual).
  /// Offline (or while earlier changes wait in the queue): applied locally and queued.
  ///
  /// [queuedBody] replaces [body] when the call is queued, e.g. to add the device time (`occurred_at`).
  Future<void> perform({
    required String label,
    required String method,
    required String path,
    Map<String, dynamic> body = const {},
    Map<String, dynamic>? queuedBody,
  }) async {
    final route = matchOp(method, path) ?? (throw StateError('No offline rule for $method $path'));
    if (pending.isNotEmpty) await sync().catchError((Object _) {}); // keep the order of changes
    if (pending.isEmpty) {
      try {
        await client.send(method, path, body: body);
        _online = true;
        await pull().catchError((Object _) {}); // the change is saved; the copy catches up on the next sync
        return;
      } on NetworkException {
        _online = false;
      } on TimeoutApiException {
        _online = false;
      }
    }
    final who = actor() ?? (throw const UnauthorizedException('Sign in again to continue.'));
    final cfg = config ?? (throw const NetworkException('Connect once so the app can download your data.'));
    final queued = queuedBody ?? body;
    store.batch(() {
      LocalOps.apply(OpContext(store: store, config: cfg, userId: who.id, userName: who.name, newId: () => const Uuid().v7()), route, queued);
      store.enqueue(OutboxItem(seq: 0, op: route.op, method: method, path: path, body: queued, label: label, createdAt: DateTime.now()));
    });
  }

  /// Resend a failed change, optionally with a corrected body (e.g. allow a duplicate phone).
  Future<void> retry(OutboxItem item, {Map<String, dynamic>? body}) async {
    store.updateOutbox(item.copyWith(status: OutboxStatus.pending, body: body));
    await sync();
  }

  /// Drop a change the server refused. Its local effects are removed by rebuilding the copy from the
  /// server (now, or at the next sync when offline).
  Future<void> discard(OutboxItem item) async {
    store.removeOutbox(item.seq);
    store.setMeta(_rebuildKey, '1');
    await sync().catchError((Object _) {});
  }

  static const _rebuildKey = 'needs_rebuild';

  /// Server snapshot + the changes still waiting in the queue, re-applied locally.
  Future<void> _rebuild() async {
    final keepConfig = store.meta(_configKey);
    store.batch(() {
      store.clearAllRows();
      store.setMeta(_cursorKey, '0');
    });
    await pull();
    final who = actor();
    final cfg = config;
    if (who != null && cfg != null) {
      for (final item in pending) {
        try {
          store.batch(() => LocalOps.apply(
                OpContext(store: store, config: cfg, userId: who.id, userName: who.name, newId: () => const Uuid().v7()),
                matchOp(item.method, item.path)!,
                item.body,
              ));
        } on ApiException catch (e) {
          store.updateOutbox(item.copyWith(status: OutboxStatus.failed, errorCode: e.code, errorMessage: e.message));
        }
      }
    }
    if (keepConfig != null && store.meta(_configKey) == null) store.setMeta(_configKey, keepConfig);
    store.setMeta(_rebuildKey, null);
  }
}
