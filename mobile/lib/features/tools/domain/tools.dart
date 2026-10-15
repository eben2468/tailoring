import 'package:flutter/widgets.dart';
import 'package:material_symbols_icons/symbols.dart';

enum ToolCondition {
  excellent('Excellent'),
  good('Good'),
  fair('Fair'),
  poor('Poor');

  const ToolCondition(this.label);

  final String label;

  static ToolCondition parse(String? value) => values.firstWhere((c) => c.name == value, orElse: () => good);
}

enum ToolStatus {
  operational('Operational', 'operational'),
  needsService('Svc Pending', 'needs_service'),
  outOfService('Out of Service', 'out_of_service'),
  retired('Retired', 'retired');

  const ToolStatus(this.label, this.api);

  final String label;
  final String api;

  /// Longer wording for choices ("Needs service").
  String get choiceLabel => switch (this) {
        needsService => 'Needs service',
        outOfService => 'Out of service',
        _ => label,
      };

  static ToolStatus parse(String? value) => values.firstWhere((s) => s.api == value, orElse: () => operational);
}

/// Maintenance schedule state (ToolMaintenance / MaintenanceRules).
enum MaintenanceState {
  none,
  ok,
  dueSoon,
  overdue;

  static MaintenanceState parse(String? value) => switch (value) {
        'ok' => ok,
        'due_soon' => dueSoon,
        'overdue' => overdue,
        _ => none,
      };
}

enum MaintenanceType {
  routine('Routine service', Symbols.build),
  repair('Repair', Symbols.handyman),
  calibration('Calibration', Symbols.tune),
  inspection('Inspection', Symbols.search_check),
  sharpening('Sharpening', Symbols.content_cut),
  cleaning('Cleaning', Symbols.water_drop),
  other('Other', Symbols.more_horiz);

  const MaintenanceType(this.label, this.icon);

  final String label;
  final IconData icon;

  static MaintenanceType parse(String? value) => values.firstWhere((t) => t.name == value, orElse: () => other);
}

class Tool {
  const Tool({
    required this.id,
    required this.categoryId,
    required this.name,
    required this.condition,
    required this.status,
    required this.maintenanceCount,
    required this.maintenanceState,
    required this.version,
    this.categoryName,
    this.brandModel,
    this.serialNumber,
    this.purchaseDate,
    this.storageLocation,
    this.intervalDays,
    this.nextOverride,
    this.notes,
    this.lastMaintenance,
    this.nextMaintenance,
    this.daysUntilDue,
    this.archivedAt,
  });

  factory Tool.fromJson(Map<String, dynamic> json) => Tool(
        id: json['id'] as String,
        categoryId: (json['category_id'] as num).toInt(),
        categoryName: json['category_name'] as String?,
        name: json['tool_name'] as String,
        brandModel: json['brand_model'] as String?,
        serialNumber: json['serial_number'] as String?,
        purchaseDate: _date(json['purchase_date']),
        condition: ToolCondition.parse(json['tool_condition'] as String?),
        status: ToolStatus.parse(json['operational_status'] as String?),
        storageLocation: json['storage_location'] as String?,
        intervalDays: (json['maintenance_interval_days'] as num?)?.toInt(),
        nextOverride: _date(json['next_maintenance_override']),
        notes: json['notes'] as String?,
        lastMaintenance: _date(json['last_maintenance_date']),
        maintenanceCount: (json['maintenance_count'] as num? ?? 0).toInt(),
        nextMaintenance: _date(json['next_maintenance_date']),
        maintenanceState: MaintenanceState.parse(json['maintenance_state'] as String?),
        daysUntilDue: (json['days_until_due'] as num?)?.toInt(),
        archivedAt: DateTime.tryParse(json['archived_at'] as String? ?? '')?.toLocal(),
        version: (json['version'] as num).toInt(),
      );

