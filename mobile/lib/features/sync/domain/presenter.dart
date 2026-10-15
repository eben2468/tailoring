import 'dart:math';

import '../../../core/local/local_store.dart';
import 'config_bundle.dart';
import 'local_ops.dart';

/// Builds API-shaped JSON (the same shapes as the Laravel resources) from local rows, so screens and
/// models work identically online and offline. Hours, progress and flags follow the server's rules
/// (views v_task_hours / v_job_hours, JobResource). One instance per store snapshot: indexes are
/// built once.
class Presenter {
  Presenter(this.store, this.config, {DateTime? now, this.userId}) : now = (now ?? DateTime.now()).toUtc();

  final RowStore store;
  final ConfigBundle config;
  final DateTime now;

  /// The signed-in user (their running timer).
  final int? userId;

  static int _int(Object? v) => v is num ? v.toInt() : 0;

  static bool _alive(Map<String, dynamic> r) => r['deleted_at'] == null;

  late final Map<String, List<Map<String, dynamic>>> _tasksByJob = _group(Tables.tasks, 'job_id', sortBy: 'sort_order');
  late final Map<String, List<Map<String, dynamic>>> _logsByTask = _group(Tables.workLogs, 'job_task_id', includeDeleted: true);
  late final Map<String, List<Map<String, dynamic>>> _checklistByTask = _group(Tables.checklist, 'job_task_id', sortBy: 'sort_order');
  late final Map<String, List<Map<String, dynamic>>> _jobsByCustomer = _group(Tables.jobs, 'customer_id');
  late final Map<String, List<Map<String, dynamic>>> _setsByCustomer = _group(Tables.measurementSets, 'customer_id');
  late final Map<String, List<Map<String, dynamic>>> _stockByItem = _group(Tables.inventoryTransactions, 'item_id', includeDeleted: true);
  late final Map<String, List<Map<String, dynamic>>> _logsByTool = _group(Tables.toolLogs, 'tool_id');

  Map<String, List<Map<String, dynamic>>> _group(String table, String key, {String? sortBy, bool includeDeleted = false}) {
    final out = <String, List<Map<String, dynamic>>>{};
    for (final r in store.all(table)) {
      if (!includeDeleted && !_alive(r)) continue;
      (out[r[key] as String] ??= []).add(r);
    }
    if (sortBy != null) {
      for (final list in out.values) {
        list.sort((a, b) {
          final c = _int(a[sortBy]).compareTo(_int(b[sortBy]));
          return c != 0 ? c : (a['created_at'] as String? ?? '').compareTo(b['created_at'] as String? ?? '');
        });
      }
    }
    return out;
  }

  // ---------------------------------------------------------------- customers

  Map<String, dynamic> customer(Map<String, dynamic> row) {
    final jobs = _jobsByCustomer[row['id']] ?? const [];
    final sets = _setsByCustomer[row['id']] ?? const [];
    final lastMeasured = sets.map((s) => s['measured_at'] as String).fold<String?>(null, (m, v) => m == null || v.compareTo(m) > 0 ? v : m);
    return {
      ...row,
      'is_archived': row['archived_at'] != null,
      'summary': {
        'active_jobs': jobs.where((j) => const ['queued', 'in_progress', 'on_hold', 'ready_for_collection'].contains(j['status'])).length,
        'completed_jobs': jobs.where((j) => j['status'] == 'completed').length,
        'measurement_sets': sets.length,
        'last_measured_at': lastMeasured,
      },
    };
  }

  // ---------------------------------------------------------------- measurements

  Map<String, dynamic> measurementSet(Map<String, dynamic> row) {
    final unit = row['entered_unit'] as String? ?? 'in';
    final values = (row['values'] as List? ?? const []).cast<Map<String, dynamic>>().map((v) {
      final field = config.field(_int(v['field_id']));
      final cm = (v['value_cm'] as num?)?.toDouble();
      return {
        'field_id': v['field_id'],
        'code': field?['code'] ?? '',
        'label': field?['label'] ?? '',
        'group_id': field?['group_id'],
        'sort_order': (field?['group_order'] as int? ?? 0) * 1000 + (field?['sort_order'] as int? ?? 0),
        'value_cm': cm,
        'value': cm == null ? null : (unit == 'in' ? ((cm / 2.54) * 1000).round() / 1000 : cm),
        'value_text': v['value_text'],
      };
    }).toList();
    return {...row, 'values': values, 'values_count': values.length};
  }

  /// Newest first.
  List<Map<String, dynamic>> measurementHistory(String customerId) {
    final sets = [...?_setsByCustomer[customerId]]..sort((a, b) {
        final c = (b['measured_at'] as String).compareTo(a['measured_at'] as String);
        return c != 0 ? c : (b['created_at'] as String? ?? '').compareTo(a['created_at'] as String? ?? '');
      });
    return sets.map(measurementSet).toList();
  }

