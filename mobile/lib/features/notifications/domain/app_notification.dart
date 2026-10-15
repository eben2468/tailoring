import 'package:flutter/widgets.dart';
import 'package:material_symbols_icons/symbols.dart';

enum NotificationSeverity {
  info,
  warning,
  critical;

  static NotificationSeverity parse(String? v) => values.firstWhere((s) => s.name == v, orElse: () => info);
}

/// One notification (GET /notifications, or the synced `notifications` rows).
class AppNotification {
  const AppNotification({
    required this.id,
    required this.type,
    required this.severity,
    required this.title,
    required this.createdAt,
    this.body,
    this.route,
    this.readAt,
  });

  factory AppNotification.fromJson(Map<String, dynamic> json) => AppNotification(
        id: (json['id'] as num).toInt(),
        type: json['notification_type'] as String,
        severity: NotificationSeverity.parse(json['severity'] as String?),
        title: json['title'] as String,
        body: json['body'] as String?,
        route: json['route'] as String?,
        readAt: DateTime.tryParse(json['read_at'] as String? ?? '')?.toLocal(),
        createdAt: DateTime.parse(json['created_at'] as String).toLocal(),
      );

  final int id;
  final String type;
  final NotificationSeverity severity;
  final String title;
  final String? body;

  /// App route to open (e.g. `/jobs/<id>`).
  final String? route;
  final DateTime? readAt;
  final DateTime createdAt;

  bool get isUnread => readAt == null;

  IconData get icon => switch (type) {
        'low_stock' || 'out_of_stock' || 'negative_stock' => Symbols.inventory_2,
        'maintenance_due' || 'maintenance_overdue' => Symbols.build,
        'job_due_today' || 'job_due_tomorrow' || 'job_overdue' => Symbols.content_cut,
        'appointment_reminder' => Symbols.event,
        'timer_long_running' => Symbols.timer,
        'ai_insight' => Symbols.auto_awesome,
        _ => Symbols.notifications,
      };
}
