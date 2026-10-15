import 'package:dio/dio.dart';
import 'package:nutofe/core/local/local_store.dart';
import 'package:nutofe/core/network/api_exception.dart';
import 'package:nutofe/features/sync/domain/config_bundle.dart';
import 'package:nutofe/features/sync/domain/local_ops.dart';

import 'fakes.dart';
import 'report_fixtures.dart';

/// In-memory stand-in for the Laravel API used by widget tests: /sync/pull, /sync/config and every
/// business write. Writes go through [LocalOps] (the app's copy of the server rules) on a server-side
/// store that numbers each change (sync_seq), so the app's real sync engine and screens are exercised
/// end to end. Server-only behaviour is added here: job numbers.
class FakeBackend {
  FakeBackend() {
    adapter = FakeAdapter(_handle);
  }

  late final FakeAdapter adapter;
  final requests = <String>[];

  /// The push token this phone registered (PUT /devices/current/push-token), null after DELETE.
  String? pushToken;
  final server = _SeqStore();
  late final jobs = FakeJobs(this);
  int _ids = 0;
  int _jobNumber = 23;

  static const userId = 1;

  String newId([String prefix = '0000']) => '0192f0a1-$prefix-7000-8000-${(++_ids).toString().padLeft(12, '0')}';

  static const groups = [
    {
      'id': 1,
      'code': 'upper_body',
      'name': 'Upper Body / Jacket & Shirt',
      'is_active': true,
      'fields': [
        {'id': 3, 'code': 'chest', 'label': 'Chest', 'value_type': 'length', 'choice_options': null, 'min_cm': 60, 'max_cm': 200, 'help_text': null, 'is_active': true},
        {'id': 4, 'code': 'waist', 'label': 'Waist (natural)', 'value_type': 'length', 'choice_options': null, 'min_cm': 50, 'max_cm': 200, 'help_text': null, 'is_active': true},
      ],
    },
    {
      'id': 3,
      'code': 'posture',
      'name': 'Posture & Fit',
      'is_active': true,
      'fields': [
        {'id': 20, 'code': 'shoulder_slope', 'label': 'Shoulder Slope', 'value_type': 'choice', 'choice_options': ['Level', 'Low left', 'Low right'], 'min_cm': null, 'max_cm': null, 'help_text': null, 'is_active': true},
      ],
    },
  ];

  static const taskTypes = [
    {'id': 1, 'code': 'measurement', 'name': 'Measurement', 'kind': 'work', 'is_fitting': false, 'color_key': 'slate', 'sort_order': 10, 'is_active': true},
    {'id': 2, 'code': 'cutting', 'name': 'Cutting', 'kind': 'work', 'is_fitting': false, 'color_key': 'blue', 'sort_order': 20, 'is_active': true},
    {'id': 3, 'code': 'sewing', 'name': 'Sewing', 'kind': 'work', 'is_fitting': false, 'color_key': 'blue', 'sort_order': 30, 'is_active': true},
    {'id': 4, 'code': 'fitting', 'name': 'Fitting', 'kind': 'work', 'is_fitting': true, 'color_key': 'teal', 'sort_order': 40, 'is_active': true},
    {'id': 6, 'code': 'finishing', 'name': 'Finishing', 'kind': 'work', 'is_fitting': false, 'color_key': 'indigo', 'sort_order': 60, 'is_active': true},
    {'id': 9, 'code': 'ready_for_collection', 'name': 'Ready for Collection', 'kind': 'milestone', 'is_fitting': false, 'color_key': 'green', 'sort_order': 90, 'is_active': true},
  ];

  static Map<String, dynamic> _type(int id) => taskTypes.firstWhere((t) => t['id'] == id);

  static Map<String, dynamic> _jobType(int id, String name, String components, List<(int, String?, double)> tasks) => {
        'id': id,
        'code': name.toLowerCase(),
        'name': name,
        'components': components,
        'description': null,
        'default_quantity': 1,
        'sort_order': id * 10,
        'is_active': true,
        'tasks': [
          for (final (i, t) in tasks.indexed)
            {'task_type': _type(t.$1), 'name': t.$2 ?? _type(t.$1)['name'], 'custom_name': t.$2, 'sort_order': i + 1, 'default_estimated_seconds': (t.$3 * 3600).round()},
        ],
      };