  /// Latest value of each field across all sets (v_customer_current_measurements).
  Map<String, dynamic> currentMeasurements(String customerId) {
    final latest = <int, Map<String, dynamic>>{};
    for (final set in measurementHistory(customerId).reversed) {
      for (final v in (set['values'] as List).cast<Map<String, dynamic>>()) {
        latest[_int(v['field_id'])] = {
          ...v,
          'value_type': config.field(_int(v['field_id']))?['value_type'] ?? 'length',
          'value_in': v['value_cm'] == null ? null : ((v['value_cm'] as double) / 2.54 * 1000).round() / 1000,
          'measurement_set_id': set['id'],
          'measured_at': set['measured_at'],
          'entered_unit': set['entered_unit'],
        };
      }
    }
    final values = latest.values.toList()..sort((a, b) => _int(a['sort_order']).compareTo(_int(b['sort_order'])));
    final customer = store.get(Tables.customers, customerId);
    return {
      'customer_id': customerId,
      'preferred_unit': customer?['preferred_unit'],
      'last_measured_at': values.isEmpty ? null : values.map((v) => v['measured_at'] as String).reduce((a, b) => a.compareTo(b) > 0 ? a : b),
      'values': values,
    };
  }

  // ---------------------------------------------------------------- jobs

  int _actual(String taskId) => (_logsByTask[taskId] ?? const [])
      .where((l) => _alive(l) && l['ended_at'] != null)
      .fold(0, (s, l) => s + DateTime.parse(l['ended_at'] as String).difference(DateTime.parse(l['started_at'] as String)).inSeconds);

  Map<String, dynamic> task(Map<String, dynamic> t) {
    final logs = (_logsByTask[t['id']] ?? const []).where(_alive).toList();
    final actual = _actual(t['id'] as String);
    final calc = Hours.task(status: t['status'] as String, estimated: _int(t['estimated_seconds']), actual: actual, override: (t['progress_override'] as num?)?.toDouble());
    final starts = logs.map((l) => l['started_at'] as String).toList()..sort();
    final ends = logs.map((l) => l['ended_at'] as String?).whereType<String>().toList()..sort();
    return {
      'id': t['id'],
      'task_type': config.taskType(_int(t['task_type_id'])) ?? {'id': t['task_type_id'], 'code': 'unknown', 'name': 'Stage', 'kind': 'work'},
      'name': t['task_name'],
      'sort_order': t['sort_order'],
      'status': t['status'],
      'estimated_seconds': _int(t['estimated_seconds']),
      'actual_seconds': actual,
      'remaining_seconds': calc.remaining,
      'overrun_seconds': calc.overrun,
      'progress_percent': calc.progress,
      'is_progress_manual': calc.manual,
      'is_running': logs.any((l) => l['ended_at'] == null),
      'log_count': logs.length,
      'actual_start': starts.firstOrNull,
      'actual_end': ends.lastOrNull,
      'scheduled_start': t['scheduled_start'],
      'scheduled_end': t['scheduled_end'],
      'completed_at': t['completed_at'],
      'notes': t['notes'],
      'checklist': [
        for (final i in _checklistByTask[t['id']] ?? const <Map<String, dynamic>>[])
          {'id': i['id'], 'label': i['label'], 'is_done': i['is_done'] == true, 'done_at': i['done_at'], 'sort_order': i['sort_order'], 'version': i['version']},
      ],
      'version': t['version'],
      'updated_at': t['updated_at'],
    };
  }

