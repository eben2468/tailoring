import '../../../core/local/local_store.dart';
import '../../../core/network/api_exception.dart';
import 'config_bundle.dart';

/// Applies one API mutation to a [RowStore] with the server's business rules (JobService,
/// JobTaskService, TimerService, CustomerService, MeasurementService). Used to show changes made
/// offline straight away; the server re-applies the same call when it is replayed and stays the
/// authority (its rows replace these on the next pull). Throws the same ApiExceptions as the API.
class OpContext {
  OpContext({
    required this.store,
    required this.config,
    required this.userId,
    required this.userName,
    required this.newId,
    DateTime? now,
    this.nextJobNumber,
  }) : now = (now ?? DateTime.now()).toUtc();

  final RowStore store;
  final ConfigBundle config;
  final int userId;
  final String userName;
  final DateTime now;
  final String Function() newId;

  /// The server assigns job numbers; the device leaves them empty (shown as "New") until it syncs.
  final String? Function()? nextJobNumber;

  String get nowIso => iso(now);
}

/// ISO-8601 UTC with milliseconds, like the API ("2026-10-08T09:15:00.000Z").
String iso(DateTime t) {
  final u = t.toUtc();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${u.year.toString().padLeft(4, '0')}-${two(u.month)}-${two(u.day)}T${two(u.hour)}:${two(u.minute)}:${two(u.second)}.${u.millisecond.toString().padLeft(3, '0')}Z';
}

