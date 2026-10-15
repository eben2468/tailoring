import '../../ai/domain/ai.dart';
import '../../calendar/domain/calendar.dart';
import '../../inventory/domain/inventory.dart';
import '../../jobs/domain/job.dart';
import '../../tools/domain/tools.dart';

/// GET /dashboard (or Presenter.dashboard offline): the owner's day on one screen.
class Dashboard {
  const Dashboard({
    required this.date,
    required this.shop,
    required this.counts,
    required this.appointmentsToday,
    required this.workload,
    required this.schedule,
    required this.priorityJobs,
    required this.inventoryAlertCount,
    required this.inventoryAlerts,
    required this.maintenanceAlertCount,
    required this.maintenanceAlerts,
    required this.insights,
  });

  factory Dashboard.fromJson(Map<String, dynamic> json) {
    List<Map<String, dynamic>> list(String key) => (json[key] as List? ?? const []).cast<Map<dynamic, dynamic>>().map((m) => m.cast<String, dynamic>()).toList();
    Map<String, dynamic> map(String key) => (json[key] as Map?)?.cast<String, dynamic>() ?? const {};
    final appointments = map('appointments_today');
    return Dashboard(
      date: DateTime.parse(json['date'] as String),
      shop: ShopStatus.fromJson(map('shop')),
      counts: map('counts').map((k, v) => MapEntry(k, (v as num?)?.toInt())),
      appointmentsToday: (
        total: (appointments['total'] as num? ?? 0).toInt(),
        fittings: (appointments['fittings'] as num? ?? 0).toInt(),
        collections: (appointments['collections'] as num? ?? 0).toInt(),
      ),
      workload: Workload.fromJson(map('workload')),
      schedule: list('schedule').map(ScheduleItem.fromJson).toList(),
      priorityJobs: list('priority_jobs').map(Job.fromJson).toList(),
      inventoryAlertCount: (json['inventory_alert_count'] as num? ?? 0).toInt(),
      inventoryAlerts: list('inventory_alerts').map(InventoryItem.fromJson).toList(),
      maintenanceAlertCount: (json['maintenance_alert_count'] as num? ?? 0).toInt(),
      maintenanceAlerts: list('maintenance_alerts').map(Tool.fromJson).toList(),
      insights: list('insights').map(Insight.fromJson).toList(),
    );
  }

  /// Today in the business timezone.
  final DateTime date;
  final ShopStatus shop;

  /// open, active, at_fitting, queued, ready_for_collection, due_today, overdue, most_days_late, due_this_week.
  final Map<String, int?> counts;
  final ({int total, int fittings, int collections}) appointmentsToday;
  final Workload workload;

  /// Timer, planned stages and appointments by time, then up to 3 "up next" stages.
  final List<ScheduleItem> schedule;
  final List<Job> priorityJobs;
  final int inventoryAlertCount;
  final List<InventoryItem> inventoryAlerts;
  final int maintenanceAlertCount;
  final List<Tool> maintenanceAlerts;
  final List<Insight> insights;

  int count(String key) => counts[key] ?? 0;

  int get alertCount => inventoryAlertCount + maintenanceAlertCount;

  ScheduleItem? get nextUp => schedule.where((i) => i.kind == ScheduleKind.next).firstOrNull;
}

/// Today's opening hours (settings: schedule.working_hours).
class ShopStatus {
  const ShopStatus({required this.isOpen, this.opensAt, this.closesAt});

  factory ShopStatus.fromJson(Map<String, dynamic> json) => ShopStatus(isOpen: json['is_open'] == true, opensAt: json['opens_at'] as String?, closesAt: json['closes_at'] as String?);

  final bool isOpen;

  /// "08:00"; null when the shop is closed all day.
  final String? opensAt;
  final String? closesAt;
}

/// Remaining hours of the stages on the bench (in progress, or planned for today), per stage type.
class Workload {
  const Workload({required this.remainingSeconds, required this.capacitySeconds, required this.byStage});

  factory Workload.fromJson(Map<String, dynamic> json) => Workload(
    remainingSeconds: (json['remaining_seconds'] as num? ?? 0).toInt(),
    capacitySeconds: (json['capacity_seconds'] as num? ?? 0).toInt(),
    byStage: [
      for (final s in (json['by_stage'] as List? ?? const []).cast<Map<dynamic, dynamic>>())
        (name: s['name'] as String, colorKey: s['color_key'] as String?, remainingSeconds: (s['remaining_seconds'] as num).toInt()),
    ],
  );

  final int remainingSeconds;

  /// Bench hours available today (0 when the shop is closed).
  final int capacitySeconds;
  final List<({String name, String? colorKey, int remainingSeconds})> byStage;
}

enum ScheduleKind {
  timer,
  stage,
  appointment,
  next;

  static ScheduleKind parse(String? value) => values.firstWhere((k) => k.name == value, orElse: () => next);
}

/// One line of the production schedule.
class ScheduleItem {
  const ScheduleItem({
    required this.kind,
    required this.title,
    this.startsAt,
    this.endsAt,
    this.jobId,
    this.jobNumber,
    this.jobTitle,
    this.customerName,
    this.taskId,
    this.appointmentId,
    this.appointmentType,
    this.location,
    this.estimatedSeconds,
    this.remainingSeconds,
  });

  factory ScheduleItem.fromJson(Map<String, dynamic> json) {
    DateTime? time(String key) => json[key] == null ? null : DateTime.parse(json[key] as String).toLocal();
    return ScheduleItem(
      kind: ScheduleKind.parse(json['kind'] as String?),
      title: json['title'] as String,
      startsAt: time('starts_at'),
      endsAt: time('ends_at'),
      jobId: json['job_id'] as String?,
      jobNumber: json['job_number'] as String?,
      jobTitle: json['job_title'] as String?,
      customerName: json['customer_name'] as String?,
      taskId: json['task_id'] as String?,
      appointmentId: json['appointment_id'] as String?,
      appointmentType: json['appointment_type'] == null ? null : AppointmentType.parse(json['appointment_type'] as String),
      location: json['location'] as String?,
      estimatedSeconds: (json['estimated_seconds'] as num?)?.toInt(),
      remainingSeconds: (json['remaining_seconds'] as num?)?.toInt(),
    );
  }

  final ScheduleKind kind;

  /// Stage name or appointment title.
  final String title;
  final DateTime? startsAt;
  final DateTime? endsAt;
  final String? jobId;
  final String? jobNumber;
  final String? jobTitle;
  final String? customerName;
  final String? taskId;
  final String? appointmentId;
  final AppointmentType? appointmentType;
  final String? location;
  final int? estimatedSeconds;
  final int? remainingSeconds;
}
