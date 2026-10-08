import 'package:dio/dio.dart';

import 'fakes.dart';

/// In-memory jobs, stages and garment templates for widget tests. Follows the Laravel rules that the
/// screens depend on: job numbers, the status machine, TASKS_INCOMPLETE, stage status needing a job in
/// production, and the hour/progress formulas (99 % cap, estimate-weighted job progress).
class FakeJobs {
  FakeJobs(this.customerName);

  /// Resolves a customer id to {full_name, phone} (owned by FakeBackend).
  final Map<String, dynamic>? Function(String id) customerName;

  final jobs = <Map<String, dynamic>>[];
  int _number = 23;
  int _ids = 0;

  static const taskTypes = [
    {'id': 1, 'code': 'measurement', 'name': 'Measurement', 'kind': 'work', 'is_fitting': false, 'color_key': 'slate', 'sort_order': 10, 'is_active': true},
    {'id': 2, 'code': 'cutting', 'name': 'Cutting', 'kind': 'work', 'is_fitting': false, 'color_key': 'blue', 'sort_order': 20, 'is_active': true},
    {'id': 3, 'code': 'sewing', 'name': 'Sewing', 'kind': 'work', 'is_fitting': false, 'color_key': 'blue', 'sort_order': 30, 'is_active': true},
    {'id': 4, 'code': 'fitting', 'name': 'Fitting', 'kind': 'work', 'is_fitting': true, 'color_key': 'teal', 'sort_order': 40, 'is_active': true},
    {'id': 6, 'code': 'finishing', 'name': 'Finishing', 'kind': 'work', 'is_fitting': false, 'color_key': 'indigo', 'sort_order': 60, 'is_active': true},
    {'id': 9, 'code': 'ready_for_collection', 'name': 'Ready for Collection', 'kind': 'milestone', 'is_fitting': false, 'color_key': 'green', 'sort_order': 90, 'is_active': true},
  ];

  late final jobTypes = <Map<String, dynamic>>[
    _jobType(1, '3-Piece Suit', 'Jacket, Waistcoat & Trousers', [(1, 'Measurement & Pattern Drafting', 2.5), (2, 'Fabric Cutting', 3), (3, 'Sewing & Assembly', 6), (6, 'Finishing & Buttonholes', 2), (9, null, 0)]),
    _jobType(6, 'Kaftan', 'Top & Trousers', [(1, null, 0), (2, null, 0), (3, null, 0), (9, null, 0)]),
  ];

  static Map<String, dynamic> _type(int id) => taskTypes.firstWhere((t) => t['id'] == id);

  Map<String, dynamic> _jobType(int id, String name, String components, List<(int, String?, double)> tasks) => {
        'id': id,
        'code': name.toLowerCase(),
        'name': name,
        'components': components,
        'description': null,
        'default_quantity': 1,
        'sort_order': id * 10,
        'is_active': true,
        'estimated_seconds': tasks.fold<int>(0, (s, t) => s + (t.$3 * 3600).round()),
        'tasks': [
          for (final (i, t) in tasks.indexed)
            {
              'task_type': _type(t.$1),
              'name': t.$2 ?? _type(t.$1)['name'],
              'custom_name': t.$2,
              'sort_order': i + 1,
              'default_estimated_seconds': (t.$3 * 3600).round(),
            },
        ],
      };

  String _id(String prefix) => '0192f0a1-$prefix-7000-8000-${(++_ids).toString().padLeft(12, '0')}';