  late final configJson = <String, dynamic>{
    'config_version': 1,
    'settings': {
      'business.name': 'Nutɔfe',
      'business.timezone': 'Africa/Accra',
      'jobs.due_soon_days': 3,
      'timer.review_threshold_hours': 12,
      'schedule.capacity_hours_per_day': 8,
      'tools.maintenance_due_soon_days': 7,
      'schedule.working_hours': {'mon': {'open': '08:00', 'close': '18:00'}, 'tue': {'open': '08:00', 'close': '18:00'}, 'wed': {'open': '08:00', 'close': '18:00'}, 'thu': {'open': '08:00', 'close': '18:00'}, 'fri': {'open': '08:00', 'close': '18:00'}, 'sat': {'open': '09:00', 'close': '15:00'}, 'sun': null},
    },
    'task_types': taskTypes,
    'job_types': [
      _jobType(1, '3-Piece Suit', 'Jacket, Waistcoat & Trousers', [(1, 'Measurement & Pattern Drafting', 2.5), (2, 'Fabric Cutting', 3), (3, 'Sewing & Assembly', 6), (6, 'Finishing & Buttonholes', 2), (9, null, 0)]),
      _jobType(6, 'Kaftan', 'Top & Trousers', [(1, null, 0), (2, null, 0), (3, null, 0), (9, null, 0)]),
      _jobType(2, '2-Piece Suit', 'Jacket & Trousers', [(2, 'Fabric Cutting', 2), (4, 'Baste Fitting', 1), (3, 'Sewing & Assembly', 5), (9, null, 0)]),
    ],
    'measurement_groups': groups,
    'inventory_categories': [
      {'id': 1, 'name': 'Fabric', 'sort_order': 10, 'is_active': true},
      {'id': 2, 'name': 'Thread', 'sort_order': 20, 'is_active': true},
      {'id': 3, 'name': 'Buttons', 'sort_order': 30, 'is_active': true},
      {'id': 5, 'name': 'Linings', 'sort_order': 50, 'is_active': true},
      {'id': 9, 'name': 'Old stock', 'sort_order': 90, 'is_active': false},
    ],
    'tool_categories': [
      {'id': 1, 'name': 'Sewing Machines', 'sort_order': 10, 'is_active': true},
      {'id': 2, 'name': 'Irons & Pressing', 'sort_order': 20, 'is_active': true},
      {'id': 3, 'name': 'Cutting Tools', 'sort_order': 30, 'is_active': true},
    ],
  };

  late final ConfigBundle config = ConfigBundle.fromJson(configJson);

  OpContext _ctx({DateTime? now}) => OpContext(
        store: server,
        config: config,
        userId: userId,
        userName: 'Marcus Owner',
        newId: () => newId('aaaa'),
        now: now,
        nextJobNumber: () => (++_jobNumber).toString().padLeft(3, '0'),
      );

  /// Applies an API call to the server data (also used by tests to set the scene).
  void apply(String method, String path, Map<String, dynamic> body, {DateTime? now}) =>
      LocalOps.apply(_ctx(now: now), matchOp(method, path)!, body);

  // ---------------------------------------------------------------- scene helpers

  /// Rows as the server holds them.
  List<Map<String, dynamic>> get customers => server.all(Tables.customers).toList();

  List<Map<String, dynamic>> get sets => server.all(Tables.measurementSets).toList();

  Map<String, dynamic> addCustomer(String name, {String? phone, String? address, String? stylePreferences}) {
    final id = newId('cccc');
    apply('POST', '/customers', {'id': id, 'full_name': name, 'phone': phone, 'address': address, 'style_preferences': stylePreferences, 'allow_duplicate_phone': true});
    return server.get(Tables.customers, id)!;
  }

