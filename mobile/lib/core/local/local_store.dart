import 'dart:async';
import 'dart:convert';

import 'package:sqlite3/sqlite3.dart';

/// Business tables mirrored on the device (same names and columns as the API's /sync/pull).
abstract final class Tables {
  static const customers = 'customers';
  static const measurementSets = 'measurement_sets';
  static const jobs = 'jobs';
  static const tasks = 'job_tasks';
  static const checklist = 'job_task_checklist_items';
  static const workLogs = 'work_logs';
  static const appointments = 'appointments';
  static const inventoryItems = 'inventory_items';
  static const inventoryTransactions = 'inventory_transactions';
  static const tools = 'tools';
  static const toolLogs = 'tool_maintenance_logs';

  /// Personal: the signed-in user's own notifications (numeric ids, no tombstones).
  static const notifications = 'notifications';

  /// AI insight cards (numeric ids; written by the server only).
  static const insights = 'ai_insights';

  static const all = [customers, measurementSets, jobs, tasks, checklist, workLogs, appointments, inventoryItems, inventoryTransactions, tools, toolLogs, notifications, insights];
}

/// Rows keyed by table and id. Tombstoned rows (deleted_at set) are kept, like on the server.
abstract class RowStore {
  Map<String, dynamic>? get(String table, String id);

  /// Every row of a table, tombstones included.
  Iterable<Map<String, dynamic>> all(String table);

  /// Inserts or replaces a row (by its `id`).
  void put(String table, Map<String, dynamic> row);
}

/// Rows held in memory. A tailoring business has thousands of rows, not millions: queries are
/// plain Dart over these maps (no SQL query layer, no code generation).
class MemoryRowStore implements RowStore {
  final Map<String, Map<String, Map<String, dynamic>>> _tables = {for (final t in Tables.all) t: {}};

  @override
  Map<String, dynamic>? get(String table, String id) => _tables[table]![id];

  @override
  Iterable<Map<String, dynamic>> all(String table) => _tables[table]!.values;

  @override
  void put(String table, Map<String, dynamic> row) => _tables[table]!["${row['id']}"] = row; // notification ids are numbers

  void clearRows() {
    for (final t in _tables.values) {
      t.clear();
    }
  }
}

/// One queued change made while offline: an API call replayed in order when the connection returns.
class OutboxItem {
  const OutboxItem({
    required this.seq,
    required this.op,
    required this.method,
    required this.path,
    required this.body,
    required this.label,
    required this.createdAt,
    this.status = OutboxStatus.pending,
    this.errorCode,
    this.errorMessage,
  });

  factory OutboxItem.fromJson(int seq, Map<String, dynamic> json) => OutboxItem(
        seq: seq,
        op: json['op'] as String,
        method: json['method'] as String,
        path: json['path'] as String,
        body: (json['body'] as Map).cast<String, dynamic>(),
        label: json['label'] as String,
        createdAt: DateTime.parse(json['created_at'] as String),
        status: OutboxStatus.values.byName(json['status'] as String? ?? 'pending'),
        errorCode: json['error_code'] as String?,
        errorMessage: json['error_message'] as String?,
      );

  final int seq;
  final String op;
  final String method;
  final String path;
  final Map<String, dynamic> body;

  /// What the owner did, in words ("Start timer on Sewing").
  final String label;
  final DateTime createdAt;
  final OutboxStatus status;
  final String? errorCode;
  final String? errorMessage;

  OutboxItem copyWith({OutboxStatus? status, String? errorCode, String? errorMessage, Map<String, dynamic>? body}) => OutboxItem(
        seq: seq,
        op: op,
        method: method,
        path: path,
        body: body ?? this.body,
        label: label,
        createdAt: createdAt,
        status: status ?? this.status,
        errorCode: errorCode,
        errorMessage: errorMessage,
      );

  Map<String, dynamic> toJson() => {
        'op': op,
        'method': method,
        'path': path,
        'body': body,
        'label': label,
        'created_at': createdAt.toUtc().toIso8601String(),
        'status': status.name,
        'error_code': errorCode,
        'error_message': errorMessage,
      };
}

/// pending: waiting to be sent · failed: the server refused it (conflict / validation) and the owner decides.
enum OutboxStatus { pending, failed }

