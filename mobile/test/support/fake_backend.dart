import 'package:dio/dio.dart';

import 'fake_jobs.dart';
import 'fakes.dart';

/// In-memory stand-in for the customer + measurement endpoints (same envelope and rules as Laravel),
/// so screens can be exercised end-to-end in widget tests.
class FakeBackend {
  FakeBackend() {
    adapter = FakeAdapter(_handle);
  }

  late final FakeAdapter adapter;
  final customers = <Map<String, dynamic>>[];
  final sets = <Map<String, dynamic>>[]; // newest last
  final requests = <String>[];

  /// Jobs, stages and garment templates.
  late final jobs = FakeJobs((id) => customers.where((c) => c['id'] == id).firstOrNull);

  static const groups = [
    {
      'id': 1,
      'code': 'upper_body',
      'name': 'Upper Body / Jacket & Shirt',
      'fields': [
        {'id': 3, 'code': 'chest', 'label': 'Chest', 'value_type': 'length', 'choice_options': null, 'min_cm': 60, 'max_cm': 200, 'help_text': null},
        {'id': 4, 'code': 'waist', 'label': 'Waist (natural)', 'value_type': 'length', 'choice_options': null, 'min_cm': 50, 'max_cm': 200, 'help_text': null},
      ],
    },
    {
      'id': 3,
      'code': 'posture',
      'name': 'Posture & Fit',
      'fields': [
        {'id': 20, 'code': 'shoulder_slope', 'label': 'Shoulder Slope', 'value_type': 'choice', 'choice_options': ['Level', 'Low left', 'Low right'], 'min_cm': null, 'max_cm': null, 'help_text': null},
      ],
    },
  ];

  Map<String, dynamic> addCustomer(String name, {String? phone, int sets = 0, int activeJobs = 0}) {
    final id = '0192f0a1-0000-7000-8000-${(customers.length + 1).toString().padLeft(12, '0')}';
    final customer = {
      'id': id,
      'full_name': name,
      'phone': phone,
      'phone_alt': null,
      'email': null,
      'address': null,
      'notes': null,
      'style_preferences': null,
      'preferred_unit': null,
      'is_archived': false,
      'version': 1,
      'summary': {'active_jobs': activeJobs, 'completed_jobs': 0, 'measurement_sets': sets, 'last_measured_at': null},
      'created_at': '2026-01-15T10:00:00.000Z',
      'updated_at': '2026-01-15T10:00:00.000Z',
    };
    customers.add(customer);
    return customer;
  }

  void addSet(String customerId, Map<int, double> cmValues, {String unit = 'in', DateTime? at, String? notes, Map<int, String> texts = const {}}) {
    sets.add({
      'id': '0192f0a1-5555-7000-8000-${(sets.length + 1).toString().padLeft(12, '0')}',
      'customer_id': customerId,
      'measured_at': (at ?? DateTime.utc(2026, 10, 1)).toIso8601String(),
      'entered_unit': unit,
      'notes': notes,
      'supersedes_set_id': null,
      'recorded_by': 'Marcus Owusu',
      'values': [
        for (final e in cmValues.entries) {'field_id': e.key, 'code': _code(e.key), 'label': _label(e.key), 'value_cm': e.value, 'value': null, 'value_text': null},
        for (final e in texts.entries) {'field_id': e.key, 'code': _code(e.key), 'label': _label(e.key), 'value_cm': null, 'value': null, 'value_text': e.value},
      ],
      'created_at': (at ?? DateTime.utc(2026, 10, 1)).toIso8601String(),
    });
  }

  static Map<String, dynamic> _field(int id) =>
      groups.expand((g) => (g['fields']! as List).cast<Map<String, dynamic>>()).firstWhere((f) => f['id'] == id);
  static String _code(int id) => _field(id)['code'] as String;
  static String _label(int id) => _field(id)['label'] as String;