  /// A measurement set in cm ({field_id: cm}).
  void addSet(String customerId, Map<int, double> cmValues, {String unit = 'in', DateTime? at, String? notes, Map<int, String> texts = const {}}) {
    final id = newId('5555');
    final when = (at ?? DateTime.utc(2026, 10, 1)).toUtc();
    server.put(Tables.measurementSets, {
      'id': id,
      'customer_id': customerId,
      'measured_at': iso(when),
      'entered_unit': unit,
      'notes': notes,
      'supersedes_set_id': null,
      'created_by': userId,
      'recorded_by': 'Marcus Owusu',
      'created_at': iso(when),
      'deleted_at': null,
      'values': [
        for (final e in cmValues.entries) {'field_id': e.key, 'value_cm': e.value, 'value_text': null},
        for (final e in texts.entries) {'field_id': e.key, 'value_cm': null, 'value_text': e.value},
      ],
    });
  }

  /// An appointment at [start] (local time) for [minutes].
  Map<String, dynamic> addAppointment(String title, DateTime start, {int minutes = 60, String type = 'fitting', String? customerId, String? jobId, String? location, String status = 'scheduled'}) {
    final id = newId('9999');
    apply('POST', '/appointments', {
      'id': id,
      'appointment_type': type,
      'title': title,
      'customer_id': customerId,
      'job_id': jobId,
      'starts_at': start.toUtc().toIso8601String(),
      'ends_at': start.add(Duration(minutes: minutes)).toUtc().toIso8601String(),
      'location': location,
      'status': status,
      'allow_overlap': true,
    });
    return server.get(Tables.appointments, id)!;
  }

  /// A material with an opening balance of [stock] (none when 0).
  Map<String, dynamic> addMaterial(String name, {int categoryId = 1, String unit = 'm', double stock = 0, double min = 0, double? reorder, double? cost, String? location, String? sku}) {
    final id = newId('1111');
    apply('POST', '/inventory/items', {
      'id': id,
      'category_id': categoryId,
      'item_name': name,
      'unit': unit,
      'min_stock_level': min,
      'reorder_quantity': ?reorder,
      'unit_cost': ?cost,
      'storage_location': ?location,
      'sku': ?sku,
      if (stock > 0) 'opening_quantity': stock,
    });
    return server.get(Tables.inventoryItems, id)!;
  }

  /// Stock on hand as the server calculates it.
  double stockOf(String itemId) => StockRules.onHand(server.all(Tables.inventoryTransactions).where((t) => t['item_id'] == itemId));

  List<Map<String, dynamic>> transactionsOf(String itemId) => server.all(Tables.inventoryTransactions).where((t) => t['item_id'] == itemId).toList();

  /// A tool bought [boughtDaysAgo] days ago with a service cycle of [interval] days.
  Map<String, dynamic> addTool(String name,
      {int categoryId = 1, int? boughtDaysAgo, int? interval, String status = 'operational', String condition = 'good', String? location, String? brand}) {
    final id = newId('7777');
    apply('POST', '/tools', {
      'id': id,
      'category_id': categoryId,
      'tool_name': name,
      'brand_model': ?brand,
      'purchase_date': boughtDaysAgo == null ? null : MaintenanceRules.addDays(businessToday(config, DateTime.now()), -boughtDaysAgo),
      'maintenance_interval_days': interval,
      'operational_status': status,
      'tool_condition': condition,
      'storage_location': ?location,
    });
    return server.get(Tables.tools, id)!;
  }

  /// Maintenance logged [daysAgo] days ago.
  void logService(String toolId, int daysAgo, {String type = 'routine', String? description}) => apply('POST', '/tools/$toolId/maintenance', {
        'id': newId('8888'),
        'maintenance_type': type,
        'performed_on': MaintenanceRules.addDays(businessToday(config, DateTime.now()), -daysAgo),
        'description': ?description,
      });

  Map<String, dynamic> toolRow(String id) => server.get(Tables.tools, id)!;

  int _notificationId = 0;

  /// A notification for the signed-in user, created [minutesAgo] minutes ago.
  Map<String, dynamic> addNotification(String title, {String type = 'low_stock', String severity = 'warning', String? body, String? route, int minutesAgo = 5, bool read = false}) {
    final created = DateTime.now().toUtc().subtract(Duration(minutes: minutesAgo));
    final row = {
      'id': ++_notificationId,
      'notification_type': type,
      'severity': severity,
      'title': title,
      'body': body,
      'entity_type': null,
      'entity_id': null,
      'route': route,
      'read_at': read ? iso(created) : null,
      'created_at': iso(created),
    };
    server.put(Tables.notifications, row);
    return row;
  }