  Map<String, dynamic> job(Map<String, dynamic> j, {bool detail = false}) {
    final tasks = (_tasksByJob[j['id']] ?? const []).map(task).toList();
    final work = tasks.where((t) => (t['task_type'] as Map)['kind'] != 'milestone').toList();
    final h = Hours.job(
      jobStatus: j['status'] as String,
      override: (j['progress_override'] as num?)?.toDouble(),
      workTasks: [
        for (final t in work)
          (status: t['status'] as String, estimated: t['estimated_seconds'] as int, actual: t['actual_seconds'] as int, override: t['is_progress_manual'] == true ? t['progress_percent'] as double : null),
      ],
    );
    final visible = tasks.where((t) => t['status'] != 'skipped').toList();
    final current = visible.where((t) => t['status'] == 'in_progress').firstOrNull ?? visible.where((t) => t['status'] == 'pending').firstOrNull;
    final customer = store.get(Tables.customers, j['customer_id'] as String);
    final type = config.jobType(_int(j['job_type_id']));
    final set = j['measurement_set_id'] == null ? null : store.get(Tables.measurementSets, j['measurement_set_id'] as String);

    final out = <String, dynamic>{
      'id': j['id'],
      'job_number': j['job_number'],
      'title': j['title'],
      'quantity': j['quantity'],
      'priority': j['priority'],
      'status': j['status'],
      'status_label': JobStatusRules.label(j['status'] as String),
      'customer': {'id': j['customer_id'], 'full_name': customer?['full_name'] ?? 'Unknown customer', 'phone': customer?['phone']},
      'job_type': {'id': j['job_type_id'], 'name': type?['name'] ?? 'Garment', 'components': type?['components']},
      'order_date': j['order_date'],
      'due_date': j['due_date'],
      'collection_date': j['collection_date'],
      'completed_at': j['completed_at'],
      'hours': {
        'estimated_seconds': h.estimated,
        'actual_seconds': h.actual,
        'remaining_seconds': h.remaining,
        'overrun_seconds': h.overrun,
        'task_count': h.count,
        'completed_task_count': h.completed,
        'progress_percent': h.progress,
        'is_progress_manual': h.manual,
        'has_running_timer': work.any((t) => t['is_running'] == true),
        'actual_start': null,
      },
      'current_task': current == null
          ? null
          : {
              'id': current['id'],
              'name': current['name'],
              'status': current['status'],
              'kind': (current['task_type'] as Map)['kind'],
              'task_type_code': (current['task_type'] as Map)['code'],
              'task_type_name': (current['task_type'] as Map)['name'],
              'color_key': (current['task_type'] as Map)['color_key'],
            },
      'step': {'index': current == null ? visible.length : visible.indexOf(current) + 1, 'total': visible.length},
      'stages': [
        for (final t in visible) {'id': t['id'], 'name': t['name'], 'type_name': (t['task_type'] as Map)['name'], 'kind': (t['task_type'] as Map)['kind'], 'status': t['status']},
      ],
      'flags': _flags(j),
      'allowed_transitions': JobStatusRules.allowed(j['status'] as String),
      'version': j['version'],
      'created_at': j['created_at'],
      'updated_at': j['updated_at'],
    };
    if (!detail) return out;
    return {
      ...out,
      'description': j['description'],
      'fabric_note': j['fabric_note'],
      'notes': j['notes'],
      'cancel_reason': j['cancel_reason'],
      'progress_override': j['progress_override'],
      'measurement_set': set == null || !_alive(set) ? null : {'id': set['id'], 'measured_at': set['measured_at']},
      'tasks': tasks,
    };
  }

  Map<String, dynamic> _flags(Map<String, dynamic> j) {
    final due = j['due_date'] as String?;
    if (due == null) return {'is_overdue': false, 'is_due_soon': false, 'days_until_due': null};
    final today = DateTime.parse(businessToday(config, now));
    final days = DateTime.parse(due).difference(today).inDays;
    final inProduction = JobStatusRules.production.contains(j['status']);
    return {'is_overdue': inProduction && days < 0, 'is_due_soon': inProduction && days >= 0 && days <= config.dueSoonDays, 'days_until_due': days};
  }

  static const _open = ['draft', 'queued', 'in_progress', 'on_hold', 'ready_for_collection'];

  bool _matches(Map<String, dynamic> j, Map<String, dynamic> flags, String filter) {
    final s = j['status'];
    return switch (filter) {
      'open' => _open.contains(s),
      'active' => s == 'in_progress' || s == 'on_hold',
      'pending' => s == 'draft' || s == 'queued',
      'ready' => s == 'ready_for_collection',
      'due_soon' => flags['is_due_soon'] == true,
      'overdue' => flags['is_overdue'] == true,
      'completed' || 'cancelled' => s == filter,
      _ => true,
    };
  }

  bool _search(Map<String, dynamic> j, String q) {
    if (q.isEmpty) return true;
    final needle = q.toLowerCase();
    final number = q.replaceFirst('#', '');
    if (RegExp(r'^\d+$').hasMatch(number) && j['job_number'] != null && int.tryParse(j['job_number'] as String) == int.parse(number)) return true;
    final customer = store.get(Tables.customers, j['customer_id'] as String)?['full_name'] as String? ?? '';
    final type = config.jobType(_int(j['job_type_id']))?['name'] as String? ?? '';
    return (j['title'] as String).toLowerCase().contains(needle) || customer.toLowerCase().contains(needle) || type.toLowerCase().contains(needle);
  }

  /// GET /jobs equivalent: filter, search, customer, server ordering.
  List<Map<String, dynamic>> jobs({String filter = 'open', String query = '', String? customerId}) {
    final rows = store.all(Tables.jobs).where((j) => _alive(j) && (customerId == null || j['customer_id'] == customerId)).where((j) => _matches(j, _flags(j), filter) && _search(j, query)).toList();
    int priority(Map<String, dynamic> j) => const {'urgent': 0, 'high': 1}[j['priority']] ?? 2;
    final sort = switch (filter) {
      'completed' || 'cancelled' => 'recent',
      'any' => 'number',
      _ => 'due',
    };
    rows.sort((a, b) {
      switch (sort) {
        case 'recent':
          return (b['updated_at'] as String? ?? '').compareTo(a['updated_at'] as String? ?? '');
        case 'number':
          final c = (b['order_date'] as String).compareTo(a['order_date'] as String);
          return c != 0 ? c : (b['job_number'] as String? ?? '~').compareTo(a['job_number'] as String? ?? '~');
        default:
          final da = a['due_date'] as String?, db = b['due_date'] as String?;
          if (da == null || db == null) {
            if (da != db) return da == null ? 1 : -1;
          } else if (da != db) {
            return da.compareTo(db);
          }
          final p = priority(a).compareTo(priority(b));
          return p != 0 ? p : (b['job_number'] as String? ?? '~').compareTo(a['job_number'] as String? ?? '~');
      }
    });
    return rows.map((j) => job(j)).toList();
  }

