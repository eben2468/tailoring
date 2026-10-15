/// The configuration downloaded from GET /sync/config: garment types with templates, production
/// stages, measurement fields and business settings. Read-only on the device.
class ConfigBundle {
  ConfigBundle({required this.version, required this.settings, required this.taskTypes, required this.jobTypes, required this.measurementGroups, this.inventoryCategories = const [], this.toolCategories = const []});

  factory ConfigBundle.fromJson(Map<String, dynamic> json) => ConfigBundle(
        version: (json['config_version'] as num?)?.toInt() ?? 0,
        settings: (json['settings'] as Map?)?.cast<String, dynamic>() ?? const {},
        taskTypes: _list(json['task_types']),
        jobTypes: _list(json['job_types']),
        measurementGroups: _list(json['measurement_groups']),
        inventoryCategories: _list(json['inventory_categories']),
        toolCategories: _list(json['tool_categories']),
      );

  final int version;
  final Map<String, dynamic> settings;
  final List<Map<String, dynamic>> taskTypes;
  final List<Map<String, dynamic>> jobTypes;
  final List<Map<String, dynamic>> measurementGroups;

  /// Material categories (Fabric, Thread …), inactive ones included (old items keep their category).
  final List<Map<String, dynamic>> inventoryCategories;

  /// Tool categories (Sewing Machines, Irons & Pressing …), inactive ones included.
  final List<Map<String, dynamic>> toolCategories;

  late final Map<int, Map<String, dynamic>> _taskTypes = {for (final t in taskTypes) (t['id'] as num).toInt(): t};
  late final Map<int, Map<String, dynamic>> _jobTypes = {for (final t in jobTypes) (t['id'] as num).toInt(): t};
  late final Map<int, Map<String, dynamic>> _fields = {
    for (final (gi, g) in measurementGroups.indexed)
      for (final (fi, f) in _list(g['fields']).indexed) (f['id'] as num).toInt(): {...f, 'group_id': g['id'], 'group_order': gi, 'sort_order': fi},
  };

  Map<String, dynamic>? taskType(int id) => _taskTypes[id];

  Map<String, dynamic>? inventoryCategory(int id) => inventoryCategories.where((c) => (c['id'] as num).toInt() == id).firstOrNull;

  Map<String, dynamic>? toolCategory(int id) => toolCategories.where((c) => (c['id'] as num).toInt() == id).firstOrNull;

  int get maintenanceDueSoonDays => (settings['tools.maintenance_due_soon_days'] as num?)?.toInt() ?? 7;

  Map<String, dynamic>? taskTypeByCode(String code) => taskTypes.where((t) => t['code'] == code).firstOrNull;

  Map<String, dynamic>? jobType(int id) => _jobTypes[id];

  /// Measurement field with its group_id.
  Map<String, dynamic>? field(int id) => _fields[id];

  bool isMilestone(int taskTypeId) => taskType(taskTypeId)?['kind'] == 'milestone';

  String get timezone => settings['business.timezone'] as String? ?? 'Africa/Accra';

  int get dueSoonDays => (settings['jobs.due_soon_days'] as num?)?.toInt() ?? 3;

  int get reviewThresholdSeconds => ((settings['timer.review_threshold_hours'] as num?)?.toInt() ?? 12) * 3600;

  Map<String, dynamic> toJson() => {
        'config_version': version,
        'settings': settings,
        'task_types': taskTypes,
        'job_types': jobTypes,
        'measurement_groups': measurementGroups,
        'inventory_categories': inventoryCategories,
        'tool_categories': toolCategories,
      };

  static List<Map<String, dynamic>> _list(Object? value) => (value as List<dynamic>? ?? const []).cast<Map<dynamic, dynamic>>().map((m) => m.cast<String, dynamic>()).toList();
}

/// Hour and progress rules (ARCHITECTURE §9.2) — the same as the server's views and HoursCalculator.
/// Durations in seconds; percentages rounded to 2 decimals.
abstract final class Hours {
  static const unfinishedCap = 99.0;

  static ({int remaining, int overrun, double progress, bool manual}) task({
    required String status,
    required int estimated,
    required int actual,
    double? override,
  }) {
    final closed = status == 'completed' || status == 'skipped';
    final double progress;
    if (status == 'completed') {
      progress = 100;
    } else if (override != null) {
      progress = override;
    } else if (estimated > 0) {
      progress = (actual / estimated * 100).clamp(0, unfinishedCap).toDouble();
    } else {
      progress = 0;
    }
    return (
      remaining: closed ? 0 : (estimated - actual).clamp(0, estimated),
      overrun: (actual - estimated).clamp(0, actual < 0 ? 0 : actual),
      progress: _round(progress),
      manual: override != null && status != 'completed',
    );
  }