  Map<String, dynamic> notificationRow(int id) => server.get(Tables.notifications, '$id')!;

  int _insightId = 0;

  /// An AI insight card as the core API stores it.
  Map<String, dynamic> addInsight(String title, {String type = 'delay_risk', String severity = 'warning', String body = 'Body', Map<String, dynamic>? action, String status = 'new'}) {
    final row = {
      'id': ++_insightId,
      'insight_type': type,
      'severity': severity,
      'title': title,
      'body': body,
      'payload': {'action': ?action},
      'entity_type': null,
      'entity_id': null,
      'insight_status': status,
      'generated_at': iso(DateTime.now().toUtc().subtract(const Duration(minutes: 10))),
      'expires_at': iso(DateTime.now().toUtc().add(const Duration(hours: 30))),
      'updated_at': iso(DateTime.now().toUtc()),
    };
    server.put(Tables.insights, row);
    return row;
  }

  Map<String, dynamic> insightRow(int id) => server.get(Tables.insights, '$id')!;

  /// What the AI service answers (null = AI_UNAVAILABLE).
  Map<String, dynamic>? aiOverview = {
    'completed_jobs': 4,
    'accuracy': {'stages': 38, 'accuracy_percent': 92.3, 'within_10_percent': 71.4, 'bias_percent': 3.7, 'by_stage': [{'task_type_id': 3, 'name': 'Sewing', 'stages': 12, 'bias_percent': 12.5}]},
    'workload': {'from': '2026-10-12', 'to': '2026-10-18', 'capacity_seconds': 172800, 'demand_seconds': 145152, 'backlog_seconds': 180000, 'free_seconds': 27648, 'utilization_percent': 84.0, 'jobs_due': 3, 'state': 'optimal'},
    'risks': <Map<String, dynamic>>[],
    'queue': <Map<String, dynamic>>[],
    'stock': <Map<String, dynamic>>[],
    'llm': {'enabled': false, 'name': 'gemini-gemini-2.5-flash'},
  };

  /// Chat answers keyed by question.
  final aiAnswers = <String, String>{};

  /// Estimate per task type id (seconds) learned from history.
  final aiEstimates = <int, int>{};

  Map<String, dynamic>? aiForecast;

  FakeReply? _ai(RequestOptions r, String path) {
    FakeReply unavailable() => FakeReply.error(503, 'AI_UNAVAILABLE', 'The AI assistant cannot be reached right now. Everything else keeps working.');
    if (path.endsWith('/ai/overview')) return aiOverview == null ? unavailable() : FakeReply.ok(aiOverview);
    if (path.endsWith('/ai/chat')) {
      if (aiOverview == null) return unavailable();
      final messages = ((r.data as Map)['messages'] as List).cast<Map<String, dynamic>>();
      final q = messages.last['text'] as String;
      return FakeReply.ok({'answer': aiAnswers[q] ?? "I don't have data for that.", 'source': 'analytics', 'job_numbers': <String>[]});
    }
    if (path.endsWith('/ai/estimate')) {
      final type = config.jobType(((r.data as Map)['job_type_id'] as num).toInt())!;
      return FakeReply.ok({
        'tasks': [
          for (final t in (type['tasks'] as List).cast<Map<String, dynamic>>())
            if ((t['task_type'] as Map)['kind'] != 'milestone')
              {
                'task_type_id': (t['task_type'] as Map)['id'],
                'name': t['name'],
                'suggested_seconds': aiEstimates[(t['task_type'] as Map)['id']] ?? t['default_estimated_seconds'],
                'default_seconds': t['default_estimated_seconds'],
                'basis': aiEstimates.containsKey((t['task_type'] as Map)['id']) ? 'history' : 'defaults',
                'sample_size': aiEstimates.containsKey((t['task_type'] as Map)['id']) ? 5 : 0,
                'confidence': null,
                'explanation': '',
              },
        ],
      });
    }
    if (RegExp(r'/jobs/[^/]+/ai/forecast$').hasMatch(path)) return aiOverview == null ? unavailable() : FakeReply.ok(aiForecast);
    return null;
  }

