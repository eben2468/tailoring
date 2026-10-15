import 'package:flutter/widgets.dart';
import 'package:material_symbols_icons/symbols.dart';

/// The reports (GET /reports/{key}).
enum ReportKind {
  jobs('jobs', 'Jobs & Deadlines', 'Orders, completions, on-time rate and lead time', Symbols.content_cut),
  hours('hours', 'Hours & Estimates', 'Estimated against actual hours, by garment and stage', Symbols.timer),
  workload('workload', 'Workload & Capacity', 'Planned production against bench capacity', Symbols.calendar_month),
  customers('customers', 'Customers', 'New and returning customers, top customers', Symbols.contacts),
  inventory('inventory', 'Inventory', 'Stock status, consumption and stock value', Symbols.inventory_2),
  tools('tools', 'Tools & Maintenance', 'Service due, overdue and done', Symbols.precision_manufacturing);

  const ReportKind(this.key, this.title, this.description, this.icon);

  final String key;
  final String title;
  final String description;
  final IconData icon;

  static ReportKind? byKey(String key) => values.where((k) => k.key == key).firstOrNull;
}

/// Preset date ranges (business dates, inclusive).
enum ReportPreset {
  last7('7 days'),
  last30('30 days'),
  last90('90 days'),
  thisMonth('This month'),
  lastMonth('Last month'),
  last12Months('12 months');

  const ReportPreset(this.label);

  final String label;

  ReportRange range(DateTime today) {
    final t = DateTime(today.year, today.month, today.day);
    return switch (this) {
      last7 => ReportRange(t.subtract(const Duration(days: 6)), t),
      last30 => ReportRange(t.subtract(const Duration(days: 29)), t),
      last90 => ReportRange(t.subtract(const Duration(days: 89)), t),
      thisMonth => ReportRange(DateTime(t.year, t.month), t),
      lastMonth => ReportRange(DateTime(t.year, t.month - 1), DateTime(t.year, t.month, 0)),
      last12Months => ReportRange(DateTime(t.year - 1, t.month, t.day + 1), t),
    };
  }
}

class ReportRange {
  const ReportRange(this.from, this.to);

  final DateTime from;
  final DateTime to;

  static String _ymd(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  String get fromYmd => _ymd(from);
  String get toYmd => _ymd(to);

  @override
  bool operator ==(Object other) => other is ReportRange && other.fromYmd == fromYmd && other.toYmd == toYmd;

  @override
  int get hashCode => Object.hash(fromYmd, toYmd);
}

/// A report as returned by the API (display-only; every figure is calculated on the server).
class ReportResult {
  const ReportResult({required this.kind, required this.data, required this.fetchedAt, required this.stale});

  final ReportKind kind;
  final Map<String, dynamic> data;
  final DateTime fetchedAt;

  /// Shown from the phone's copy because the server could not be reached.
  final bool stale;

  Map<String, dynamic> section(String key) => (data[key] as Map?)?.cast<String, dynamic>() ?? const {};

  List<Map<String, dynamic>> list(String key) => (data[key] as List? ?? const []).cast<Map<dynamic, dynamic>>().map((m) => m.cast<String, dynamic>()).toList();

  /// day | week | month.
  String get groupBy => section('period')['group_by'] as String? ?? 'day';

  List<Map<String, dynamic>> get series => list('series');
}