  Map<String, int> jobCounts({String? customerId}) {
    final rows = store.all(Tables.jobs).where((j) => _alive(j) && (customerId == null || j['customer_id'] == customerId)).toList();
    return {
      for (final f in ['open', 'active', 'pending', 'ready', 'due_soon', 'overdue', 'completed', 'cancelled', 'any']) f: rows.where((j) => _matches(j, _flags(j), f)).length,
    };
  }

  // ---------------------------------------------------------------- appointments

  /// AppointmentResource + names the screens show.
  Map<String, dynamic> appointment(Map<String, dynamic> a) {
    final customer = a['customer_id'] == null ? null : store.get(Tables.customers, a['customer_id'] as String);
    final job = a['job_id'] == null ? null : store.get(Tables.jobs, a['job_id'] as String);
    return {
      ...a,
      'customer_name': customer?['full_name'],
      'customer_phone': customer?['phone'],
      'job_number': job?['job_number'],
      'job_title': job?['title'],
    };
  }

  // ---------------------------------------------------------------- work logs & timer

  Map<String, dynamic> workLog(Map<String, dynamic> l) {
    final start = DateTime.parse(l['started_at'] as String);
    final end = l['ended_at'] == null ? null : DateTime.parse(l['ended_at'] as String);
    return {
      'id': l['id'],
      'task_id': l['job_task_id'],
      'entry_type': l['entry_type'],
      'started_at': l['started_at'],
      'ended_at': l['ended_at'],
      'duration_seconds': (end ?? now).difference(start).inSeconds.clamp(0, 1 << 31),
      'is_running': end == null && _alive(l),
      'note': l['note'],
      'needs_review': l['needs_review'] == true,
      'is_voided': !_alive(l),
      'void_reason': l['void_reason'],
      'recorded_by': l['recorded_by'],
      'version': l['version'],
    };
  }

  /// Newest first, voided entries included.
  List<Map<String, dynamic>> workLogs(String taskId) =>
      [...?_logsByTask[taskId]]..sort((a, b) => (b['started_at'] as String).compareTo(a['started_at'] as String));

  /// The signed-in user's running session with what it is for (GET /timers/active `timer`).
  Map<String, dynamic>? activeTimer() {
    final log = store.all(Tables.workLogs).where((l) => l['ended_at'] == null && _alive(l) && _int(l['created_by']) == userId).firstOrNull;
    if (log == null) return null;
    final task = store.get(Tables.tasks, log['job_task_id'] as String);
    final job = task == null ? null : store.get(Tables.jobs, task['job_id'] as String);
    if (task == null || job == null) return null;
    return {
      ...workLog(log),
      'task': {
        'id': task['id'],
        'name': task['task_name'],
        'type_name': config.taskType(_int(task['task_type_id']))?['name'] ?? task['task_name'],
        'job_id': job['id'],
        'job_number': job['job_number'],
        'job_title': job['title'],
        'customer_name': store.get(Tables.customers, job['customer_id'] as String)?['full_name'] ?? '',
      },
    };
  }

  // ---------------------------------------------------------------- inventory

  /// First moment of this calendar month in the business timezone (Ghana: UTC).
  DateTime get _monthStart {
    final today = businessToday(config, now);
    final y = int.parse(today.substring(0, 4)), m = int.parse(today.substring(5, 7));
    return const {'Africa/Accra', 'Africa/Abidjan', 'UTC', 'Etc/UTC', 'GMT'}.contains(config.timezone) ? DateTime.utc(y, m) : DateTime(y, m).toUtc();
  }

  /// InventoryItemResource: the material with its stock from the ledger (InventoryStock rules).
  Map<String, dynamic> inventoryItem(Map<String, dynamic> row) {
    final ledger = _stockByItem[row['id']] ?? const [];
    final live = ledger.where(_alive).toList();
    final onHand = StockRules.onHand(live);
    final monthStart = iso(_monthStart);
    final last = live.map((t) => t['occurred_at'] as String).fold<String?>(null, (m, v) => m == null || v.compareTo(m) > 0 ? v : m);
    return {
      for (final key in const [
        'id', 'category_id', 'item_name', 'sku', 'description', 'unit', 'min_stock_level', 'reorder_quantity', 'unit_cost',
        'supplier_name', 'supplier_contact', 'storage_location', 'notes', 'archived_at', 'version', 'created_at', 'updated_at',
      ])
        key: row[key],
      'category_name': config.inventoryCategory(_int(row['category_id']))?['name'],
      'quantity_on_hand': onHand,
      'stock_status': StockRules.status(onHand, (row['min_stock_level'] as num? ?? 0).toDouble()),
      'last_transaction_at': last,
      'jobs_used_this_month': live
          .where((t) => t['transaction_type'] == 'usage' && t['job_id'] != null && (t['occurred_at'] as String).compareTo(monthStart) >= 0)
          .map((t) => t['job_id'])
          .toSet()
          .length,
    };
  }