  /// Business dates ("2026-10-09") as local midnight.
  static DateTime? _date(Object? v) => v is String && v.length >= 10 ? DateTime(int.parse(v.substring(0, 4)), int.parse(v.substring(5, 7)), int.parse(v.substring(8, 10))) : null;

  final String id;
  final int categoryId;
  final String? categoryName;
  final String name;
  final String? brandModel;
  final String? serialNumber;
  final DateTime? purchaseDate;
  final ToolCondition condition;
  final ToolStatus status;
  final String? storageLocation;
  final int? intervalDays;
  final DateTime? nextOverride;
  final String? notes;
  final DateTime? lastMaintenance;
  final int maintenanceCount;
  final DateTime? nextMaintenance;
  final MaintenanceState maintenanceState;
  final int? daysUntilDue;
  final DateTime? archivedAt;
  final int version;

  bool get isArchived => archivedAt != null;

  /// Overdue, due soon, or not in working order.
  bool get needsAttention =>
      maintenanceState == MaintenanceState.overdue || maintenanceState == MaintenanceState.dueSoon || status == ToolStatus.needsService || status == ToolStatus.outOfService;

  /// "Due in 46 days" · "Due today" · "Overdue by 3 days" · "No schedule".
  String get dueLabel {
    final d = daysUntilDue;
    if (d == null) return status == ToolStatus.retired ? 'Retired' : 'No schedule';
    if (d < 0) return 'Overdue by ${-d} day${d == -1 ? '' : 's'}';
    if (d == 0) return 'Due today';
    if (d == 1) return 'Due tomorrow';
    return 'Due in $d days';
  }
}

class MaintenanceLog {
  const MaintenanceLog({required this.id, required this.toolId, required this.performedOn, required this.type, this.description, this.performedBy, this.conditionAfter, this.recordedBy});

  factory MaintenanceLog.fromJson(Map<String, dynamic> json) => MaintenanceLog(
        id: json['id'] as String,
        toolId: json['tool_id'] as String,
        performedOn: Tool._date(json['performed_on'])!,
        type: MaintenanceType.parse(json['maintenance_type'] as String?),
        description: json['description'] as String?,
        performedBy: json['performed_by'] as String?,
        conditionAfter: json['condition_after'] == null ? null : ToolCondition.parse(json['condition_after'] as String),
        recordedBy: json['recorded_by'] as String?,
      );

  final String id;
  final String toolId;
  final DateTime performedOn;
  final MaintenanceType type;
  final String? description;
  final String? performedBy;
  final ToolCondition? conditionAfter;
  final String? recordedBy;
}

/// GET /tools/summary.
class ToolSummary {
  const ToolSummary({
    required this.total,
    required this.operational,
    required this.needsService,
    required this.outOfService,
    required this.retired,
    required this.dueSoon,
    required this.overdue,
    required this.byCategory,
    required this.alerts,
  });

  factory ToolSummary.fromJson(Map<String, dynamic> json) => ToolSummary(
        total: (json['total_tools'] as num).toInt(),
        operational: (json['operational'] as num).toInt(),
        needsService: (json['needs_service'] as num).toInt(),
        outOfService: (json['out_of_service'] as num).toInt(),
        retired: (json['retired'] as num).toInt(),
        dueSoon: (json['due_soon'] as num).toInt(),
        overdue: (json['overdue'] as num).toInt(),
        byCategory: {for (final c in (json['by_category'] as List? ?? const []).cast<Map<String, dynamic>>()) (c['category_id'] as num).toInt(): (c['tools'] as num).toInt()},
        alerts: [for (final t in (json['alerts'] as List).cast<Map<String, dynamic>>()) Tool.fromJson(t)],
      );

  final int total;
  final int operational;
  final int needsService;
  final int outOfService;
  final int retired;
  final int dueSoon;
  final int overdue;
  final Map<int, int> byCategory;

  /// Overdue → out of service → needs service → due soon.
  final List<Tool> alerts;
}