  List<Map<String, dynamic>> logsOf(String toolId) => server.all(Tables.toolLogs).where((l) => l['tool_id'] == toolId && l['deleted_at'] == null).toList();

  List<Map<String, dynamic>> get appointments =>server.all(Tables.appointments).where((a) => a['deleted_at'] == null).toList();

  FakeReply _handle(RequestOptions r) {
    final path = r.path;
    requests.add('${r.method} $path');
    if (path.endsWith('/auth/me')) return FakeReply.ok({'user': userJson(), 'business': businessJson});
    if (path.endsWith('/sync/config')) return FakeReply.ok(configJson);
    if (path.endsWith('/devices/current/push-token')) {
      pushToken = r.method == 'PUT' ? (r.data as Map)['fcm_token'] as String : null;
      return FakeReply.ok(null);
    }
    final ai = _ai(r, path);
    if (ai != null) return ai;
    final report = RegExp(r'/reports/(\w+)$').firstMatch(path);
    if (report != null && r.method == 'GET') {
      return FakeReply.ok(reportFixture(report.group(1)!, from: '${r.queryParameters['from']}', to: '${r.queryParameters['to']}'));
    }
    if (path.endsWith('/tool-categories') && r.method == 'GET') {
      return FakeReply.ok([
        for (final c in (configJson['tool_categories'] as List).cast<Map<String, dynamic>>())
          {...c, 'item_count': server.all(Tables.tools).where((t) => t['category_id'] == c['id'] && t['archived_at'] == null).length},
      ]);
    }
    if (path.endsWith('/inventory/categories') && r.method == 'GET') {
      return FakeReply.ok([
        for (final c in (configJson['inventory_categories'] as List).cast<Map<String, dynamic>>())
          {...c, 'item_count': server.all(Tables.inventoryItems).where((i) => i['category_id'] == c['id'] && i['archived_at'] == null).length},
      ]);
    }
    if (path.endsWith('/sync/pull')) {
      final cursor = int.tryParse('${r.queryParameters['cursor'] ?? 0}') ?? 0;
      return FakeReply.ok({
        'cursor': server.seq,
        'has_more': false,
        'config_version': 1,
        'server_time': iso(DateTime.now()),
        'changes': {for (final t in Tables.all) t: server.changedSince(t, cursor)},
      });
    }

    final route = matchOp(r.method, path.replaceFirst(RegExp(r'^.*/api/v1'), ''));
    if (route == null) return FakeReply.error(404, 'NOT_FOUND', 'Unhandled fake route ${r.method} $path');
    try {
      LocalOps.apply(_ctx(), route, r.data is Map<String, dynamic> ? r.data as Map<String, dynamic> : const {});
      return FakeReply.ok(null, message: 'OK');
    } on ValidationException catch (e) {
      return FakeReply.error(422, e.code ?? 'VALIDATION_FAILED', e.message, errors: e.fieldErrors);
    } on ConflictException catch (e) {
      return FakeReply.error(409, e.code ?? 'CONFLICT', e.message);
    } on NotFoundException catch (e) {
      return FakeReply.error(404, 'NOT_FOUND', e.message);
    }
  }
}

/// Server rows with a change number per row (the server's sync_seq).
class _SeqStore extends MemoryRowStore {
  int seq = 0;

  @override
  void put(String table, Map<String, dynamic> row) => super.put(table, {...row, 'sync_seq': ++seq});

  List<Map<String, dynamic>> changedSince(String table, int cursor) =>
      all(table).where((r) => (r['sync_seq'] as int) > cursor).toList()..sort((a, b) => (a['sync_seq'] as int).compareTo(b['sync_seq'] as int));
}

/// Job and timer scene helpers on the fake server.
class FakeJobs {
  FakeJobs(this._b);

  final FakeBackend _b;

  List<Map<String, dynamic>> _tasks(String jobId) =>
      _b.server.all(Tables.tasks).where((t) => t['job_id'] == jobId && t['deleted_at'] == null).toList()..sort((a, b) => (a['sort_order'] as int).compareTo(b['sort_order'] as int));