  /// GET /inventory/items: active (or archived) materials by name.
  List<Map<String, dynamic>> inventoryItems({bool archived = false}) {
    final rows = store.all(Tables.inventoryItems).where((r) => _alive(r) && (r['archived_at'] != null) == archived).map(inventoryItem).toList()
      ..sort((a, b) => (a['item_name'] as String).toLowerCase().compareTo((b['item_name'] as String).toLowerCase()));
    return rows;
  }

  /// GET /inventory/summary.
  Map<String, dynamic> inventorySummary() {
    final items = inventoryItems();
    int count(String status) => items.where((i) => i['stock_status'] == status).length;
    const rank = {'negative': 0, 'out': 1, 'low': 2};
    final alerts = items.where((i) => i['stock_status'] != 'ok').toList()
      ..sort((a, b) {
        final c = rank[a['stock_status']]!.compareTo(rank[b['stock_status']]!);
        return c != 0 ? c : (a['item_name'] as String).toLowerCase().compareTo((b['item_name'] as String).toLowerCase());
      });
    final byCategory = <int, int>{};
    for (final i in items) {
      byCategory.update(_int(i['category_id']), (n) => n + 1, ifAbsent: () => 1);
    }
    return {
      'total_items': items.length,
      'category_count': byCategory.length,
      'low_stock': count('low'),
      'out_of_stock': count('out'),
      'negative': count('negative'),
      'stock_value': (items.fold<double>(0, (s, i) => i['unit_cost'] == null ? s : s + max(0.0, (i['quantity_on_hand'] as num).toDouble()) * (i['unit_cost'] as num).toDouble()) * 100).round() / 100,
      'valued_items': items.where((i) => i['unit_cost'] != null).length,
      'by_category': [for (final e in byCategory.entries) {'category_id': e.key, 'items': e.value}],
      'alerts': alerts,
    };
  }

  /// InventoryTransactionResource.
  Map<String, dynamic> inventoryTransaction(Map<String, dynamic> t) {
    final item = store.get(Tables.inventoryItems, t['item_id'] as String);
    final job = t['job_id'] == null ? null : store.get(Tables.jobs, t['job_id'] as String);
    return {
      'id': t['id'],
      'item_id': t['item_id'],
      'item_name': item?['item_name'],
      'unit': item?['unit'],
      'transaction_type': t['transaction_type'],
      'quantity_change': (t['quantity_change'] as num).toDouble(),
      'job_id': t['job_id'],
      'job_number': job?['job_number'],
      'unit_cost': (t['unit_cost'] as num?)?.toDouble(),
      'reference': t['reference'],
      'note': t['note'],
      'occurred_at': t['occurred_at'],
      'is_voided': !_alive(t),
      'void_reason': t['void_reason'],
      'recorded_by': t['recorded_by'],
      'version': t['version'],
      'created_at': t['created_at'],
    };
  }

  /// GET /inventory/items/{id}/transactions: newest first, voided lines included.
  List<Map<String, dynamic>> inventoryLedger(String itemId) => ([...?_stockByItem[itemId]]
        ..sort((a, b) {
          final c = (b['occurred_at'] as String).compareTo(a['occurred_at'] as String);
          return c != 0 ? c : (b['id'] as String).compareTo(a['id'] as String);
        }))
      .map(inventoryTransaction)
      .toList();

  /// GET /jobs/{id}/materials: what was used for (and returned from) a job, oldest first.
  List<Map<String, dynamic>> jobMaterials(String jobId) => (store.all(Tables.inventoryTransactions).where((t) => t['job_id'] == jobId && _alive(t)).toList()
        ..sort((a, b) => (a['occurred_at'] as String).compareTo(b['occurred_at'] as String)))
      .map(inventoryTransaction)
      .toList();

  // ---------------------------------------------------------------- tools