/// Y-m-d of "today" in the business timezone. Ghana (Africa/Accra) is UTC+0 all year.
String businessToday(ConfigBundle config, DateTime now) {
  const utcZones = {'Africa/Accra', 'Africa/Abidjan', 'UTC', 'Etc/UTC', 'GMT', 'Europe/London'};
  final d = utcZones.contains(config.timezone) ? now.toUtc() : now.toLocal();
  return '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

/// [t] with its date and time fields in the business timezone (Ghana: UTC).
DateTime businessClock(ConfigBundle config, DateTime t) {
  const utcZones = {'Africa/Accra', 'Africa/Abidjan', 'UTC', 'Etc/UTC', 'GMT', 'Europe/London'};
  return utcZones.contains(config.timezone) ? t.toUtc() : t.toLocal();
}

/// The moment a business date (Y-m-d) starts, in UTC.
DateTime businessDayStart(ConfigBundle config, String date) {
  const utcZones = {'Africa/Accra', 'Africa/Abidjan', 'UTC', 'Etc/UTC', 'GMT', 'Europe/London'};
  final d = DateTime.parse(date);
  return utcZones.contains(config.timezone) ? DateTime.utc(d.year, d.month, d.day) : DateTime(d.year, d.month, d.day).toUtc();
}

/// "14:30" in the business timezone (Ghana: UTC).
String businessTime(ConfigBundle config, DateTime t) {
  const utcZones = {'Africa/Accra', 'Africa/Abidjan', 'UTC', 'Etc/UTC', 'GMT', 'Europe/London'};
  final d = utcZones.contains(config.timezone) ? t.toUtc() : t.toLocal();
  return '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}

/// "0241110001" / "233241110001" / "+233 24 111 0001" → "+233241110001" (Ghana), others as typed (digits).
String? normalizePhone(String? value) {
  if (value == null || value.trim().isEmpty) return null;
  final digits = value.replaceAll(RegExp(r'[^\d+]'), '');
  if (digits.startsWith('+')) return digits;
  if (digits.startsWith('00')) return '+${digits.substring(2)}';
  if (digits.startsWith('233')) return '+$digits';
  if (digits.startsWith('0') && digits.length == 10) return '+233${digits.substring(1)}';
  return digits;
}

/// The API mutation that a method + path stands for.
class OpRoute {
  const OpRoute(this.op, this.params);

  final String op;
  final List<String> params;
}

const _uuid = r'([0-9a-fA-F-]{36})';

final _routes = <(String, RegExp, String)>[
  ('POST', RegExp(r'^/customers$'), 'customer.create'),
  ('PATCH', RegExp('^/customers/$_uuid\$'), 'customer.update'),
  ('POST', RegExp('^/customers/$_uuid/archive\$'), 'customer.archive'),
  ('POST', RegExp('^/customers/$_uuid/unarchive\$'), 'customer.unarchive'),
  ('POST', RegExp('^/customers/$_uuid/measurements\$'), 'measurement.record'),
  ('DELETE', RegExp('^/measurement-sets/$_uuid\$'), 'measurement.discard'),
  ('POST', RegExp(r'^/jobs$'), 'job.create'),
  ('PATCH', RegExp('^/jobs/$_uuid\$'), 'job.update'),
  ('DELETE', RegExp('^/jobs/$_uuid\$'), 'job.delete'),
  ('POST', RegExp('^/jobs/$_uuid/status\$'), 'job.status'),
  ('POST', RegExp('^/jobs/$_uuid/progress-override\$'), 'job.progress'),
  ('POST', RegExp('^/jobs/$_uuid/tasks\$'), 'task.add'),
  ('PUT', RegExp('^/jobs/$_uuid/tasks/order\$'), 'task.reorder'),
  ('PATCH', RegExp('^/tasks/$_uuid\$'), 'task.update'),
  ('DELETE', RegExp('^/tasks/$_uuid\$'), 'task.delete'),
  ('POST', RegExp('^/tasks/$_uuid/status\$'), 'task.status'),
  ('POST', RegExp('^/tasks/$_uuid/progress-override\$'), 'task.progress'),
  ('POST', RegExp('^/tasks/$_uuid/checklist\$'), 'checklist.add'),
  ('PATCH', RegExp('^/checklist-items/$_uuid\$'), 'checklist.update'),
  ('DELETE', RegExp('^/checklist-items/$_uuid\$'), 'checklist.delete'),
  ('POST', RegExp('^/tasks/$_uuid/timer/start\$'), 'timer.start'),
  ('POST', RegExp(r'^/timers/stop$'), 'timer.stop'),
  ('POST', RegExp(r'^/timers/switch$'), 'timer.switch'),
  ('POST', RegExp('^/tasks/$_uuid/work-logs\$'), 'worklog.add'),
  ('PATCH', RegExp('^/work-logs/$_uuid\$'), 'worklog.update'),
  ('POST', RegExp('^/work-logs/$_uuid/void\$'), 'worklog.void'),
  ('POST', RegExp(r'^/appointments$'), 'appointment.create'),
  ('PATCH', RegExp('^/appointments/$_uuid\$'), 'appointment.update'),
  ('DELETE', RegExp('^/appointments/$_uuid\$'), 'appointment.delete'),
  ('POST', RegExp('^/appointments/$_uuid/status\$'), 'appointment.status'),
  ('POST', RegExp(r'^/inventory/items$'), 'inventory.create'),
  ('PATCH', RegExp('^/inventory/items/$_uuid\$'), 'inventory.update'),
  ('POST', RegExp('^/inventory/items/$_uuid/archive\$'), 'inventory.archive'),
  ('POST', RegExp('^/inventory/items/$_uuid/unarchive\$'), 'inventory.unarchive'),
  ('POST', RegExp('^/inventory/items/$_uuid/transactions\$'), 'inventory.record'),
  ('POST', RegExp('^/inventory/transactions/$_uuid/void\$'), 'inventory.void'),
  ('POST', RegExp(r'^/tools$'), 'tool.create'),
  ('PATCH', RegExp('^/tools/$_uuid\$'), 'tool.update'),
  ('POST', RegExp('^/tools/$_uuid/archive\$'), 'tool.archive'),
  ('POST', RegExp('^/tools/$_uuid/unarchive\$'), 'tool.unarchive'),
  ('POST', RegExp('^/tools/$_uuid/maintenance\$'), 'tool.maintenance'),
  ('DELETE', RegExp('^/tool-maintenance/$_uuid\$'), 'tool.maintenance_delete'),
  ('POST', RegExp(r'^/notifications/(\d+)/read$'), 'notification.read'),
  ('POST', RegExp(r'^/notifications/read-all$'), 'notification.read_all'),
  ('POST', RegExp(r'^/ai/insights/(\d+)/(seen|dismiss|applied)$'), 'insight.status'),
];

OpRoute? matchOp(String method, String path) {
  for (final (m, pattern, op) in _routes) {
    if (m != method) continue;
    final match = pattern.firstMatch(path);
    if (match != null) return OpRoute(op, [for (var i = 1; i <= match.groupCount; i++) match.group(i)!.toLowerCase()]);
  }
  return null;
}

abstract final class LocalOps {
  static void apply(OpContext c, OpRoute route, Map<String, dynamic> body) {
    final p = route.params;
    switch (route.op) {
      case 'customer.create':
        _customerCreate(c, body);
      case 'customer.update':
        _customerUpdate(c, p[0], body);
      case 'customer.archive' || 'customer.unarchive':
        _touch(c, Tables.customers, _require(c, Tables.customers, p[0]), {'archived_at': route.op == 'customer.archive' ? c.nowIso : null});
      case 'measurement.record':
        _measurementRecord(c, p[0], body);
      case 'measurement.discard':
        _touch(c, Tables.measurementSets, _require(c, Tables.measurementSets, p[0]), {'deleted_at': c.nowIso});
      case 'job.create':
        _jobCreate(c, body);
      case 'job.update':
        _jobUpdate(c, p[0], body);
      case 'job.delete':
        _jobDelete(c, p[0]);
      case 'job.status':
        _jobStatus(c, p[0], body);
      case 'job.progress':
        final job = _require(c, Tables.jobs, p[0]);
        _guardOpen(job);
        _touch(c, Tables.jobs, job, {'progress_override': (body['progress_percent'] as num?)?.toDouble()});
      case 'task.add':
        _taskAdd(c, p[0], body);
      case 'task.reorder':
        _taskReorder(c, p[0], (body['task_ids'] as List).cast<String>());
      case 'task.update':
        _taskUpdate(c, p[0], body);
      case 'task.delete':
        _taskDelete(c, p[0]);
      case 'task.status':
        _taskStatus(c, p[0], body['status'] as String, (body['version'] as num?)?.toInt());
      case 'task.progress':
        final task = _require(c, Tables.tasks, p[0]);
        _guardOpen(_jobOf(c, task));
        if (c.config.isMilestone(_int(task['task_type_id']))) throw _invalid('progress_percent', 'Milestones have no progress of their own.');
        _touch(c, Tables.tasks, task, {'progress_override': (body['progress_percent'] as num?)?.toDouble()});
      case 'checklist.add':
        _checklistAdd(c, p[0], body);
      case 'checklist.update':
        _checklistUpdate(c, p[0], body);
      case 'checklist.delete':
        final item = _require(c, Tables.checklist, p[0]);
        _guardOpen(_jobOf(c, _require(c, Tables.tasks, item['job_task_id'] as String)));
        _touch(c, Tables.checklist, item, {'deleted_at': c.nowIso});
      case 'timer.start':
        _timerStart(c, p[0], body['id'] as String?, _at(c, body));
      case 'timer.stop':
        _timerStop(c, body);
      case 'timer.switch':
        _timerSwitch(c, body);
      case 'worklog.add':
        _worklogAdd(c, p[0], body);
      case 'worklog.update':
        _worklogUpdate(c, p[0], body);
      case 'worklog.void':
        _touch(c, Tables.workLogs, _require(c, Tables.workLogs, p[0]), {'deleted_at': c.nowIso, 'void_reason': body['reason']});
      case 'appointment.create':
        _appointmentCreate(c, body);
      case 'appointment.update':
        _appointmentUpdate(c, p[0], body);
      case 'appointment.status':
        _appointmentStatus(c, p[0], body['status'] as String);
      case 'appointment.delete':
        _touch(c, Tables.appointments, _require(c, Tables.appointments, p[0]), {'deleted_at': c.nowIso});
      case 'inventory.create':
        _itemCreate(c, body);
      case 'inventory.update':
        _itemUpdate(c, p[0], body);
      case 'inventory.archive' || 'inventory.unarchive':
        final item = _require(c, Tables.inventoryItems, p[0]);
        final archive = route.op == 'inventory.archive';
        if ((item['archived_at'] != null) != archive) _touch(c, Tables.inventoryItems, item, {'archived_at': archive ? c.nowIso : null});
      case 'inventory.record':
        _stockRecord(c, p[0], body);
      case 'inventory.void':
        _stockVoid(c, p[0], body);
      case 'tool.create':
        _toolCreate(c, body);
      case 'tool.update':
        final tool = _require(c, Tables.tools, p[0]);
        _guardVersion(tool, body['version'], 'This tool was changed on another device. Reload to see the latest details.');
        _touch(c, Tables.tools, tool, _toolData(c, body, tool));
      case 'tool.archive' || 'tool.unarchive':
        final tool = _require(c, Tables.tools, p[0]);
        final archive = route.op == 'tool.archive';
        if ((tool['archived_at'] != null) != archive) _touch(c, Tables.tools, tool, {'archived_at': archive ? c.nowIso : null});
      case 'tool.maintenance':
        _toolMaintenance(c, p[0], body);
      case 'tool.maintenance_delete':
        final log = c.store.get(Tables.toolLogs, p[0]);
        if (log == null) throw const NotFoundException('The requested resource was not found.');
        if (log['deleted_at'] == null) _touch(c, Tables.toolLogs, log, {'deleted_at': c.nowIso});
      case 'notification.read':
        final n = c.store.get(Tables.notifications, p[0]);
        if (n == null) throw const NotFoundException('The requested resource was not found.');
        if (n['read_at'] == null) c.store.put(Tables.notifications, {...n, 'read_at': c.nowIso});
      case 'insight.status':
        // Like AiInsightService::setStatus: new → seen → applied | dismissed; never back, expired stays expired.
        final row = c.store.get(Tables.insights, p[0]);
        if (row == null) throw const NotFoundException('The requested resource was not found.');
        final status = switch (p[1]) {
          'dismiss' => 'dismissed',
          final s => s,
        };
        const rank = {'new': 0, 'seen': 1, 'applied': 2, 'dismissed': 2, 'expired': 3};
        final from = row['insight_status'] as String;
        if (from != 'expired' && (rank[from] ?? 0) < (rank[status] ?? 0)) c.store.put(Tables.insights, {...row, 'insight_status': status, 'updated_at': c.nowIso});
      case 'notification.read_all':
        for (final n in c.store.all(Tables.notifications).where((n) => n['read_at'] == null).toList()) {
          c.store.put(Tables.notifications, {...n, 'read_at': c.nowIso});
        }
      default:
        throw StateError('Unknown operation ${route.op}');
    }
  }

  // ---------------------------------------------------------------- customers & measurements

  static void _customerCreate(OpContext c, Map<String, dynamic> body) {
    final id = body['id'] as String;
    if (c.store.get(Tables.customers, id) != null) return; // idempotent retry
    final phone = normalizePhone(body['phone'] as String?);
    if (body['allow_duplicate_phone'] != true) _guardDuplicatePhone(c, phone, null);
    c.store.put(Tables.customers, {
      'id': id,
      'full_name': (body['full_name'] as String).trim(),
      'phone': phone,
      'phone_alt': normalizePhone(body['phone_alt'] as String?),
      'email': (body['email'] as String?)?.toLowerCase(),
      'address': body['address'],
      'notes': body['notes'],
      'style_preferences': body['style_preferences'],
      'preferred_unit': body['preferred_unit'],
      'archived_at': null,
      'version': 1,
      'created_at': c.nowIso,
      'updated_at': c.nowIso,
      'deleted_at': null,
    });
  }

  static void _customerUpdate(OpContext c, String id, Map<String, dynamic> body) {
    final row = _require(c, Tables.customers, id);
    _guardVersion(row, body['version'], 'This customer was changed on another device. Reload to see the latest details.');
    final changes = <String, dynamic>{};
    for (final key in ['full_name', 'phone', 'phone_alt', 'email', 'address', 'notes', 'style_preferences', 'preferred_unit']) {
      if (body.containsKey(key)) changes[key] = body[key];
    }
    if (changes.containsKey('phone')) changes['phone'] = normalizePhone(changes['phone'] as String?);
    if (changes.containsKey('phone_alt')) changes['phone_alt'] = normalizePhone(changes['phone_alt'] as String?);
    if (changes['email'] is String) changes['email'] = (changes['email'] as String).toLowerCase();
    if (body['allow_duplicate_phone'] != true && changes['phone'] != null) _guardDuplicatePhone(c, changes['phone'] as String, id);
    _touch(c, Tables.customers, row, changes);
  }

  static void _guardDuplicatePhone(OpContext c, String? phone, String? exceptId) {
    if (phone == null) return;
    final matches = c.store
        .all(Tables.customers)
        .where((r) => r['deleted_at'] == null && r['id'] != exceptId && (r['phone'] == phone || r['phone_alt'] == phone))
        .map((r) => r['full_name'] as String)
        .toList()
      ..sort();
    if (matches.isNotEmpty) {
      final names = matches.length == 1 ? matches.first : '${matches.sublist(0, matches.length - 1).join(', ')} and ${matches.last}';
      throw ConflictException('This phone number is already used by $names.', code: 'DUPLICATE_PHONE');
    }
  }

  static void _measurementRecord(OpContext c, String customerId, Map<String, dynamic> body) {
    final id = body['id'] as String;
    if (c.store.get(Tables.measurementSets, id) != null) return;
    _require(c, Tables.customers, customerId);
    final unit = body['entered_unit'] as String;
    final values = <Map<String, dynamic>>[];
    final errors = <String, List<String>>{};
    for (final (i, v) in (body['values'] as List).cast<Map<String, dynamic>>().indexed) {
      final field = c.config.field(_int(v['field_id']));
      if (field == null || field['is_active'] == false) {
        errors['values.$i.field_id'] = ['This measurement field does not exist or is no longer used.'];
        continue;
      }
      if (field['value_type'] == 'length') {
        final raw = (v['value'] as num?)?.toDouble();
        if (raw == null || raw <= 0) {
          errors['values.$i.value'] = ['${field['label']} needs a positive number.'];
          continue;
        }
        final cm = ((unit == 'in' ? raw * 2.54 : raw) * 1000).roundToDouble() / 1000;
        final min = (field['min_cm'] as num?)?.toDouble();
        final max = (field['max_cm'] as num?)?.toDouble();
        if ((min != null && cm < min) || (max != null && cm > max)) {
          String fmt(double? cmValue, double fallback) {
            final x = (cmValue ?? fallback) / (unit == 'in' ? 2.54 : 1);
            return x.toStringAsFixed(2).replaceFirst(RegExp(r'\.?0+$'), '');
          }

          errors['values.$i.value'] = ['${field['label']} must be between ${fmt(min, 0)} and ${fmt(max, 999)} $unit.'];
          continue;
        }
        values.add({'field_id': field['id'], 'value_cm': cm, 'value_text': null});
      } else {
        final text = (v['value_text'] as String? ?? '').trim();
        if (text.isEmpty) {
          errors['values.$i.value_text'] = ['${field['label']} needs a value.'];
          continue;
        }
        values.add({'field_id': field['id'], 'value_cm': null, 'value_text': text});
      }
    }
    if (errors.isNotEmpty) throw ValidationException('Some measurements are invalid.', errors, code: 'VALIDATION_FAILED');
    c.store.put(Tables.measurementSets, {
      'id': id,
      'customer_id': customerId,
      'measured_at': body['measured_at'] ?? c.nowIso,
      'entered_unit': unit,
      'notes': body['notes'],
      'supersedes_set_id': body['supersedes_set_id'],
      'created_by': c.userId,
      'recorded_by': c.userName,
      'created_at': c.nowIso,
      'deleted_at': null,
      'values': values,
    });
  }

  // ---------------------------------------------------------------- jobs

  static void _jobCreate(OpContext c, Map<String, dynamic> body) {
    final id = body['id'] as String;
    if (c.store.get(Tables.jobs, id) != null) return;
    final customer = c.store.get(Tables.customers, body['customer_id'] as String);
    if (customer == null || customer['deleted_at'] != null) throw _invalid('customer_id', 'This customer does not exist.');
    if (customer['archived_at'] != null) throw _invalid('customer_id', 'This customer is archived. Restore them before creating a job.');
    final type = c.config.jobType(_int(body['job_type_id']));
    if (type == null || type['is_active'] == false) throw _invalid('job_type_id', 'Choose an active garment type.');

    final setId = body['measurement_set_id'] as String?;
    if (setId != null && c.store.get(Tables.measurementSets, setId)?['customer_id'] != customer['id']) {
      throw _invalid('measurement_set_id', "These measurements don't belong to this customer.");
    }
    final orderDate = body['order_date'] as String? ?? businessToday(c.config, c.now);
    _guardDates(orderDate, body['due_date'] as String?, body['collection_date'] as String?);

    final requested = (body['tasks'] as List?)?.cast<Map<String, dynamic>>();
    final templates = (type['tasks'] as List).cast<Map<String, dynamic>>();
    final planned = [
      if (requested != null)
        for (final t in requested) (id: t['id'] as String?, typeId: _int(t['task_type_id']), name: t['task_name'] as String?, seconds: _int(t['estimated_seconds']))
      else
        for (final t in templates)
          (id: null, typeId: _int((t['task_type'] as Map)['id']), name: t['name'] as String?, seconds: _int(t['default_estimated_seconds'])),
    ];
    for (final (i, t) in planned.indexed) {
      final taskType = c.config.taskType(t.typeId);
      if (taskType == null || taskType['is_active'] == false) throw _invalid('tasks.$i.task_type_id', 'This production stage does not exist or is no longer used.');
    }

    final title = (body['title'] as String?)?.trim();
    c.store.put(Tables.jobs, {
      'id': id,
      'job_number': c.nextJobNumber?.call(),
      'customer_id': customer['id'],
      'job_type_id': type['id'],
      'title': title == null || title.isEmpty ? type['name'] : title,
      'description': body['description'],
      'quantity': body['quantity'] ?? type['default_quantity'] ?? 1,
      'priority': body['priority'] ?? 'normal',
      'status': body['status'] ?? 'queued',
      'order_date': orderDate,
      'due_date': body['due_date'],
      'collection_date': body['collection_date'],
      'measurement_set_id': setId,
      'fabric_note': body['fabric_note'],
      'progress_override': null,
      'notes': body['notes'],
      'cancel_reason': null,
      'completed_at': null,
      'version': 1,
      'created_at': c.nowIso,
      'updated_at': c.nowIso,
      'deleted_at': null,
    });
    for (final (i, t) in planned.indexed) {
      final taskType = c.config.taskType(t.typeId)!;
      final name = t.name?.trim();
      c.store.put(Tables.tasks, {
        'id': t.id ?? c.newId(),
        'job_id': id,
        'task_type_id': t.typeId,
        'task_name': name == null || name.isEmpty ? taskType['name'] : name,
        'sort_order': i + 1,
        'status': 'pending',
        'estimated_seconds': taskType['kind'] == 'milestone' ? 0 : t.seconds,
        'progress_override': null,
        'scheduled_start': null,
        'scheduled_end': null,
        'completed_at': null,
        'notes': null,
        'version': 1,
        'updated_at': c.nowIso,
        'deleted_at': null,
      });
    }
  }

  static void _jobUpdate(OpContext c, String id, Map<String, dynamic> body) {
    final job = _require(c, Tables.jobs, id);
    _guardVersion(job, body['version'], 'This job was changed on another device. Reload to see the latest details.');
    _guardOpen(job);
    final changes = <String, dynamic>{};
    for (final key in ['title', 'description', 'quantity', 'priority', 'order_date', 'due_date', 'collection_date', 'fabric_note', 'notes', 'measurement_set_id']) {
      if (body.containsKey(key)) changes[key] = body[key];
    }
    if (changes['measurement_set_id'] case final String setId when c.store.get(Tables.measurementSets, setId)?['customer_id'] != job['customer_id']) {
      throw _invalid('measurement_set_id', "These measurements don't belong to this customer.");
    }
    final merged = {...job, ...changes};
    _guardDates(merged['order_date'] as String, merged['due_date'] as String?, merged['collection_date'] as String?);
    _touch(c, Tables.jobs, job, changes);
  }

  static void _jobDelete(OpContext c, String id) {
    final job = _require(c, Tables.jobs, id);
    if (job['status'] != 'draft') throw const ConflictException('Only draft jobs can be deleted. Cancel this job instead.', code: 'JOB_NOT_DRAFT');
    for (final task in _tasksOf(c, id)) {
      for (final item in _checklistOf(c, task['id'] as String)) {
        _touch(c, Tables.checklist, item, {'deleted_at': c.nowIso});
      }
      _touch(c, Tables.tasks, task, {'deleted_at': c.nowIso});
    }
    _touch(c, Tables.jobs, job, {'deleted_at': c.nowIso});
  }

  static void _jobStatus(OpContext c, String id, Map<String, dynamic> body) {
    final job = _require(c, Tables.jobs, id);
    final from = job['status'] as String;
    final to = body['status'] as String;
    if (body['version'] != null) _guardVersion(job, body['version'], 'This job was changed on another device. Reload to see the latest details.');
    if (from == to) return;
    if (!JobStatusRules.allowed(from).contains(to)) {
      throw ConflictException(
        'A job that is ${JobStatusRules.label(from).toLowerCase()} cannot be changed to ${JobStatusRules.label(to).toLowerCase()}.',
        code: 'INVALID_STATUS_TRANSITION',
      );
    }
    final reason = (body['reason'] as String?)?.trim() ?? '';
    if (to == 'cancelled' && reason.isEmpty) throw _invalid('reason', 'Give a reason for cancelling this job.');
    final tasks = _tasksOf(c, id);
    if (['on_hold', 'ready_for_collection', 'completed', 'cancelled'].contains(to) && tasks.any((t) => _runningLogOf(c, t['id'] as String) != null)) {
      throw const ConflictException('A work timer is running on this job. Stop it first.', code: 'TIMER_RUNNING');
    }
    if (to == 'ready_for_collection' && body['force'] != true) {
      final unfinished = tasks.where((t) => !c.config.isMilestone(_int(t['task_type_id'])) && !_closed(t)).toList();
      if (unfinished.isNotEmpty) {
        final names = unfinished.map((t) => t['task_name'] as String).toList();
        final joined = names.length == 1 ? names.first : '${names.sublist(0, names.length - 1).join(', ')} and ${names.last}';
        throw ConflictException('${names.length} ${names.length == 1 ? 'stage is' : 'stages are'} not finished yet: $joined.', code: 'TASKS_INCOMPLETE');
      }
    }
    _touch(c, Tables.jobs, job, {
      'status': to,
      'completed_at': to == 'completed' ? c.nowIso : null,
      if (to == 'cancelled') 'cancel_reason': reason,
    });
    // Milestones follow the job status.
    final reached = switch (to) {
      'ready_for_collection' => ['ready_for_collection'],
      'completed' => ['ready_for_collection', 'completed'],
      'cancelled' => null,
      _ => <String>[],
    };
    if (reached == null) return;
    for (final t in tasks.where((t) => c.config.isMilestone(_int(t['task_type_id'])))) {
      final done = reached.contains(c.config.taskType(_int(t['task_type_id']))?['code']);
      if (done && t['status'] != 'completed') _touch(c, Tables.tasks, t, {'status': 'completed', 'completed_at': c.nowIso});
      if (!done && t['status'] == 'completed') _touch(c, Tables.tasks, t, {'status': 'pending', 'completed_at': null});
    }
  }

  static void _startProductionIfIdle(OpContext c, Map<String, dynamic> job) {
    if (job['status'] == 'queued' || job['status'] == 'on_hold') _touch(c, Tables.jobs, job, {'status': 'in_progress'});
  }

  // ---------------------------------------------------------------- tasks & checklist

  static void _taskAdd(OpContext c, String jobId, Map<String, dynamic> body) {
    final id = body['id'] as String? ?? c.newId();
    if (c.store.get(Tables.tasks, id) != null) return;
    final job = _require(c, Tables.jobs, jobId);
    _guardOpen(job);
    final type = c.config.taskType(_int(body['task_type_id']));
    if (type == null || type['is_active'] == false) throw _invalid('task_type_id', 'This production stage does not exist or is no longer used.');
    final tasks = _tasksOf(c, jobId);
    var position = tasks.length;
    if (type['kind'] != 'milestone') {
      while (position > 0 && c.config.isMilestone(_int(tasks[position - 1]['task_type_id']))) {
        position--;
      }
    }
    final name = (body['task_name'] as String?)?.trim();
    c.store.put(Tables.tasks, {
      'id': id,
      'job_id': jobId,
      'task_type_id': type['id'],
      'task_name': name == null || name.isEmpty ? type['name'] : name,
      'sort_order': position + 1,
      'status': 'pending',
      'estimated_seconds': type['kind'] == 'milestone' ? 0 : _int(body['estimated_seconds']),
      'progress_override': null,
      'scheduled_start': null,
      'scheduled_end': null,
      'completed_at': null,
      'notes': body['notes'],
      'version': 1,
      'updated_at': c.nowIso,
      'deleted_at': null,
    });
    for (final (i, later) in tasks.sublist(position).indexed) {
      _setSort(c, later, position + i + 2);
    }
  }

  static void _taskReorder(OpContext c, String jobId, List<String> ids) {
    _guardOpen(_require(c, Tables.jobs, jobId));
    final tasks = {for (final t in _tasksOf(c, jobId)) t['id'] as String: t};
    final wanted = ids.map((i) => i.toLowerCase()).toList();
    if (wanted.toSet().length != wanted.length || wanted.length != tasks.length || !wanted.every(tasks.containsKey)) {
      throw _invalid('task_ids', 'Send every task of this job exactly once.');
    }
    for (final (i, id) in wanted.indexed) {
      _setSort(c, tasks[id]!, i + 1);
    }
  }

  static void _taskUpdate(OpContext c, String id, Map<String, dynamic> body) {
    final task = _require(c, Tables.tasks, id);
    _guardOpen(_jobOf(c, task));
    _guardVersion(task, body['version'], 'This stage was changed on another device. Reload to see the latest details.');
    final changes = <String, dynamic>{};
    for (final key in ['task_name', 'estimated_seconds', 'notes', 'scheduled_start', 'scheduled_end']) {
      if (body.containsKey(key)) changes[key] = body[key];
    }
    if (_int(changes['estimated_seconds']) > 0 && c.config.isMilestone(_int(task['task_type_id']))) {
      throw _invalid('estimated_seconds', 'Milestones such as "Ready for Collection" have no hours.');
    }
    for (final key in ['scheduled_start', 'scheduled_end']) {
      if (changes[key] is String) changes[key] = iso(DateTime.parse(changes[key] as String));
    }
    final start = (changes.containsKey('scheduled_start') ? changes['scheduled_start'] : task['scheduled_start']) as String?;
    final end = (changes.containsKey('scheduled_end') ? changes['scheduled_end'] : task['scheduled_end']) as String?;
    if (end != null && (start == null || end.compareTo(start) <= 0)) throw _invalid('scheduled_end', 'The planned end must be after the planned start.');
    _touch(c, Tables.tasks, task, changes);
  }

  static void _taskDelete(OpContext c, String id) {
    final task = _require(c, Tables.tasks, id);
    final job = _jobOf(c, task);
    _guardOpen(job);
    if (_logsOf(c, id).isNotEmpty) throw const ConflictException('This stage has logged hours, so it cannot be deleted. Skip it instead.', code: 'TASK_HAS_WORK');
    for (final item in _checklistOf(c, id)) {
      _touch(c, Tables.checklist, item, {'deleted_at': c.nowIso});
    }
    _touch(c, Tables.tasks, task, {'deleted_at': c.nowIso});
    for (final (i, t) in _tasksOf(c, job['id'] as String).indexed) {
      _setSort(c, t, i + 1);
    }
  }

  static void _taskStatus(OpContext c, String id, String status, int? version) {
    final task = _require(c, Tables.tasks, id);
    final job = _jobOf(c, task);
    if (version != null) _guardVersion(task, version, 'This stage was changed on another device. Reload to see the latest details.');
    if (c.config.isMilestone(_int(task['task_type_id']))) throw _invalid('status', 'This milestone follows the job status. Change the job status instead.');
    if (task['status'] == status) return;
    if (!JobStatusRules.production.contains(job['status'])) {
      throw ConflictException(
        switch (job['status']) {
          'draft' => 'Queue this job for production before working on its stages.',
          'ready_for_collection' => 'This job is ready for collection. Move it back to production to change its stages.',
          _ => 'This job is ${JobStatusRules.label(job['status'] as String).toLowerCase()} and can no longer be changed.',
        },
        code: 'JOB_NOT_IN_PRODUCTION',
      );
    }
    if ((status == 'completed' || status == 'skipped') && _runningLogOf(c, id) != null) {
      throw const ConflictException('A work timer is running on this stage. Stop it first.', code: 'TIMER_RUNNING');
    }
    _touch(c, Tables.tasks, task, {'status': status, 'completed_at': status == 'completed' ? c.nowIso : null});
    if (status == 'in_progress' || status == 'completed') _startProductionIfIdle(c, job);
  }

  static void _checklistAdd(OpContext c, String taskId, Map<String, dynamic> body) {
    final id = body['id'] as String? ?? c.newId();
    if (c.store.get(Tables.checklist, id) != null) return;
    final task = _require(c, Tables.tasks, taskId);
    _guardOpen(_jobOf(c, task));
    final items = _checklistOf(c, taskId);
    c.store.put(Tables.checklist, {
      'id': id,
      'job_task_id': taskId,
      'label': (body['label'] as String).trim(),
      'is_done': false,
      'done_at': null,
      'sort_order': items.fold<int>(0, (m, i) => _int(i['sort_order']) > m ? _int(i['sort_order']) : m) + 1,
      'version': 1,
      'created_at': c.nowIso,
      'deleted_at': null,
    });
  }

  static void _checklistUpdate(OpContext c, String id, Map<String, dynamic> body) {
    final item = _require(c, Tables.checklist, id);
    _guardOpen(_jobOf(c, _require(c, Tables.tasks, item['job_task_id'] as String)));
    if (body['version'] != null) _guardVersion(item, body['version'], 'This subtask was changed on another device. Reload to see the latest details.');
    final changes = <String, dynamic>{};
    if (body['label'] is String) changes['label'] = (body['label'] as String).trim();
    if (body['is_done'] is bool && body['is_done'] != item['is_done']) {
      changes['is_done'] = body['is_done'];
      changes['done_at'] = body['is_done'] == true ? c.nowIso : null;
    }
    if (changes.isNotEmpty) _touch(c, Tables.checklist, item, changes);
  }

  // ---------------------------------------------------------------- timer & work logs

  static DateTime _at(OpContext c, Map<String, dynamic> body) => body['occurred_at'] is String ? DateTime.parse(body['occurred_at'] as String).toUtc() : c.now;

  static void _timerStart(OpContext c, String taskId, String? id, DateTime at) {
    if (id != null && c.store.get(Tables.workLogs, id) != null) return;
    final task = _require(c, Tables.tasks, taskId);
    final job = _jobOf(c, task);
    _guardWorkable(c, job, task);
    if (_closed(task)) {
      throw ConflictException('${task['task_name']} is ${task['status'] == 'completed' ? 'completed' : 'skipped'}. Reopen the stage to log more work.', code: 'TASK_CLOSED');
    }
    final running = _myRunning(c);
    if (running != null) {
      if (running['job_task_id'] == taskId) return;
      final other = c.store.get(Tables.tasks, running['job_task_id'] as String)?['task_name'];
      throw ConflictException('A timer is already running on $other. Switch to this stage or stop it first.', code: 'TIMER_ALREADY_RUNNING');
    }
    if (task['status'] == 'pending') _touch(c, Tables.tasks, task, {'status': 'in_progress'});
    _startProductionIfIdle(c, job);
    c.store.put(Tables.workLogs, _logRow(c, id ?? c.newId(), taskId, 'timer', at, null, null));
  }

  static void _timerStop(OpContext c, Map<String, dynamic> body) {
    final entryId = body['entry_id'] as String?;
    if (entryId != null) {
      final log = c.store.get(Tables.workLogs, entryId);
      if (log == null) throw const NotFoundException('This timer session does not exist.');
      if (log['ended_at'] != null || log['deleted_at'] != null) return; // replay of a stop that already happened
    }
    final running = _myRunning(c);
    if (running == null) throw const ConflictException('No timer is running.', code: 'NO_TIMER_RUNNING');
    _close(c, running, _at(c, body), body['note'] as String?);
    if (body['complete_task'] == true) _taskStatus(c, running['job_task_id'] as String, 'completed', null);
  }

  static void _timerSwitch(OpContext c, Map<String, dynamic> body) {
    final id = body['id'] as String?;
    if (id != null && c.store.get(Tables.workLogs, id) != null) return;
    final to = body['task_id'] as String;
    final running = _myRunning(c);
    if (running != null && running['job_task_id'] == to) return;
    final at = _at(c, body);
    if (running != null) _close(c, running, at, body['note'] as String?);
    _timerStart(c, to, id, at);
  }

  static void _close(OpContext c, Map<String, dynamic> log, DateTime at, String? note) {
    final started = DateTime.parse(log['started_at'] as String);
    final end = at.isAfter(started) ? at : started.add(const Duration(milliseconds: 1));
    final trimmed = note?.trim();
    _touch(c, Tables.workLogs, log, {
      'ended_at': iso(end),
      if (trimmed != null && trimmed.isNotEmpty) 'note': log['note'] == null ? trimmed : '${log['note']}\n$trimmed',
      'needs_review': end.difference(started).inSeconds > c.config.reviewThresholdSeconds,
    });
  }

  static void _worklogAdd(OpContext c, String taskId, Map<String, dynamic> body) {
    final id = body['id'] as String? ?? c.newId();
    if (c.store.get(Tables.workLogs, id) != null) return;
    final task = _require(c, Tables.tasks, taskId);
    _guardWorkable(c, _jobOf(c, task), task, allowReady: true);
    DateTime start, end;
    String? note = body['note'] as String?;
    if (body['duration_seconds'] != null) {
      final seconds = _int(body['duration_seconds']);
      final running = _myRunning(c);
      end = running != null ? DateTime.parse(running['started_at'] as String) : _at(c, body);
      start = end.subtract(Duration(seconds: seconds));
      if (note == null) {
        final h = seconds ~/ 3600, m = (seconds % 3600) ~/ 60;
        note = 'Adjustment +${h > 0 ? (m > 0 ? '${h}h ${m}m' : '${h}h') : '${m}m'}';
      }
    } else {
      start = DateTime.parse(body['started_at'] as String).toUtc();
      end = DateTime.parse(body['ended_at'] as String).toUtc();
    }
    _guardRange(c, start, end);
    c.store.put(Tables.workLogs, _logRow(c, id, taskId, 'manual', start, end, note));
  }

  static void _worklogUpdate(OpContext c, String id, Map<String, dynamic> body) {
    final log = _require(c, Tables.workLogs, id);
    _guardOpen(_jobOf(c, _require(c, Tables.tasks, log['job_task_id'] as String)));
    _guardVersion(log, body['version'], 'This entry was changed on another device. Reload to see the latest details.');
    if (log['ended_at'] == null && (body['started_at'] != null || body['ended_at'] != null)) {
      throw const ConflictException('Stop the timer before changing its times.', code: 'TIMER_RUNNING');
    }
    final changes = <String, dynamic>{
      if (body['started_at'] != null) 'started_at': iso(DateTime.parse(body['started_at'] as String)),
      if (body['ended_at'] != null) 'ended_at': iso(DateTime.parse(body['ended_at'] as String)),
      if (body.containsKey('note')) 'note': body['note'],
    };
    final merged = {...log, ...changes};
    if (merged['ended_at'] != null) {
      final s = DateTime.parse(merged['started_at'] as String), e = DateTime.parse(merged['ended_at'] as String);
      _guardRange(c, s, e);
      changes['needs_review'] = e.difference(s).inSeconds > c.config.reviewThresholdSeconds;
    }
    _touch(c, Tables.workLogs, log, changes);
  }

  static Map<String, dynamic> _logRow(OpContext c, String id, String taskId, String type, DateTime start, DateTime? end, String? note) => {
        'id': id,
        'job_task_id': taskId,
        'entry_type': type,
        'started_at': iso(start),
        'ended_at': end == null ? null : iso(end),
        'note': note,
        'needs_review': end != null && end.difference(start).inSeconds > c.config.reviewThresholdSeconds,
        'void_reason': null,
        'created_by': c.userId,
        'recorded_by': c.userName,
        'version': 1,
        'created_at': c.nowIso,
        'deleted_at': null,
      };

  static void _guardWorkable(OpContext c, Map<String, dynamic> job, Map<String, dynamic> task, {bool allowReady = false}) {
    if (c.config.isMilestone(_int(task['task_type_id']))) throw _invalid('job_task_id', 'Milestones such as "Ready for Collection" have no work to log.');
    final allowed = [...JobStatusRules.production, if (allowReady) 'ready_for_collection'];
    if (!allowed.contains(job['status'])) {
      throw ConflictException(
        switch (job['status']) {
          'draft' => 'Queue this job for production before logging work.',
          'ready_for_collection' => 'This job is ready for collection. Move it back to production to log more work.',
          _ => 'This job is ${JobStatusRules.label(job['status'] as String).toLowerCase()} and can no longer be changed.',
        },
        code: 'JOB_NOT_IN_PRODUCTION',
      );
    }
  }

  static void _guardRange(OpContext c, DateTime start, DateTime end) {
    if (!end.isAfter(start)) throw _invalid('ended_at', 'The end time must be after the start time.');
    if (end.isAfter(c.now.add(const Duration(minutes: 1)))) throw _invalid('ended_at', 'Work cannot be logged in the future.');
    if (end.difference(start).inSeconds > 24 * 3600) throw _invalid('ended_at', 'One entry cannot be longer than 24 hours.');
  }

  // ---------------------------------------------------------------- appointments (AppointmentService)

  static const _appointmentTransitions = {
    'scheduled': ['confirmed', 'completed', 'cancelled', 'no_show'],
    'confirmed': ['scheduled', 'completed', 'cancelled', 'no_show'],
  };

  static void _appointmentCreate(OpContext c, Map<String, dynamic> body) {
    final id = body['id'] as String? ?? c.newId();
    if (c.store.get(Tables.appointments, id) != null) return;
    final data = _appointmentData(c, body, null);
    if (body['allow_overlap'] != true) _guardOverlap(c, data['starts_at'] as String, data['ends_at'] as String, null);
    c.store.put(Tables.appointments, {
      'id': id,
      'appointment_type': body['appointment_type'],
      'title': (body['title'] as String).trim(),
      'location': body['location'],
      'reminder_minutes_before': body['reminder_minutes_before'],
      'notes': body['notes'],
      ...data,
      'status': body['status'] ?? 'scheduled',
      'version': 1,
      'created_at': c.nowIso,
      'updated_at': c.nowIso,
      'deleted_at': null,
    });
  }

  static void _appointmentUpdate(OpContext c, String id, Map<String, dynamic> body) {
    final row = _require(c, Tables.appointments, id);
    _guardVersion(row, body['version'], 'This appointment was changed on another device. Reload to see the latest details.');
    if (row['status'] != 'scheduled' && row['status'] != 'confirmed') {
      throw ConflictException('This appointment is ${(row['status'] as String).replaceAll('_', ' ')} and can no longer be changed.', code: 'APPOINTMENT_CLOSED');
    }
    final data = _appointmentData(c, body, row);
    if (body['allow_overlap'] != true) _guardOverlap(c, data['starts_at'] as String, data['ends_at'] as String, id);
    _touch(c, Tables.appointments, row, {
      for (final key in ['appointment_type', 'title', 'location', 'reminder_minutes_before', 'notes'])
        if (body.containsKey(key)) key: key == 'title' ? (body[key] as String).trim() : body[key],
      ...data,
    });
  }

  static void _appointmentStatus(OpContext c, String id, String status) {
    final row = _require(c, Tables.appointments, id);
    final from = row['status'] as String;
    if (from == status) return;
    if (!(_appointmentTransitions[from] ?? const []).contains(status)) {
      throw ConflictException('A ${from.replaceAll('_', ' ')} appointment cannot be marked ${status.replaceAll('_', ' ')}.', code: 'INVALID_STATUS_TRANSITION');
    }
    _touch(c, Tables.appointments, row, {'status': status});
  }

  /// Links and times, like AppointmentService::resolve (the job decides the customer when none is given).
  static Map<String, dynamic> _appointmentData(OpContext c, Map<String, dynamic> body, Map<String, dynamic>? existing) {
    final out = <String, dynamic>{};
    var customerId = existing?['customer_id'] as String?;
    if (body.containsKey('customer_id')) {
      customerId = body['customer_id'] as String?;
      if (customerId != null && c.store.get(Tables.customers, customerId) == null) throw _invalid('customer_id', 'This customer does not exist.');
      out['customer_id'] = customerId;
    }
    var jobId = existing?['job_id'] as String?;
    if (body.containsKey('job_id')) {
      jobId = body['job_id'] as String?;
      if (jobId != null) {
        final job = c.store.get(Tables.jobs, jobId);
        if (job == null || job['deleted_at'] != null) throw _invalid('job_id', 'This job does not exist.');
        if (customerId != null && job['customer_id'] != customerId) throw _invalid('job_id', 'This job belongs to another customer.');
        if (customerId == null) out['customer_id'] = job['customer_id'];
      }
      out['job_id'] = jobId;
    }
    if (body.containsKey('job_task_id')) {
      final taskId = body['job_task_id'] as String?;
      if (taskId != null && c.store.get(Tables.tasks, taskId)?['job_id'] != jobId) throw _invalid('job_task_id', 'This stage belongs to another job.');
      out['job_task_id'] = taskId;
    }
    if (existing == null) {
      out.putIfAbsent('customer_id', () => null);
      out.putIfAbsent('job_id', () => null);
      out.putIfAbsent('job_task_id', () => null);
    }
    final starts = body['starts_at'] != null ? DateTime.parse(body['starts_at'] as String) : DateTime.tryParse(existing?['starts_at'] as String? ?? '');
    final ends = body['ends_at'] != null ? DateTime.parse(body['ends_at'] as String) : DateTime.tryParse(existing?['ends_at'] as String? ?? '');
    if (starts == null || ends == null) throw _invalid('starts_at', 'Give the start and end time.');
    if (!ends.isAfter(starts)) throw _invalid('ends_at', 'The end time must be after the start time.');
    if (ends.difference(starts) > const Duration(hours: 12)) throw _invalid('ends_at', 'An appointment cannot be longer than 12 hours.');
    out['starts_at'] = iso(starts);
    out['ends_at'] = iso(ends);
    return out;
  }

  static void _guardOverlap(OpContext c, String starts, String ends, String? exceptId) {
    final clash = c.store
        .all(Tables.appointments)
        .where((a) =>
            a['deleted_at'] == null &&
            a['id'] != exceptId &&
            (a['status'] == 'scheduled' || a['status'] == 'confirmed') &&
            (a['starts_at'] as String).compareTo(ends) < 0 &&
            (a['ends_at'] as String).compareTo(starts) > 0)
        .toList()
      ..sort((a, b) => (a['starts_at'] as String).compareTo(b['starts_at'] as String));
    if (clash.isEmpty) return;
    final a = clash.first;
    final who = a['customer_id'] == null ? null : c.store.get(Tables.customers, a['customer_id'] as String)?['full_name'];
    String hm(String t) => businessTime(c.config, DateTime.parse(t));
    throw ConflictException(
      'This overlaps "${a['title']}"${who == null ? '' : ' with $who'} (${hm(a['starts_at'] as String)}–${hm(a['ends_at'] as String)}).',
      code: 'SCHEDULE_CONFLICT',
    );
  }

  // ---------------------------------------------------------------- inventory (InventoryService)

  static const _itemFields = [
    'category_id', 'item_name', 'sku', 'description', 'unit', 'min_stock_level', 'reorder_quantity', 'unit_cost',
    'supplier_name', 'supplier_contact', 'storage_location', 'notes',
  ];

  static void _itemCreate(OpContext c, Map<String, dynamic> body) {
    final id = body['id'] as String? ?? c.newId();
    if (c.store.get(Tables.inventoryItems, id) != null) return;
    final data = _itemData(c, body, null);
    final unit = data['unit'] as String;
    final opening = (body['opening_quantity'] as num?)?.toDouble() ?? 0;
    _guardStockQuantity(unit, opening, 'opening_quantity', allowZero: true);
    c.store.put(Tables.inventoryItems, {
      for (final key in _itemFields) key: data[key],
      'id': id,
      'min_stock_level': data['min_stock_level'] ?? 0.0,
      'archived_at': null,
      'version': 1,
      'created_at': c.nowIso,
      'updated_at': c.nowIso,
      'deleted_at': null,
    });
    if (opening > 0) {
      _putTransaction(c, body['opening_transaction_id'] as String? ?? c.newId(), id, 'opening', opening, unitCost: data['unit_cost'], note: 'Opening balance', at: _at(c, body));
    }
  }

  static void _itemUpdate(OpContext c, String id, Map<String, dynamic> body) {
    final row = _require(c, Tables.inventoryItems, id);
    _guardVersion(row, body['version'], 'This material was changed on another device. Reload to see the latest details.');
    final data = _itemData(c, body, row);
    if (data.containsKey('unit') && data['unit'] != row['unit'] && c.store.all(Tables.inventoryTransactions).any((t) => t['item_id'] == id)) {
      throw _invalid('unit', 'The unit cannot change once stock has been recorded. Add a new material instead.');
    }
    _touch(c, Tables.inventoryItems, row, data);
  }

  /// Like InventoryService::itemData: trims text, checks the category, code and whole-number units.
  static Map<String, dynamic> _itemData(OpContext c, Map<String, dynamic> body, Map<String, dynamic>? existing) {
    final out = <String, dynamic>{
      for (final key in _itemFields)
        if (body.containsKey(key)) key: body[key] is String ? ((body[key] as String).trim().isEmpty ? null : (body[key] as String).trim()) : body[key],
    };
    for (final key in ['min_stock_level', 'reorder_quantity', 'unit_cost']) {
      if (out[key] is num) out[key] = (out[key] as num).toDouble();
    }
    if (out.containsKey('item_name') && out['item_name'] == null) throw _invalid('item_name', 'Give the material a name.');
    if (out['category_id'] != null && _int(out['category_id']) != _int(existing?['category_id'])) {
      final category = c.config.inventoryCategory(_int(out['category_id']));
      if (category == null || category['is_active'] != true) throw _invalid('category_id', 'Choose an active category.');
    }
    if (out['sku'] != null && c.store.all(Tables.inventoryItems).any((i) => i['sku'] == out['sku'] && i['id'] != existing?['id'])) {
      throw _invalid('sku', 'Another material already uses this code.');
    }
    final unit = (out['unit'] ?? existing?['unit']) as String;
    for (final key in ['min_stock_level', 'reorder_quantity']) {
      final v = out[key] as double?;
      if (v != null && StockRules.isCounted(unit) && v != v.floorToDouble()) throw _invalid(key, 'Use a whole number of ${StockRules.unitName(unit, 2)}.');
    }
    if (out.containsKey('min_stock_level') && out['min_stock_level'] == null) out['min_stock_level'] = 0.0;
    return out;
  }

  static void _stockRecord(OpContext c, String itemId, Map<String, dynamic> body) {
    final id = body['id'] as String? ?? c.newId();
    if (c.store.get(Tables.inventoryTransactions, id) != null) return; // replay
    final item = _require(c, Tables.inventoryItems, itemId);
    if (item['archived_at'] != null) throw const ConflictException('This material is archived. Restore it to record stock.', code: 'ITEM_ARCHIVED');
    final unit = item['unit'] as String;
    final type = body['transaction_type'] as String;
    final onHand = StockRules.onHand(c.store.all(Tables.inventoryTransactions).where((t) => t['item_id'] == itemId));
    final double change;
    if (type == 'adjustment') {
      final counted = (body['counted_quantity'] as num).toDouble();
      _guardStockQuantity(unit, counted, 'counted_quantity', allowZero: true);
      change = StockRules.round(counted - onHand);
      if (change == 0) throw _invalid('counted_quantity', 'The stock already shows ${StockRules.quantity(onHand, unit)}.');
    } else {
      final quantity = (body['quantity'] as num).toDouble();
      _guardStockQuantity(unit, quantity, 'quantity');
      change = StockRules.reductions.contains(type) ? -quantity : quantity;
    }
    final jobId = body['job_id'] as String?;
    if (jobId != null) {
      if (!StockRules.jobTypes.contains(type)) throw _invalid('job_id', 'Only usage and returns can be linked to a job.');
      final job = c.store.get(Tables.jobs, jobId);
      if (job == null || job['deleted_at'] != null) throw _invalid('job_id', 'This job does not exist.');
    }
    if (body['unit_cost'] != null && type != 'purchase') throw _invalid('unit_cost', 'A cost can only be recorded with a purchase.');
    final after = StockRules.round(onHand + change);
    if (change < 0 && after < 0 && body['offline'] != true) {
      final field = type == 'adjustment' ? 'counted_quantity' : 'quantity';
      final message = onHand <= 0
          ? 'There is no stock of this material. Record what came in, or a stock count, first.'
          : 'Only ${StockRules.quantity(onHand, unit)} in stock. If the shelf holds more, record a stock count first.';
      throw ValidationException(message, {field: [message]}, code: 'INSUFFICIENT_STOCK');
    }
    _putTransaction(c, id, itemId, type, change,
        jobId: jobId, unitCost: (body['unit_cost'] as num?)?.toDouble(), reference: _text(body['reference']), note: _text(body['note']), at: _at(c, body));
  }

  static void _stockVoid(OpContext c, String id, Map<String, dynamic> body) {
    final tx = c.store.get(Tables.inventoryTransactions, id);
    if (tx == null) throw const NotFoundException('The requested resource was not found.');
    if (tx['deleted_at'] != null) return; // replay
    final item = _require(c, Tables.inventoryItems, tx['item_id'] as String);
    final change = (tx['quantity_change'] as num).toDouble();
    final onHand = StockRules.onHand(c.store.all(Tables.inventoryTransactions).where((t) => t['item_id'] == item['id']));
    final after = StockRules.round(onHand - change);
    if (after < 0 && change > 0 && body['offline'] != true) {
      throw ValidationException(
        'Voiding this would leave ${StockRules.quantity(after, item['unit'] as String)} in stock. Record the usage correction or a stock count instead.',
        const {},
        code: 'INSUFFICIENT_STOCK',
      );
    }
    final reason = (body['reason'] as String).trim();
    _touch(c, Tables.inventoryTransactions, tx, {'deleted_at': c.nowIso, 'void_reason': reason.length > 255 ? reason.substring(0, 255) : reason});
  }

  static void _putTransaction(OpContext c, String id, String itemId, String type, double change,
      {String? jobId, Object? unitCost, String? reference, String? note, required DateTime at}) {
    c.store.put(Tables.inventoryTransactions, {
      'id': id,
      'item_id': itemId,
      'transaction_type': type,
      'quantity_change': StockRules.round(change),
      'job_id': jobId,
      'unit_cost': unitCost,
      'reference': reference,
      'note': note,
      'occurred_at': iso(at),
      'void_reason': null,
      'created_by': c.userId,
      'recorded_by': c.userName,
      'version': 1,
      'created_at': c.nowIso,
      'deleted_at': null,
    });
  }

  static void _guardStockQuantity(String unit, double quantity, String field, {bool allowZero = false}) {
    if (quantity < 0 || (!allowZero && quantity <= 0)) throw _invalid(field, 'Enter a quantity above zero.');
    if (StockRules.isCounted(unit) && quantity != quantity.floorToDouble()) throw _invalid(field, 'Use a whole number of ${StockRules.unitName(unit, 2)}.');
  }

  static String? _text(Object? v) => v is String && v.trim().isNotEmpty ? v.trim() : null;

  // ---------------------------------------------------------------- tools (ToolService)

  static const _toolFields = [
    'category_id', 'tool_name', 'brand_model', 'serial_number', 'purchase_date', 'tool_condition', 'operational_status',
    'storage_location', 'maintenance_interval_days', 'next_maintenance_override', 'notes',
  ];

  static void _toolCreate(OpContext c, Map<String, dynamic> body) {
    final id = body['id'] as String? ?? c.newId();
    if (c.store.get(Tables.tools, id) != null) return;
    final data = _toolData(c, body, null);
    c.store.put(Tables.tools, {
      for (final key in _toolFields) key: data[key],
      'id': id,
      'tool_condition': data['tool_condition'] ?? 'good',
      'operational_status': data['operational_status'] ?? 'operational',
      'archived_at': null,
      'version': 1,
      'created_at': c.nowIso,
      'updated_at': c.nowIso,
      'deleted_at': null,
    });
  }

  /// Like ToolService::data: trims text, checks the category and the dates.
  static Map<String, dynamic> _toolData(OpContext c, Map<String, dynamic> body, Map<String, dynamic>? existing) {
    final out = <String, dynamic>{
      for (final key in _toolFields)
        if (body.containsKey(key)) key: body[key] is String ? ((body[key] as String).trim().isEmpty ? null : (body[key] as String).trim()) : body[key],
    };
    if (out.containsKey('tool_name') && out['tool_name'] == null) throw _invalid('tool_name', 'Give the tool a name.');
    if (out['category_id'] != null && _int(out['category_id']) != _int(existing?['category_id'])) {
      final category = c.config.toolCategory(_int(out['category_id']));
      if (category == null || category['is_active'] != true) throw _invalid('category_id', 'Choose an active category.');
    }
    final today = businessToday(c.config, c.now);
    if (out['purchase_date'] is String && (out['purchase_date'] as String).compareTo(today) > 0) throw _invalid('purchase_date', 'The purchase date cannot be in the future.');
    if (out['next_maintenance_override'] is String && (out['next_maintenance_override'] as String).compareTo(today) < 0) {
      throw _invalid('next_maintenance_override', 'The next maintenance date cannot be in the past.');
    }
    return out;
  }

  static void _toolMaintenance(OpContext c, String toolId, Map<String, dynamic> body) {
    final id = body['id'] as String? ?? c.newId();
    if (c.store.get(Tables.toolLogs, id) != null) return; // replay
    final today = businessToday(c.config, c.now);
    final performedOn = body['performed_on'] as String? ?? today;
    if (performedOn.compareTo(today) > 0) throw _invalid('performed_on', 'Maintenance cannot be logged for a future date.');
    final tool = _require(c, Tables.tools, toolId);
    if (tool['archived_at'] != null) throw const ConflictException('This tool is archived. Restore it to log maintenance.', code: 'TOOL_ARCHIVED');
    c.store.put(Tables.toolLogs, {
      'id': id,
      'tool_id': toolId,
      'performed_on': performedOn,
      'maintenance_type': body['maintenance_type'],
      'description': _text(body['description']),
      'performed_by': _text(body['performed_by']),
      'condition_after': body['condition_after'],
      'created_by': c.userId,
      'recorded_by': c.userName,
      'version': 1,
      'created_at': c.nowIso,
      'deleted_at': null,
    });
    _touch(c, Tables.tools, tool, {
      'next_maintenance_override': null,
      if (body['condition_after'] != null) 'tool_condition': body['condition_after'],
      if (body['operational_status'] != null) 'operational_status': body['operational_status'],
    });
  }

  // ---------------------------------------------------------------- helpers

  static Map<String, dynamic>? _myRunning(OpContext c) => c.store
      .all(Tables.workLogs)
      .where((l) => l['ended_at'] == null && l['deleted_at'] == null && _int(l['created_by']) == c.userId)
      .firstOrNull;

  static Map<String, dynamic>? _runningLogOf(OpContext c, String taskId) =>
      c.store.all(Tables.workLogs).where((l) => l['job_task_id'] == taskId && l['ended_at'] == null && l['deleted_at'] == null).firstOrNull;

  static List<Map<String, dynamic>> _logsOf(OpContext c, String taskId) =>
      c.store.all(Tables.workLogs).where((l) => l['job_task_id'] == taskId && l['deleted_at'] == null).toList();

  static List<Map<String, dynamic>> _tasksOf(OpContext c, String jobId) =>
      c.store.all(Tables.tasks).where((t) => t['job_id'] == jobId && t['deleted_at'] == null).toList()..sort((a, b) => _int(a['sort_order']).compareTo(_int(b['sort_order'])));

  static List<Map<String, dynamic>> _checklistOf(OpContext c, String taskId) =>
      c.store.all(Tables.checklist).where((i) => i['job_task_id'] == taskId && i['deleted_at'] == null).toList();

  static Map<String, dynamic> _jobOf(OpContext c, Map<String, dynamic> task) => _require(c, Tables.jobs, task['job_id'] as String);

  static bool _closed(Map<String, dynamic> task) => task['status'] == 'completed' || task['status'] == 'skipped';

  static Map<String, dynamic> _require(OpContext c, String table, String id) {
    final row = c.store.get(table, id);
    if (row == null || row['deleted_at'] != null) throw const NotFoundException('The requested resource was not found.');
    return row;
  }

  static void _guardOpen(Map<String, dynamic> job) {
    if (job['status'] == 'completed' || job['status'] == 'cancelled') {
      throw ConflictException('This job is ${JobStatusRules.label(job['status'] as String).toLowerCase()} and can no longer be changed.', code: 'JOB_CLOSED');
    }
  }

  static void _guardVersion(Map<String, dynamic> row, Object? version, String message) {
    if (version != null && _int(version) != _int(row['version'])) throw ConflictException(message, code: 'CONFLICT_VERSION');
  }

  static void _guardDates(String order, String? due, String? collection) {
    if (due != null && due.compareTo(order) < 0) throw _invalid('due_date', 'The due date cannot be before the order date.');
    if (collection != null && collection.compareTo(order) < 0) throw _invalid('collection_date', 'The collection date cannot be before the order date.');
  }

  static void _setSort(OpContext c, Map<String, dynamic> task, int order) {
    if (_int(task['sort_order']) != order) _touch(c, Tables.tasks, task, {'sort_order': order});
  }

  /// Applies changes as a new row (version + 1), like an Eloquent save with the Syncable trait.
  static void _touch(OpContext c, String table, Map<String, dynamic> row, Map<String, dynamic> changes) {
    c.store.put(table, {...row, ...changes, 'version': _int(row['version']) + 1, if (row.containsKey('updated_at')) 'updated_at': c.nowIso});
  }

  static ValidationException _invalid(String field, String message) => ValidationException('Some fields are invalid.', {field: [message]}, code: 'VALIDATION_FAILED');

  static int _int(Object? v) => v is num ? v.toInt() : (v is String ? int.tryParse(v) ?? 0 : 0);
}
