/// Report responses in the shape of GET /reports/{key} (values as the Laravel ReportService returns them).
Map<String, dynamic> reportFixture(String key, {required String from, required String to}) {
  final start = DateTime.parse(from);
  final days = DateTime.parse(to).difference(start).inDays + 1;
  String day(int i) => start.add(Duration(days: i)).toIso8601String().substring(0, 10);
  final period = {'from': from, 'to': to, 'group_by': 'day', 'days': days};
  List<Map<String, dynamic>> series(Map<String, num> Function(int i) values) => [for (var i = 0; i < days; i++) {'period': day(i), ...values(i)}];

  return switch (key) {
    'jobs' => {
        'period': period,
        'totals': {'created': 4, 'completed': 2, 'cancelled': 1, 'on_time': 1, 'late': 1, 'on_time_rate': 50.0, 'average_days_vs_due': -1.5, 'average_lead_days': 11.5, 'garments_completed': 2},
        'now': {'open': 3, 'queued': 1, 'in_progress': 1, 'on_hold': 0, 'ready_for_collection': 1, 'overdue': 1},
        'by_job_type': [
          {'job_type_id': 1, 'name': '3-Piece Suit', 'created': 3, 'completed': 2, 'on_time': 1, 'late': 1},
          {'job_type_id': 6, 'name': 'Kaftan', 'created': 1, 'completed': 0, 'on_time': 0, 'late': 0},
        ],
        'series': series((i) => {'created': i % 7 == 0 ? 1 : 0, 'completed': i % 9 == 3 ? 1 : 0}),
      },
    'hours' => {
        'period': period,
        'totals': {'jobs': 2, 'garments': 2, 'estimated_seconds': 86400, 'actual_seconds': 82800, 'variance_seconds': -3600, 'variance_percent': -4.2, 'actual_seconds_per_garment': 41400, 'logged_seconds': 86400},
        'by_job_type': [
          {'job_type_id': 1, 'name': '3-Piece Suit', 'jobs': 2, 'garments': 2, 'estimated_seconds': 86400, 'actual_seconds': 82800, 'variance_seconds': -3600, 'variance_percent': -4.2, 'actual_seconds_per_garment': 41400},
        ],
        'by_stage': [
          {'task_type_id': 2, 'name': 'Cutting', 'tasks': 2, 'estimated_seconds': 21600, 'actual_seconds': 21600, 'variance_seconds': 0, 'variance_percent': 0.0},
          {'task_type_id': 3, 'name': 'Sewing', 'tasks': 2, 'estimated_seconds': 64800, 'actual_seconds': 61200, 'variance_seconds': -3600, 'variance_percent': -5.6},
        ],
        'series': series((i) => {'logged_seconds': (i % 3) * 7200}),
      },
    'workload' => {
        'period': period,
        'totals': {'capacity_seconds': 172800, 'planned_seconds': 14400, 'logged_seconds': 28800, 'load_percent': 8.3, 'capacity_hours_per_day': 8.0},
        'backlog': {'jobs': 2, 'remaining_seconds': 43200, 'due_in_period_seconds': 21600},
        'series': series((i) => {'capacity_seconds': i % 7 == 6 ? 0 : 28800, 'planned_seconds': i == 2 ? 14400 : 0, 'logged_seconds': i == 1 ? 28800 : 0}),
      },
    'customers' => {
        'period': period,
        'totals': {'customers': 12, 'new_customers': 2, 'ordering_customers': 2, 'returning_customers': 1, 'first_time_customers': 1, 'active_customers': 3},
        'top_customers': [
          {'customer_id': '0192f0a1-cccc-7000-8000-000000000001', 'name': 'Kofi Mensah', 'jobs': 2, 'completed': 0},
          {'customer_id': '0192f0a1-cccc-7000-8000-000000000002', 'name': 'Ama Mensah', 'jobs': 1, 'completed': 1},
        ],
        'series': series((i) => {'new_customers': i == 4 ? 2 : 0}),
      },
    'inventory' => {
        'period': period,
        'now': {'materials': 5, 'ok': 3, 'low': 1, 'out': 1, 'negative': 0, 'stock_value': 4980.5},
        'attention': [
          {'item_id': '0192f0a1-1111-7000-8000-000000000001', 'item_name': 'Horsehair Canvas', 'unit': 'm', 'min_stock_level': 5.0, 'quantity_on_hand': 0.0, 'stock_status': 'out'},
          {'item_id': '0192f0a1-1111-7000-8000-000000000002', 'item_name': 'Silk Basting Thread', 'unit': 'spool', 'min_stock_level': 10.0, 'quantity_on_hand': 3.0, 'stock_status': 'low'},
        ],
        'totals': {'usage_entries': 2, 'purchase_entries': 1, 'write_off_entries': 1, 'used_value': 500.0},
        'consumption': [
          {'item_id': '0192f0a1-1111-7000-8000-000000000003', 'item_name': 'Super 150s Wool', 'category_name': 'Fabric', 'unit': 'm', 'used': 6.0, 'returned': 1.0, 'net_used': 5.0, 'purchased': 25.0, 'written_off': 2.0, 'adjusted': 0.0, 'used_value': 500.0},
        ],
        'by_category': [
          {'category_name': 'Fabric', 'materials': 1, 'used_value': 500.0},
        ],
        'series': series((i) => {'usage_entries': i == 3 ? 2 : 0, 'purchase_entries': i == 5 ? 1 : 0}),
      },
    'tools' => {
        'period': period,
        'now': {'tools': 4, 'operational': 3, 'needs_service': 1, 'out_of_service': 0},
        'overdue': [
          {'tool_id': '0192f0a1-7777-7000-8000-000000000001', 'tool_name': 'Lockstitch #01', 'operational_status': 'operational', 'next_maintenance_date': day(0), 'days_until_due': -10},
        ],
        'due_soon': [
          {'tool_id': '0192f0a1-7777-7000-8000-000000000002', 'tool_name': 'Lockstitch #02', 'operational_status': 'operational', 'next_maintenance_date': to, 'days_until_due': 3},
        ],
        'not_working': [],
        'totals': {'services': 2},
        'by_type': [
          {'maintenance_type': 'repair', 'services': 1},
          {'maintenance_type': 'inspection', 'services': 1},
        ],
        'by_tool': [
          {'tool_id': '0192f0a1-7777-7000-8000-000000000003', 'tool_name': 'Steam Press', 'services': 2, 'last_service': to},
        ],
        'series': series((i) => {'services': i == days - 2 ? 2 : 0}),
      },
    _ => throw ArgumentError(key),
  };
}