  /// Adds a job; [done] leading work stages are completed, the next one is in progress.
  Map<String, dynamic> addJob(
    String customerId, {
    int jobTypeId = 1,
    String status = 'in_progress',
    String priority = 'normal',
    int? dueInDays,
    int done = 0,
    Map<int, int> actualSeconds = const {},
    List<String> checklist = const [],
  }) {
    final type = jobTypes.firstWhere((t) => t['id'] == jobTypeId);
    final templates = (type['tasks'] as List).cast<Map<String, dynamic>>();
    final today = DateTime.now();
    final job = <String, dynamic>{
      'id': _id('aaaa'),
      'job_number': (++_number).toString().padLeft(3, '0'),
      'title': type['name'],
      'quantity': 1,
      'priority': priority,
      'status': status,
      'customer_id': customerId,
      'job_type': {'id': type['id'], 'name': type['name'], 'components': type['components']},
      'order_date': _date(today.subtract(const Duration(days: 5))),
      'due_date': dueInDays == null ? null : _date(today.add(Duration(days: dueInDays))),
      'collection_date': null,
      'completed_at': null,
      'description': null,
      'fabric_note': 'Navy Super 150s wool',
      'notes': null,
      'cancel_reason': null,
      'progress_override': null,
      'measurement_set': null,
      'version': 1,
      'created_at': '2026-10-01T09:00:00.000Z',
      'updated_at': '2026-10-01T09:00:00.000Z',
      'tasks': [
        for (final (i, t) in templates.indexed)
          {
            'id': _id('bbbb'),
            'task_type': t['task_type'],
            'name': t['name'],
            'sort_order': i + 1,
            'status': (t['task_type'] as Map)['kind'] == 'milestone'
                ? 'pending'
                : i < done
                    ? 'completed'
                    : (i == done && status == 'in_progress' ? 'in_progress' : 'pending'),
            'estimated_seconds': t['default_estimated_seconds'],
            'actual_seconds': actualSeconds[i] ?? (i < done ? t['default_estimated_seconds'] : 0),
            'completed_at': i < done ? '2026-10-0${i + 2}T15:00:00.000Z' : null,
            'notes': null,
            'log_count': 0,
            'checklist': [
              if (i == done)
                for (final (n, label) in checklist.indexed) {'id': _id('cccc'), 'label': label, 'is_done': n == 0, 'done_at': n == 0 ? '2026-10-07T10:00:00.000Z' : null, 'sort_order': n + 1, 'version': 1},
            ],
            'version': 1,
          },
      ],
    };
    jobs.add(job);
    return job;
  }