  /// ToolResource: the tool with its maintenance dates (ToolMaintenance rules).
  Map<String, dynamic> tool(Map<String, dynamic> row) {
    final logs = _logsByTool[row['id']] ?? const [];
    final last = logs.map((l) => l['performed_on'] as String).fold<String?>(null, (m, v) => m == null || v.compareTo(m) > 0 ? v : m);
    final next = MaintenanceRules.next(
      override: row['next_maintenance_override'] as String?,
      intervalDays: (row['maintenance_interval_days'] as num?)?.toInt(),
      last: last,
      purchaseDate: row['purchase_date'] as String?,
      createdDate: (row['created_at'] as String).substring(0, 10),
    );
    final state = MaintenanceRules.state(next, row['operational_status'] as String, businessToday(config, now), config.maintenanceDueSoonDays);
    return {
      for (final key in const [
        'id', 'category_id', 'tool_name', 'brand_model', 'serial_number', 'purchase_date', 'tool_condition', 'operational_status', 'storage_location',
        'maintenance_interval_days', 'next_maintenance_override', 'notes', 'archived_at', 'version', 'created_at', 'updated_at',
      ])
        key: row[key],
      'category_name': config.toolCategory(_int(row['category_id']))?['name'],
      'last_maintenance_date': last,
      'maintenance_count': logs.length,
      'next_maintenance_date': next,
      'maintenance_state': state.state,
      'days_until_due': state.days,
    };
  }

  /// GET /tools: active (or archived) tools by name.
  List<Map<String, dynamic>> tools({bool archived = false}) =>
      store.all(Tables.tools).where((r) => _alive(r) && (r['archived_at'] != null) == archived).map(tool).toList()
        ..sort((a, b) => (a['tool_name'] as String).toLowerCase().compareTo((b['tool_name'] as String).toLowerCase()));

  /// GET /tools/summary.
  Map<String, dynamic> toolSummary() {
    final all = tools();
    int status(String s) => all.where((t) => t['operational_status'] == s).length;
    int state(String s) => all.where((t) => t['maintenance_state'] == s).length;
    int? rank(Map<String, dynamic> t) => t['maintenance_state'] == 'overdue'
        ? 0
        : t['operational_status'] == 'out_of_service'
            ? 1
            : t['operational_status'] == 'needs_service'
                ? 2
                : t['maintenance_state'] == 'due_soon'
                    ? 3
                    : null;
    String key(Map<String, dynamic> t) => '${rank(t)}|${t['next_maintenance_date'] ?? '9999-12-31'}|${(t['tool_name'] as String).toLowerCase()}';
    final byCategory = <int, int>{};
    for (final t in all) {
      byCategory.update(_int(t['category_id']), (n) => n + 1, ifAbsent: () => 1);
    }
    return {
      'total_tools': all.length,
      'operational': status('operational'),
      'needs_service': status('needs_service'),
      'out_of_service': status('out_of_service'),
      'retired': status('retired'),
      'due_soon': state('due_soon'),
      'overdue': state('overdue'),
      'by_category': [for (final e in byCategory.entries) {'category_id': e.key, 'tools': e.value}],
      'alerts': all.where((t) => rank(t) != null).toList()..sort((a, b) => key(a).compareTo(key(b))),
    };
  }

  /// GET /tools/{id}/maintenance: newest first.
  List<Map<String, dynamic>> toolLogs(String toolId) => ([...?_logsByTool[toolId]]
        ..sort((a, b) {
          final c = (b['performed_on'] as String).compareTo(a['performed_on'] as String);
          return c != 0 ? c : (b['id'] as String).compareTo(a['id'] as String);
        }))
      .map((l) => {
            for (final key in const ['id', 'tool_id', 'performed_on', 'maintenance_type', 'description', 'performed_by', 'condition_after', 'recorded_by', 'version', 'created_at']) key: l[key],
          })
      .toList();

  // ---------------------------------------------------------------- notifications

  /// The signed-in user's notifications (GET /notifications), newest first.
  List<Map<String, dynamic>> notifications() => store.all(Tables.notifications).toList()
    ..sort((a, b) {
      final c = (b['created_at'] as String).compareTo(a['created_at'] as String);
      return c != 0 ? c : _int(b['id']).compareTo(_int(a['id']));
    });

  int unreadNotifications() => store.all(Tables.notifications).where((n) => n['read_at'] == null).length;

  // ---------------------------------------------------------------- dashboard

  static const _priorityRank = {'urgent': 0, 'high': 1};
  static const _weekdays = ['mon', 'tue', 'wed', 'thu', 'fri', 'sat', 'sun'];

  /// Today's opening hours (schedule.working_hours), null when closed.
  ({String open, String close})? _workingHours(DateTime businessNow) {
    final week = config.settings['schedule.working_hours'];
    final day = week is Map ? week[_weekdays[businessNow.weekday - 1]] : null;
    return day is Map && day['open'] is String && day['close'] is String ? (open: day['open'] as String, close: day['close'] as String) : null;
  }

  Map<String, dynamic>? _currentTask(String jobId) {
    final tasks = (_tasksByJob[jobId] ?? const []).where((t) => t['status'] != 'skipped');
    return tasks.where((t) => t['status'] == 'in_progress').firstOrNull ?? tasks.where((t) => t['status'] == 'pending').firstOrNull;
  }