  /// Jobs as the server holds them, each with its `tasks`.
  List<Map<String, dynamic>> get jobs => [
        for (final j in _b.server.all(Tables.jobs).where((j) => j['deleted_at'] == null)) {...j, 'tasks': _tasks(j['id'] as String)},
      ];

  /// The signed-in user's running session, or null.
  Map<String, dynamic>? get running => _b.server.all(Tables.workLogs).where((l) => l['ended_at'] == null && l['deleted_at'] == null).firstOrNull;

  /// Closed sessions and manual entries.
  List<Map<String, dynamic>> get logs => _b.server.all(Tables.workLogs).where((l) => l['ended_at'] != null && l['deleted_at'] == null).toList();

  /// A job from the garment template. [done] leading stages are completed (their estimate logged as
  /// work, unless [actualSeconds] says otherwise); in production the next stage is in progress.
  Map<String, dynamic> addJob(
    String customerId, {
    int jobTypeId = 1,
    String status = 'in_progress',
    String priority = 'normal',
    int? dueInDays,
    int done = 0,
    Map<int, int> actualSeconds = const {},
    List<String> checklist = const [],
    String? fabricNote = 'Navy Super 150s wool',
  }) {
    final id = _b.newId('bbbb');
    final today = DateTime.now().toUtc();
    String day(DateTime d) => iso(d).substring(0, 10);
    _b.apply('POST', '/jobs', {
      'id': id,
      'customer_id': customerId,
      'job_type_id': jobTypeId,
      'status': status == 'draft' ? 'draft' : 'queued',
      'priority': priority,
      'order_date': day(today.subtract(const Duration(days: 5))),
      'due_date': dueInDays == null ? null : day(today.add(Duration(days: dueInDays))),
      'fabric_note': fabricNote,
    });
    final tasks = _tasks(id);
    final logStart = today.subtract(const Duration(days: 4));
    for (final (i, t) in tasks.indexed) {
      if ((t['task_type_id'] as int) == 9) continue;
      final seconds = actualSeconds[i] ?? (i < done ? t['estimated_seconds'] as int : 0);
      if (seconds > 0) {
        final start = logStart.add(Duration(hours: i * 8));
        _b.server.put(Tables.workLogs, {
          'id': _b.newId('dddd'),
          'job_task_id': t['id'],
          'entry_type': 'timer',
          'started_at': iso(start),
          'ended_at': iso(start.add(Duration(seconds: seconds))),
          'note': null,
          'needs_review': false,
          'void_reason': null,
          'created_by': FakeBackend.userId,
          'recorded_by': 'Marcus Owner',
          'version': 1,
          'created_at': iso(start),
          'deleted_at': null,
        });
      }
      final taskStatus = i < done ? 'completed' : (i == done && status == 'in_progress' ? 'in_progress' : 'pending');
      _b.server.put(Tables.tasks, {...t, 'status': taskStatus, 'completed_at': i < done ? iso(logStart.add(Duration(hours: i * 8 + 4))) : null});
      if (i == done) {
        for (final (n, label) in checklist.indexed) {
          _b.server.put(Tables.checklist, {
            'id': _b.newId('eeee'),
            'job_task_id': t['id'],
            'label': label,
            'is_done': n == 0,
            'done_at': n == 0 ? iso(today) : null,
            'sort_order': n + 1,
            'version': 1,
            'created_at': iso(today),
            'deleted_at': null,
          });
        }
      }
    }
    if (status != 'draft' && status != 'queued') _b.server.put(Tables.jobs, {..._b.server.get(Tables.jobs, id)!, 'status': status});
    return jobs.firstWhere((j) => j['id'] == id);
  }

  /// Seconds of closed, non-voided work on a stage (what the server's v_task_hours counts).
  int actualSeconds(String taskId) => logs
      .where((l) => l['job_task_id'] == taskId)
      .fold(0, (s, l) => s + DateTime.parse(l['ended_at'] as String).difference(DateTime.parse(l['started_at'] as String)).inSeconds);

  /// A running timer on [taskId], started [elapsed] ago.
  void runTimer(String taskId, {Duration elapsed = const Duration(hours: 1)}) =>
      _b.apply('POST', '/tasks/$taskId/timer/start', {'id': _b.newId('ffff'), 'occurred_at': iso(DateTime.now().subtract(elapsed))});
}