  static String _date(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  static const _transitions = {
    'draft': ['queued', 'cancelled'],
    'queued': ['in_progress', 'cancelled'],
    'in_progress': ['on_hold', 'ready_for_collection', 'cancelled'],
    'on_hold': ['in_progress', 'cancelled'],
    'ready_for_collection': ['completed', 'in_progress', 'cancelled'],
    'completed': <String>[],
    'cancelled': <String>[],
  };

  static const _labels = {
    'draft': 'Draft',
    'queued': 'Queued',
    'in_progress': 'In production',
    'on_hold': 'On hold',
    'ready_for_collection': 'Ready for collection',
    'completed': 'Collected',
    'cancelled': 'Cancelled',
  };

  /// The API representation (hours, current stage, flags) of a stored job.
  Map<String, dynamic> present(Map<String, dynamic> job) {
    final tasks = (job['tasks'] as List).cast<Map<String, dynamic>>()..sort((a, b) => (a['sort_order'] as int).compareTo(b['sort_order'] as int));
    final presented = [for (final t in tasks) _presentTask(t)];
    final work = presented.where((t) => (t['task_type'] as Map)['kind'] == 'work').toList();
    final counted = work.where((t) => t['status'] != 'skipped').toList();
    final estimated = counted.fold<int>(0, (s, t) => s + (t['estimated_seconds'] as int));
    double progress;
    if (job['progress_override'] != null) {
      progress = (job['progress_override'] as num).toDouble();
    } else if (['ready_for_collection', 'completed'].contains(job['status'])) {
      progress = 100;
    } else if (estimated > 0) {
      progress = counted.fold<double>(0, (s, t) => s + (t['progress_percent'] as double) * (t['estimated_seconds'] as int)) / estimated;
    } else {
      progress = counted.isEmpty ? 0 : counted.where((t) => t['status'] == 'completed').length * 100 / counted.length;
    }

    final visible = presented.where((t) => t['status'] != 'skipped').toList();
    final current = visible.where((t) => t['status'] == 'in_progress').firstOrNull ?? visible.where((t) => t['status'] == 'pending').firstOrNull;
    final due = job['due_date'] == null ? null : DateTime.parse(job['due_date'] as String);
    final today = DateTime.now();
    final days = due?.difference(DateTime(today.year, today.month, today.day)).inDays;
    final inProduction = ['queued', 'in_progress', 'on_hold'].contains(job['status']);
    final customer = customerName(job['customer_id'] as String) ?? {'full_name': 'Unknown', 'phone': null};

    return {
      ...job,
      'status_label': _labels[job['status']],
      'customer': {'id': job['customer_id'], 'full_name': customer['full_name'], 'phone': customer['phone']},
      'hours': {
        'estimated_seconds': estimated,
        'actual_seconds': work.fold<int>(0, (s, t) => s + (t['actual_seconds'] as int)),
        'remaining_seconds': work.fold<int>(0, (s, t) => s + (t['remaining_seconds'] as int)),
        'overrun_seconds': work.fold<int>(0, (s, t) => s + (t['overrun_seconds'] as int)),
        'task_count': counted.length,
        'completed_task_count': counted.where((t) => t['status'] == 'completed').length,
        'progress_percent': double.parse(progress.toStringAsFixed(2)),
        'is_progress_manual': job['progress_override'] != null,
        'has_running_timer': running != null && presented.any((t) => t['id'] == running!['task_id']),
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
      'flags': {'is_overdue': inProduction && days != null && days < 0, 'is_due_soon': inProduction && days != null && days >= 0 && days <= 3, 'days_until_due': days},
      'allowed_transitions': _transitions[job['status']],
      'tasks': presented,
    };
  }

  Map<String, dynamic> _presentTask(Map<String, dynamic> t) {
    final est = t['estimated_seconds'] as int;
    final actual = t['actual_seconds'] as int;
    final status = t['status'] as String;
    final progress = status == 'completed'
        ? 100.0
        : est > 0
            ? (actual / est * 100).clamp(0, 99).toDouble()
            : 0.0;
    return {
      ...t,
      'remaining_seconds': ['completed', 'skipped'].contains(status) ? 0 : (est - actual).clamp(0, est),
      'overrun_seconds': (actual - est).clamp(0, actual),
      'progress_percent': double.parse(progress.toStringAsFixed(2)),
      'is_progress_manual': false,
      'is_running': running?['task_id'] == t['id'],
      'actual_start': null,
      'actual_end': null,
      'scheduled_start': null,
      'scheduled_end': null,
      'updated_at': '2026-10-08T09:00:00.000Z',
    };
  }

  bool _matches(Map<String, dynamic> job, String filter) {
    final p = present(job);
    final status = job['status'] as String;
    final flags = p['flags'] as Map<String, dynamic>;
    return switch (filter) {
      'open' => !['completed', 'cancelled'].contains(status),
      'active' => ['in_progress', 'on_hold'].contains(status),
      'pending' => ['draft', 'queued'].contains(status),
      'ready' => status == 'ready_for_collection',
      'due_soon' => flags['is_due_soon'] == true,
      'overdue' => flags['is_overdue'] == true,
      'completed' || 'cancelled' => status == filter,
      _ => true,
    };
  }

  /// Answers jobs / tasks / config routes, or null when the path is not a jobs route.
  FakeReply? handle(RequestOptions r) {
    final path = r.path;
    final body = r.data is Map<String, dynamic> ? r.data as Map<String, dynamic> : const <String, dynamic>{};

    if (path.endsWith('/job-types')) return FakeReply.ok(jobTypes);
    if (path.endsWith('/task-types')) return FakeReply.ok(taskTypes);
    final templates = RegExp(r'/job-types/(\d+)/templates$').firstMatch(path);
    if (templates != null && r.method == 'PUT') {
      final type = jobTypes.firstWhere((t) => t['id'] == int.parse(templates.group(1)!));
      final tasks = (body['tasks'] as List).cast<Map<String, dynamic>>();
      type['tasks'] = [
        for (final (i, t) in tasks.indexed)
          {'task_type': _type(t['task_type_id'] as int), 'name': t['task_name'], 'custom_name': t['task_name'], 'sort_order': i + 1, 'default_estimated_seconds': t['default_estimated_seconds']},
      ];
      type['estimated_seconds'] = tasks.fold<int>(0, (s, t) => s + (t['default_estimated_seconds'] as int));
      return FakeReply.ok(type, message: 'Production stages saved. New jobs will use them.');
    }

    if (path.endsWith('/jobs/counts')) {
      final customer = r.queryParameters['customer_id'];
      final mine = jobs.where((j) => customer == null || j['customer_id'] == customer);
      return FakeReply.ok({
        for (final f in ['open', 'active', 'pending', 'ready', 'due_soon', 'overdue', 'completed', 'cancelled', 'any']) f: mine.where((j) => _matches(j, f)).length,
      });
    }
    if (path.endsWith('/jobs') && r.method == 'GET') {
      final filter = r.queryParameters['filter'] as String? ?? 'open';
      final customer = r.queryParameters['customer_id'];
      final q = (r.queryParameters['q'] as String? ?? '').toLowerCase().replaceAll('#', '');
      final items = jobs
          .where((j) => _matches(j, filter) && (customer == null || j['customer_id'] == customer))
          .map(present)
          .where((j) => q.isEmpty || (j['job_number'] as String).contains(q) || ((j['customer'] as Map)['full_name'] as String).toLowerCase().contains(q))
          .toList();
      return FakeReply.ok(items, meta: {'pagination': {'page': 1, 'per_page': 20, 'total': items.length, 'total_pages': 1}});
    }
    if (path.endsWith('/jobs') && r.method == 'POST') {
      final type = jobTypes.firstWhere((t) => t['id'] == body['job_type_id']);
      final job = addJob(body['customer_id'] as String, jobTypeId: type['id'] as int, status: body['status'] as String, priority: body['priority'] as String? ?? 'normal');
      job
        ..['title'] = body['title'] ?? type['name']
        ..['fabric_note'] = body['fabric_note']
        ..['due_date'] = body['due_date']
        ..['quantity'] = body['quantity'] ?? 1;
      final tasks = (body['tasks'] as List?)?.cast<Map<String, dynamic>>();
      if (tasks != null) {
        for (final (i, t) in (job['tasks'] as List).cast<Map<String, dynamic>>().indexed) {
          t['estimated_seconds'] = tasks[i]['estimated_seconds'];
        }
      }
      return FakeReply(201, {'success': true, 'message': 'Job queued for production.', 'data': present(job)});
    }

    final jobMatch = RegExp(r'/jobs/([0-9a-f-]{36})(/.*)?$').firstMatch(path);
    if (jobMatch != null) {
      final job = jobs.where((j) => j['id'] == jobMatch.group(1)).firstOrNull;
      if (job == null) return FakeReply.error(404, 'NOT_FOUND', 'The requested resource was not found.');
      final rest = jobMatch.group(2) ?? '';
      if (rest.isEmpty && r.method == 'GET') return FakeReply.ok(present(job));
      if (rest == '/status') return _status(job, body);
    }

    final taskMatch = RegExp(r'/tasks/([0-9a-f-]{36})/status$').firstMatch(path);
    if (taskMatch != null) {
      final job = jobs.firstWhere((j) => (j['tasks'] as List).any((t) => (t as Map)['id'] == taskMatch.group(1)));
      final task = (job['tasks'] as List).cast<Map<String, dynamic>>().firstWhere((t) => t['id'] == taskMatch.group(1));
      if (!['queued', 'in_progress', 'on_hold'].contains(job['status'])) {
        return FakeReply.error(409, 'JOB_NOT_IN_PRODUCTION', 'Queue this job for production before working on its stages.');
      }
      if (body['version'] != null && body['version'] != task['version']) {
        return FakeReply.error(409, 'CONFLICT_VERSION', 'This stage was changed on another device. Reload to see the latest details.');
      }
      task
        ..['status'] = body['status']
        ..['completed_at'] = body['status'] == 'completed' ? '2026-10-08T10:00:00.000Z' : null
        ..['version'] = (task['version'] as int) + 1;
      if (['in_progress', 'completed'].contains(body['status']) && ['queued', 'on_hold'].contains(job['status'])) job['status'] = 'in_progress';
      return FakeReply.ok(present(job), message: '${task['name']} completed.');
    }

    final timerReply = _timer(r, body);
    if (timerReply != null) return timerReply;

    final itemMatch = RegExp(r'/checklist-items/([0-9a-f-]{36})$').firstMatch(path);
    if (itemMatch != null && r.method == 'PATCH') {
      for (final job in jobs) {
        for (final task in (job['tasks'] as List).cast<Map<String, dynamic>>()) {
          for (final item in (task['checklist'] as List).cast<Map<String, dynamic>>()) {
            if (item['id'] == itemMatch.group(1)) {
              item
                ..['is_done'] = body['is_done']
                ..['version'] = (item['version'] as int) + 1;
              return FakeReply.ok(present(job), message: 'Subtask updated.');
            }
          }
        }
      }
    }
    return null;
  }

  // ---------------------------------------------------------------- timer

  /// The running session {id, task_id, started_at (UTC)} or null.
  Map<String, dynamic>? running;
  final logs = <Map<String, dynamic>>[];

  /// Starts a timer as if it had been running for [elapsed].
  void runTimer(String taskId, {Duration elapsed = const Duration(hours: 1)}) {
    running = {'id': _id('dddd'), 'task_id': taskId, 'started_at': DateTime.now().toUtc().subtract(elapsed)};
    final (job, task) = _findTask(taskId);
    task['status'] = 'in_progress';
    if (job['status'] == 'queued') job['status'] = 'in_progress';
  }

  (Map<String, dynamic>, Map<String, dynamic>) _findTask(String taskId) {
    final job = jobs.firstWhere((j) => (j['tasks'] as List).any((t) => (t as Map)['id'] == taskId));
    return (job, (job['tasks'] as List).cast<Map<String, dynamic>>().firstWhere((t) => t['id'] == taskId));
  }

  Map<String, dynamic> _entry(Map<String, dynamic> log) {
    final start = log['started_at'] as DateTime;
    final end = log['ended_at'] as DateTime?;
    return {
      'id': log['id'],
      'task_id': log['task_id'],
      'entry_type': log['entry_type'] ?? 'timer',
      'started_at': start.toIso8601String(),
      'ended_at': end?.toIso8601String(),
      'duration_seconds': (end ?? DateTime.now().toUtc()).difference(start).inSeconds,
      'is_running': end == null,
      'note': log['note'],
      'needs_review': false,
      'is_voided': false,
      'void_reason': null,
      'recorded_by': 'Marcus Owusu',
      'version': 1,
    };
  }

  FakeReply _timerReply({Map<String, dynamic>? stopped, String? taskId, String message = 'OK'}) {
    final timer = running;
    Map<String, dynamic>? timerJson;
    if (timer != null) {
      final (job, task) = _findTask(timer['task_id'] as String);
      final customer = customerName(job['customer_id'] as String);
      timerJson = {
        ..._entry(timer),
        'task': {
          'id': task['id'],
          'name': task['name'],
          'type_name': (task['task_type'] as Map)['name'],
          'job_id': job['id'],
          'job_number': job['job_number'],
          'job_title': job['title'],
          'customer_name': customer?['full_name'],
        },
      };
    }
    final jobTask = taskId ?? timer?['task_id'] as String?;
    return FakeReply.ok({
      'timer': timerJson,
      'stopped': stopped == null ? null : _entry(stopped),
      'job': jobTask == null ? null : present(_findTask(jobTask).$1),
      'server_time': DateTime.now().toUtc().toIso8601String(),
    }, message: message);
  }

  Map<String, dynamic> _close({String? note}) {
    final log = {...running!, 'ended_at': DateTime.now().toUtc(), 'note': note};
    final (_, task) = _findTask(log['task_id'] as String);
    task['actual_seconds'] = (task['actual_seconds'] as int) + (log['ended_at'] as DateTime).difference(log['started_at'] as DateTime).inSeconds;
    task['log_count'] = (task['log_count'] as int) + 1;
    logs.add(log);
    running = null;
    return log;
  }

  FakeReply? _timer(RequestOptions r, Map<String, dynamic> body) {
    final path = r.path;
    if (path.endsWith('/timers/active')) return _timerReply();
    final start = RegExp(r'/tasks/([0-9a-f-]{36})/timer/start$').firstMatch(path);
    if (start != null) {
      final taskId = start.group(1)!;
      if (running != null && running!['task_id'] != taskId) {
        final (_, other) = _findTask(running!['task_id'] as String);
        return FakeReply.error(409, 'TIMER_ALREADY_RUNNING', 'A timer is already running on ${other['name']}. Switch to this stage or stop it first.');
      }
      if (running == null) runTimer(taskId, elapsed: Duration.zero);
      return _timerReply(message: 'Timer started.');
    }
    if (path.endsWith('/timers/stop')) {
      if (running == null) return FakeReply.error(409, 'NO_TIMER_RUNNING', 'No timer is running.');
      final log = _close(note: body['note'] as String?);
      if (body['complete_task'] == true) {
        final (_, task) = _findTask(log['task_id'] as String);
        task['status'] = 'completed';
      }
      return _timerReply(stopped: log, taskId: log['task_id'] as String, message: 'Timer paused. Work logged.');
    }
    if (path.endsWith('/timers/switch')) {
      if (running != null) _close(note: body['note'] as String?);
      runTimer(body['task_id'] as String, elapsed: Duration.zero);
      return _timerReply(message: 'Switched.');
    }
    final logsMatch = RegExp(r'/tasks/([0-9a-f-]{36})/work-logs$').firstMatch(path);
    if (logsMatch != null && r.method == 'GET') {
      final taskId = logsMatch.group(1)!;
      return FakeReply.ok([
        if (running?['task_id'] == taskId) _entry(running!),
        for (final log in logs.reversed.where((l) => l['task_id'] == taskId)) _entry(log),
      ]);
    }
    if (logsMatch != null && r.method == 'POST') {
      final (job, task) = _findTask(logsMatch.group(1)!);
      final seconds = (body['duration_seconds'] as int?) ?? DateTime.parse(body['ended_at'] as String).difference(DateTime.parse(body['started_at'] as String)).inSeconds;
      final end = DateTime.now().toUtc();
      final log = {'id': _id('eeee'), 'task_id': task['id'], 'entry_type': 'manual', 'started_at': end.subtract(Duration(seconds: seconds)), 'ended_at': end, 'note': body['note'] ?? 'Adjustment'};
      logs.add(log);
      task['actual_seconds'] = (task['actual_seconds'] as int) + seconds;
      return FakeReply(201, {'success': true, 'message': 'Work added.', 'data': {'entry': _entry(log), 'job': present(job)}});
    }
    return null;
  }

  FakeReply _status(Map<String, dynamic> job, Map<String, dynamic> body) {
    final to = body['status'] as String;
    if (!(_transitions[job['status']]!).contains(to)) {
      return FakeReply.error(409, 'INVALID_STATUS_TRANSITION', 'A job that is ${_labels[job['status']]!.toLowerCase()} cannot be changed to ${_labels[to]!.toLowerCase()}.');
    }
    final tasks = (job['tasks'] as List).cast<Map<String, dynamic>>();
    if (to == 'ready_for_collection' && body['force'] != true) {
      final open = tasks.where((t) => (t['task_type'] as Map)['kind'] == 'work' && !['completed', 'skipped'].contains(t['status'])).toList();
      if (open.isNotEmpty) {
        return FakeReply.error(409, 'TASKS_INCOMPLETE', '${open.length} stages are not finished yet: ${open.map((t) => t['name']).join(', ')}.');
      }
    }
    job
      ..['status'] = to
      ..['version'] = (job['version'] as int) + 1;
    for (final t in tasks.where((t) => (t['task_type'] as Map)['code'] == 'ready_for_collection')) {
      final reached = ['ready_for_collection', 'completed'].contains(to);
      t
        ..['status'] = reached ? 'completed' : 'pending'
        ..['completed_at'] = reached ? '2026-10-08T12:00:00.000Z' : null;
    }
    return FakeReply.ok(present(job), message: 'Job is now ${_labels[to]!.toLowerCase()}.');
  }
}