  Map<String, dynamic> _taskType(Map<String, dynamic> t) => config.taskType(_int(t['task_type_id'])) ?? {'id': t['task_type_id'], 'name': 'Stage', 'kind': 'work', 'is_fitting': false, 'sort_order': 0};

  Map<String, dynamic> _scheduleTask(String kind, Map<String, dynamic> t, Map<String, dynamic> job, String? start, String? end) => {
        'kind': kind,
        'starts_at': start,
        'ends_at': end,
        'title': t['task_name'],
        'job_id': job['id'],
        'job_number': job['job_number'],
        'job_title': job['title'],
        'customer_name': store.get(Tables.customers, job['customer_id'] as String)?['full_name'] ?? 'Unknown customer',
        'task_id': t['id'],
        'appointment_id': null,
        'appointment_type': null,
        'location': null,
        'estimated_seconds': _int(t['estimated_seconds']),
        'remaining_seconds': task(t)['remaining_seconds'],
      };

  /// GET /dashboard (DashboardService rules).
  Map<String, dynamic> dashboard() {
    final local = businessClock(config, now);
    final today = businessToday(config, now);
    final dayStart = businessDayStart(config, today);
    final dayEnd = dayStart.add(const Duration(days: 1));
    bool isToday(String? at) {
      if (at == null) return false;
      final t = DateTime.parse(at);
      return !t.isBefore(dayStart) && t.isBefore(dayEnd);
    }

    const productionStatuses = JobStatusRules.production;
    final jobs = store.all(Tables.jobs).where((j) => _alive(j) && (productionStatuses.contains(j['status']) || j['status'] == 'ready_for_collection')).toList();
    final production = jobs.where((j) => productionStatuses.contains(j['status'])).toList();
    final hours = _workingHours(local);
    final time = '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';

    // Counts
    String? due(Map<String, dynamic> j) => j['due_date'] as String?;
    final sunday = DateTime.parse(today).add(Duration(days: 7 - local.weekday)).toIso8601String().substring(0, 10);
    final active = jobs.where((j) => j['status'] == 'in_progress' || j['status'] == 'on_hold').toList();
    final overdue = production.where((j) => due(j) != null && due(j)!.compareTo(today) < 0).toList();

    // Timed schedule: the running timer, stages planned for today, today's open appointments.
    final timed = <Map<String, dynamic>>[];
    final timer = activeTimer();
    final runningTask = (timer?['task'] as Map?)?['id'];
    if (timer != null) {
      final t = store.get(Tables.tasks, runningTask as String)!;
      timed.add(_scheduleTask('timer', t, store.get(Tables.jobs, t['job_id'] as String)!, timer['started_at'] as String, null));
    }
    for (final j in production) {
      for (final t in _tasksByJob[j['id']] ?? const <Map<String, dynamic>>[]) {
        if (!isToday(t['scheduled_start'] as String?) || t['status'] == 'completed' || t['status'] == 'skipped' || t['id'] == runningTask) continue;
        timed.add(_scheduleTask('stage', t, j, t['scheduled_start'] as String, t['scheduled_end'] as String?));
      }
    }
    for (final a in store.all(Tables.appointments)) {
      if (!_alive(a) || !(a['status'] == 'scheduled' || a['status'] == 'confirmed') || !isToday(a['starts_at'] as String)) continue;
      final job = a['job_id'] == null ? null : store.get(Tables.jobs, a['job_id'] as String);
      timed.add({
        'kind': 'appointment',
        'starts_at': a['starts_at'],
        'ends_at': a['ends_at'],
        'title': a['title'],
        'job_id': a['job_id'],
        'job_number': job?['job_number'],
        'job_title': job?['title'],
        'customer_name': a['customer_id'] == null ? null : store.get(Tables.customers, a['customer_id'] as String)?['full_name'],
        'task_id': null,
        'appointment_id': a['id'],
        'appointment_type': a['appointment_type'],
        'location': a['location'],
        'estimated_seconds': DateTime.parse(a['ends_at'] as String).difference(DateTime.parse(a['starts_at'] as String)).inSeconds,
        'remaining_seconds': null,
      });
    }
    String timedKey(Map<String, dynamic> i) => '${i['kind'] == 'timer' ? 0 : 1}|${i['starts_at']}|${i['kind'] == 'appointment' ? 1 : 0}|${i['title']}';
    timed.sort((a, b) => timedKey(a).compareTo(timedKey(b)));

    // Up next: the current stage of queued / in-progress jobs, in due order.
    final listed = timed.map((i) => i['task_id']).whereType<String>().toSet();
    String dueKey(Map<String, dynamic> j) => '${due(j) ?? '9999-12-31'}|${_priorityRank[j['priority']] ?? 2}|${j['job_number'] ?? '~'}';
    final next = <Map<String, dynamic>>[];
    for (final j in production.where((j) => j['status'] != 'on_hold').toList()..sort((a, b) => dueKey(a).compareTo(dueKey(b)))) {
      final t = _currentTask(j['id'] as String);
      if (t == null || _taskType(t)['kind'] == 'milestone' || listed.contains(t['id']) || task(t)['is_running'] == true) continue;
      next.add(_scheduleTask('next', t, j, null, null));
      if (next.length == 3) break;
    }

    // Workload: stages in progress, or planned for today, of queued and in-progress jobs.
    final byStage = <int, Map<String, dynamic>>{};
    for (final j in production.where((j) => j['status'] != 'on_hold')) {
      for (final t in _tasksByJob[j['id']] ?? const <Map<String, dynamic>>[]) {
        final type = _taskType(t);
        final planned = t['status'] == 'pending' && isToday(t['scheduled_start'] as String?);
        if (type['kind'] == 'milestone' || !(t['status'] == 'in_progress' || planned)) continue;
        final s = byStage.putIfAbsent(_int(type['id']), () => {'task_type_id': _int(type['id']), 'name': type['name'], 'color_key': type['color_key'], 'sort_order': _int(type['sort_order']), 'remaining_seconds': 0});
        s['remaining_seconds'] = (s['remaining_seconds'] as int) + (task(t)['remaining_seconds'] as int);
      }
    }
    final stages = byStage.values.toList()
      ..sort((a, b) {
        final c = (a['sort_order'] as int).compareTo(b['sort_order'] as int);
        return c != 0 ? c : (a['task_type_id'] as int).compareTo(b['task_type_id'] as int);
      });

    String priorityKey(Map<String, dynamic> j) => '${_priorityRank[j['priority']] ?? 2}|${due(j) ?? '9999-12-31'}|${j['job_number'] ?? '~'}';
    final materials = (inventorySummary()['alerts'] as List).cast<Map<String, dynamic>>();
    final service = (toolSummary()['alerts'] as List).cast<Map<String, dynamic>>();
    final appointments = timed.where((i) => i['kind'] == 'appointment').map((i) => i['appointment_type']).toList();

    return {
      'date': today,
      'shop': {'is_open': hours != null && time.compareTo(hours.open) >= 0 && time.compareTo(hours.close) < 0, 'opens_at': hours?.open, 'closes_at': hours?.close},
      'counts': {
        'open': store.all(Tables.jobs).where((j) => _alive(j) && _open.contains(j['status'])).length,
        'active': active.length,
        'at_fitting': active.where((j) {
          final t = _currentTask(j['id'] as String);
          return t != null && _taskType(t)['is_fitting'] == true;
        }).length,
        'queued': jobs.where((j) => j['status'] == 'queued').length,
        'ready_for_collection': jobs.where((j) => j['status'] == 'ready_for_collection').length,
        'due_today': production.where((j) => due(j) == today).length,
        'overdue': overdue.length,
        'most_days_late': overdue.isEmpty ? null : overdue.map((j) => DateTime.parse(today).difference(DateTime.parse(due(j)!)).inDays).reduce(max),
        'due_this_week': production.where((j) => due(j) != null && due(j)!.compareTo(today) >= 0 && due(j)!.compareTo(sunday) <= 0).length,
      },
      'appointments_today': {
        'total': appointments.length,
        'fittings': appointments.where((t) => t == 'fitting').length,
        'collections': appointments.where((t) => t == 'collection').length,
      },
      'workload': {
        'remaining_seconds': stages.fold<int>(0, (s, e) => s + (e['remaining_seconds'] as int)),
        'capacity_seconds': hours == null ? 0 : (((config.settings['schedule.capacity_hours_per_day'] as num?) ?? 8) * 3600).round(),
        'by_stage': [for (final s in stages) {...s}..remove('sort_order')],
      },
      'schedule': [...timed, ...next],
      'priority_jobs': (production..sort((a, b) => priorityKey(a).compareTo(priorityKey(b)))).take(3).map((j) => job(j)).toList(),
      'inventory_alert_count': materials.length,
      'inventory_alerts': materials.take(3).toList(),
      'maintenance_alert_count': service.length,
      'maintenance_alerts': service.take(3).toList(),
      'insights': insights().take(3).toList(),
    };
  }

  // ---------------------------------------------------------------- AI insights

  /// Active insight cards (new or seen, not past their time): critical first, then newest.
  List<Map<String, dynamic>> insights() {
    const rank = {'critical': 0, 'warning': 1, 'advice': 2, 'info': 3};
    final nowIso = iso(now);
    return store
        .all(Tables.insights)
        .where((i) => (i['insight_status'] == 'new' || i['insight_status'] == 'seen') && (i['expires_at'] == null || (i['expires_at'] as String).compareTo(nowIso) > 0))
        .toList()
      ..sort((a, b) {
        final c = (rank[a['severity']] ?? 3).compareTo(rank[b['severity']] ?? 3);
        return c != 0 ? c : (b['generated_at'] as String).compareTo(a['generated_at'] as String);
      });
  }
}