  FakeReply _handle(RequestOptions r) {
    final path = r.path;
    requests.add('${r.method} $path');
    if (path.endsWith('/auth/me')) return FakeReply.ok({'user': userJson(), 'business': businessJson});
    if (path.endsWith('/measurement-fields')) return FakeReply.ok(groups);
    if (jobs.handle(r) case final reply?) return reply;

    final customerMatch = RegExp(r'/customers/([0-9a-f-]{36})(/.*)?$').firstMatch(path);
    if (r.method == 'GET' && path.endsWith('/customers')) {
      final q = (r.queryParameters['q'] as String? ?? '').toLowerCase();
      final archived = r.queryParameters['status'] == 'archived';
      final items = customers
          .where((c) => (c['is_archived'] as bool) == archived && (q.isEmpty || (c['full_name'] as String).toLowerCase().contains(q)))
          .toList();
      return FakeReply.ok(items, meta: {'pagination': {'page': 1, 'per_page': 30, 'total': items.length, 'total_pages': 1}});
    }
    if (r.method == 'POST' && path.endsWith('/customers')) {
      final body = r.data as Map<String, dynamic>;
      final dupe = customers.where((c) => body['phone'] != null && c['phone'] == body['phone']).toList();
      if (dupe.isNotEmpty && body['allow_duplicate_phone'] != true) {
        return FakeReply.error(409, 'DUPLICATE_PHONE', 'This phone number is already used by ${dupe.first['full_name']}.', errors: {
          'phone': ['Already used by ${dupe.first['full_name']}.'],
        });
      }
      final created = addCustomer(body['full_name'] as String, phone: body['phone'] as String?);
      return FakeReply(201, {'success': true, 'message': 'Customer added.', 'data': created});
    }
    if (path.endsWith('/customers/phone-check')) {
      final phone = r.queryParameters['phone'];
      return FakeReply.ok(customers.where((c) => c['phone'] == phone).map((c) => {'id': c['id'], 'full_name': c['full_name'], 'phone': c['phone'], 'is_archived': false}).toList());
    }
    if (customerMatch != null) {
      final id = customerMatch.group(1)!;
      final rest = customerMatch.group(2) ?? '';
      final customer = customers.where((c) => c['id'] == id).firstOrNull;
      if (customer == null) return FakeReply.error(404, 'NOT_FOUND', 'The requested resource was not found.');
      final mine = sets.where((s) => s['customer_id'] == id).toList();
      if (rest.isEmpty && r.method == 'GET') return FakeReply.ok(customer);
      if (rest == '/measurements/current') {
        final latest = <int, Map<String, dynamic>>{};
        for (final s in mine) {
          for (final v in (s['values'] as List).cast<Map<String, dynamic>>()) {
            latest[v['field_id'] as int] = {
              ...v,
              'group_id': 1,
              'value_type': v['value_cm'] == null ? 'choice' : 'length',
              'measurement_set_id': s['id'],
              'measured_at': s['measured_at'],
              'entered_unit': s['entered_unit'],
            };
          }
        }
        return FakeReply.ok({'customer_id': id, 'preferred_unit': null, 'last_measured_at': mine.isEmpty ? null : mine.last['measured_at'], 'values': latest.values.toList()});
      }
      if (rest == '/measurements' && r.method == 'GET') {
        return FakeReply.ok(mine.reversed.toList(), meta: {'pagination': {'page': 1, 'per_page': 50, 'total': mine.length, 'total_pages': 1}});
      }
      if (rest == '/measurements' && r.method == 'POST') {
        final body = r.data as Map<String, dynamic>;
        final unit = body['entered_unit'] as String;
        final values = (body['values'] as List).cast<Map<String, dynamic>>();
        for (final (i, v) in values.indexed) {
          if (v['value'] != null && (v['value'] as num) > 150) {
            return FakeReply.error(422, 'VALIDATION_FAILED', 'Some measurements are invalid.', errors: {
              'values.$i.value': ['${_label(v['field_id'] as int)} must be between 23.62 and 78.74 in.'],
            });
          }
        }
        addSet(
          id,
          {for (final v in values.where((v) => v['value'] != null)) v['field_id'] as int: (v['value'] as num).toDouble() * (unit == 'in' ? 2.54 : 1)},
          unit: unit,
          at: DateTime.now().toUtc(),
          notes: body['notes'] as String?,
          texts: {for (final v in values.where((v) => v['value_text'] != null)) v['field_id'] as int: v['value_text'] as String},
        );
        return FakeReply(201, {'success': true, 'message': 'Measurements saved.', 'data': sets.last});
      }
    }
    return FakeReply.error(404, 'NOT_FOUND', 'Unhandled fake route $path');
  }
}