/// The device's copy of the business data (ARCHITECTURE §21), persisted in SQLite (app-private storage).
/// Rows are stored as JSON and loaded into memory on start; every change is written through.
class LocalStore extends MemoryRowStore {
  LocalStore._(this._db) {
    _db.execute('''
      CREATE TABLE IF NOT EXISTS rows (tbl TEXT NOT NULL, id TEXT NOT NULL, data TEXT NOT NULL, PRIMARY KEY (tbl, id));
      CREATE TABLE IF NOT EXISTS meta (key TEXT PRIMARY KEY, value TEXT NOT NULL);
      CREATE TABLE IF NOT EXISTS outbox (seq INTEGER PRIMARY KEY AUTOINCREMENT, data TEXT NOT NULL);
    ''');
    for (final r in _db.select('SELECT tbl, data FROM rows')) {
      final table = r['tbl'] as String;
      if (Tables.all.contains(table)) super.put(table, (jsonDecode(r['data'] as String) as Map).cast<String, dynamic>());
    }
    for (final r in _db.select('SELECT key, value FROM meta')) {
      _meta[r['key'] as String] = r['value'] as String;
    }
    for (final r in _db.select('SELECT seq, data FROM outbox ORDER BY seq')) {
      _outbox.add(OutboxItem.fromJson(r['seq'] as int, (jsonDecode(r['data'] as String) as Map).cast<String, dynamic>()));
    }
  }

  /// Opens (or creates) the database file.
  factory LocalStore.open(String path) => LocalStore._(sqlite3.open(path));

  /// Tests and previews.
  factory LocalStore.memory() => LocalStore._(sqlite3.openInMemory());

  final Database _db;
  final Map<String, String> _meta = {};
  final List<OutboxItem> _outbox = [];
  final _changes = StreamController<void>.broadcast();
  int _batchDepth = 0;
  bool _dirty = false;

  /// Fires after every change (screens recompute from the store).
  Stream<void> get changes => _changes.stream;

  @override
  void put(String table, Map<String, dynamic> row) {
    super.put(table, row);
    _db.execute('INSERT OR REPLACE INTO rows (tbl, id, data) VALUES (?, ?, ?)', [table, '${row['id']}', jsonEncode(row)]);
    _changed();
  }

  /// Runs several writes in one SQLite transaction and notifies once.
  T batch<T>(T Function() body) {
    _batchDepth++;
    if (_batchDepth == 1) _db.execute('BEGIN');
    try {
      final result = body();
      if (_batchDepth == 1) _db.execute('COMMIT');
      return result;
    } catch (_) {
      if (_batchDepth == 1) _db.execute('ROLLBACK');
      rethrow;
    } finally {
      _batchDepth--;
      if (_batchDepth == 0 && _dirty) {
        _dirty = false;
        _changes.add(null);
      }
    }
  }

  String? meta(String key) => _meta[key];

  void setMeta(String key, String? value) {
    if (value == null) {
      _meta.remove(key);
      _db.execute('DELETE FROM meta WHERE key = ?', [key]);
    } else {
      _meta[key] = value;
      _db.execute('INSERT OR REPLACE INTO meta (key, value) VALUES (?, ?)', [key, value]);
    }
    _changed();
  }

  List<OutboxItem> get outbox => List.unmodifiable(_outbox);

  OutboxItem enqueue(OutboxItem item) {
    _db.execute('INSERT INTO outbox (data) VALUES (?)', [jsonEncode(item.toJson())]);
    final queued = OutboxItem.fromJson(_db.lastInsertRowId, item.toJson());
    _outbox.add(queued);
    _changed();
    return queued;
  }

  void updateOutbox(OutboxItem item) {
    final i = _outbox.indexWhere((o) => o.seq == item.seq);
    if (i < 0) return;
    _outbox[i] = item;
    _db.execute('UPDATE outbox SET data = ? WHERE seq = ?', [jsonEncode(item.toJson()), item.seq]);
    _changed();
  }

  void removeOutbox(int seq) {
    _outbox.removeWhere((o) => o.seq == seq);
    _db.execute('DELETE FROM outbox WHERE seq = ?', [seq]);
    _changed();
  }

  /// Removes every business row (kept: meta and the queue). Used to rebuild from the server.
  void clearAllRows() {
    clearRows();
    _db.execute('DELETE FROM rows');
    _changed();
  }

  /// Signing out (or another account signing in) removes the business data from the phone.
  void wipe() {
    batch(() {
      clearRows();
      _meta.clear();
      _outbox.clear();
      _db.execute('DELETE FROM rows; DELETE FROM meta; DELETE FROM outbox;');
      _changed();
    });
  }

  void _changed() {
    if (_batchDepth > 0) {
      _dirty = true;
    } else {
      _changes.add(null);
    }
  }

  void dispose() {
    _changes.close();
    _db.close();
  }
}