  /// Job totals over WORK tasks (milestones excluded by the caller).
  static ({int estimated, int actual, int remaining, int overrun, int count, int completed, double progress, bool manual}) job({
    required String jobStatus,
    double? override,
    required List<({String status, int estimated, int actual, double? override})> workTasks,
  }) {
    var estimated = 0, actual = 0, remaining = 0, overrun = 0, count = 0, completed = 0;
    var weighted = 0.0;
    for (final t in workTasks) {
      final calc = task(status: t.status, estimated: t.estimated, actual: t.actual, override: t.override);
      actual += t.actual;
      remaining += calc.remaining;
      overrun += calc.overrun;
      if (t.status == 'skipped') continue;
      count++;
      if (t.status == 'completed') completed++;
      estimated += t.estimated;
      weighted += calc.progress * t.estimated;
    }
    final double progress;
    if (override != null) {
      progress = override;
    } else if (jobStatus == 'ready_for_collection' || jobStatus == 'completed') {
      progress = 100;
    } else if (estimated > 0) {
      progress = weighted / estimated;
    } else {
      progress = count > 0 ? completed * 100 / count : 0;
    }
    return (
      estimated: estimated,
      actual: actual,
      remaining: remaining,
      overrun: overrun,
      count: count,
      completed: completed,
      progress: _round(progress),
      manual: override != null,
    );
  }

  static double _round(double v) => (v * 100).roundToDouble() / 100;
}

/// Job status state machine (ARCHITECTURE §9.5), as enforced by the server.
abstract final class JobStatusRules {
  static const transitions = {
    'draft': ['queued', 'cancelled'],
    'queued': ['in_progress', 'cancelled'],
    'in_progress': ['on_hold', 'ready_for_collection', 'cancelled'],
    'on_hold': ['in_progress', 'cancelled'],
    'ready_for_collection': ['completed', 'in_progress', 'cancelled'],
    'completed': <String>[],
    'cancelled': <String>[],
  };

  static const labels = {
    'draft': 'Draft',
    'queued': 'Queued',
    'in_progress': 'In production',
    'on_hold': 'On hold',
    'ready_for_collection': 'Ready for collection',
    'completed': 'Collected',
    'cancelled': 'Cancelled',
  };

  static const production = ['queued', 'in_progress', 'on_hold'];

  static List<String> allowed(String from) => transitions[from] ?? const [];

  static String label(String status) => labels[status] ?? status;
}

/// Stock rules (ARCHITECTURE §11): the same as the server's v_inventory_stock / InventoryStock /
/// InventoryService. Quantities have 3 decimals; count units take whole numbers.
abstract final class StockRules {
  static const countUnits = {'pcs', 'spool', 'cone', 'roll', 'set', 'box', 'pack'};
  static const additions = {'opening', 'purchase', 'return'};
  static const reductions = {'usage', 'write_off'};
  static const jobTypes = {'usage', 'return'};

  static bool isCounted(String unit) => countUnits.contains(unit);

  static double round(num v) => (v * 1000).round() / 1000;

  /// Σ quantity_change of the non-voided transactions.
  static double onHand(Iterable<Map<String, dynamic>> transactions) =>
      round(transactions.where((t) => t['deleted_at'] == null).fold<double>(0, (s, t) => s + (t['quantity_change'] as num).toDouble()));

  /// negative (< 0) → out (≤ 0) → low (≤ minimum) → ok.
  static String status(double onHand, double minLevel) => onHand < 0
      ? 'negative'
      : onHand <= 0
          ? 'out'
          : onHand <= minLevel
              ? 'low'
              : 'ok';

  /// "18.5", "3", "-1.5" (up to 3 decimals, no trailing zeros).
  static String number(num v) {
    final s = round(v).toStringAsFixed(3);
    return s.replaceFirst(RegExp(r'\.?0+$'), '');
  }

  /// "spools" / "spool" / "m" (lengths and weights keep their symbol).
  static String unitName(String unit, num count) {
    if (!isCounted(unit) || unit == 'pcs' || count.abs() == 1) return unit;
    return unit == 'box' ? 'boxes' : '${unit}s';
  }

  /// "3 spools", "18.5 m" — as in the API's messages.
  static String quantity(num v, String unit) => '${number(v)} ${unitName(unit, v)}';
}

/// Tool maintenance rules (ARCHITECTURE §12): the same as the server's v_tool_maintenance_status /
/// ToolMaintenance. Dates are business dates ("2026-10-09").
abstract final class MaintenanceRules {
  static DateTime _d(String ymd) => DateTime.utc(int.parse(ymd.substring(0, 4)), int.parse(ymd.substring(5, 7)), int.parse(ymd.substring(8, 10)));

  static String ymd(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  static String addDays(String ymd, int days) => MaintenanceRules.ymd(_d(ymd).add(Duration(days: days)));

  /// Whole days from [from] to [to] (negative when [to] is earlier).
  static int daysBetween(String from, String to) => _d(to).difference(_d(from)).inDays;

  /// Override, else (last maintenance | purchase date | created date) + interval; null without a schedule.
  static String? next({String? override, int? intervalDays, String? last, String? purchaseDate, required String createdDate}) {
    if (override != null) return override;
    if (intervalDays == null) return null;
    return addDays(last ?? purchaseDate ?? createdDate, intervalDays);
  }

  /// none (no schedule or retired) → overdue (< today) → due_soon (≤ today + window) → ok.
  static ({String state, int? days}) state(String? next, String status, String today, int dueSoonDays) {
    if (next == null || status == 'retired') return (state: 'none', days: null);
    final days = daysBetween(today, next);
    return (state: days < 0 ? 'overdue' : (days <= dueSoonDays ? 'due_soon' : 'ok'), days: days);
  }
}
