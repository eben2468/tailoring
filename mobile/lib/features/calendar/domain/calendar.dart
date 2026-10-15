import 'package:flutter/widgets.dart';
import 'package:material_symbols_icons/symbols.dart';

/// Appointment kinds (appointments.appointment_type).
enum AppointmentType {
  fitting('Fitting', Symbols.accessibility_new),
  consultation('Consultation', Symbols.forum),
  measurement('Measurement', Symbols.straighten),
  collection('Collection', Symbols.shopping_bag),
  delivery('Delivery', Symbols.local_shipping),
  other('Other', Symbols.event);

  const AppointmentType(this.label, this.icon);

  final String label;
  final IconData icon;

  static AppointmentType parse(String? value) => values.firstWhere((t) => t.name == value, orElse: () => other);
}

enum AppointmentStatus {
  scheduled('Scheduled'),
  confirmed('Confirmed'),
  completed('Completed'),
  cancelled('Cancelled'),
  noShow('No-show');

  const AppointmentStatus(this.label);

  final String label;

  String get api => this == noShow ? 'no_show' : name;

  bool get isOpen => this == scheduled || this == confirmed;

  static AppointmentStatus parse(String? value) => values.firstWhere((s) => s.api == value, orElse: () => scheduled);
}

class Appointment {
  const Appointment({
    required this.id,
    required this.type,
    required this.title,
    required this.startsAt,
    required this.endsAt,
    required this.status,
    required this.version,
    this.customerId,
    this.customerName,
    this.customerPhone,
    this.jobId,
    this.jobNumber,
    this.jobTitle,
    this.jobTaskId,
    this.location,
    this.reminderMinutesBefore,
    this.notes,
  });

  factory Appointment.fromJson(Map<String, dynamic> json) => Appointment(
        id: json['id'] as String,
        type: AppointmentType.parse(json['appointment_type'] as String?),
        title: json['title'] as String,
        customerId: json['customer_id'] as String?,
        customerName: json['customer_name'] as String?,
        customerPhone: json['customer_phone'] as String?,
        jobId: json['job_id'] as String?,
        jobNumber: json['job_number'] as String?,
        jobTitle: json['job_title'] as String?,
        jobTaskId: json['job_task_id'] as String?,
        startsAt: DateTime.parse(json['starts_at'] as String).toLocal(),
        endsAt: DateTime.parse(json['ends_at'] as String).toLocal(),
        location: json['location'] as String?,
        status: AppointmentStatus.parse(json['status'] as String?),
        reminderMinutesBefore: (json['reminder_minutes_before'] as num?)?.toInt(),
        notes: json['notes'] as String?,
        version: (json['version'] as num).toInt(),
      );

  final String id;
  final AppointmentType type;
  final String title;
  final String? customerId;
  final String? customerName;
  final String? customerPhone;
  final String? jobId;
  final String? jobNumber;
  final String? jobTitle;
  final String? jobTaskId;
  final DateTime startsAt;
  final DateTime endsAt;
  final String? location;
  final AppointmentStatus status;
  final int? reminderMinutesBefore;
  final String? notes;
  final int version;

  Duration get duration => endsAt.difference(startsAt);
}

/// What appears in the calendar.
enum CalendarKind { appointment, production, due, collection, maintenance }

/// One entry of the calendar: an appointment, a planned production block (a scheduled stage), or an
/// all-day date (job due / collection, tool service due). Built on the device from the local copy.
class CalendarItem {
  const CalendarItem({
    required this.kind,
    required this.title,
    required this.day,
    this.subtitle,
    this.start,
    this.end,
    this.status,
    this.appointment,
    this.jobId,
    this.taskId,
    this.customerName,
    this.jobNumber,
    this.toolId,
    this.isOverdue = false,
  });

  final CalendarKind kind;
  final String title;
  final String? subtitle;

  /// The calendar day (local date, time 00:00).
  final DateTime day;

  /// Null for all-day items.
  final DateTime? start;
  final DateTime? end;
  final String? status;
  final Appointment? appointment;
  final String? jobId;
  final String? taskId;
  final String? customerName;
  final String? jobNumber;

  /// The tool whose service is due (maintenance items).
  final String? toolId;
  final bool isOverdue;

  bool get allDay => start == null;

  Duration get duration => start == null || end == null ? Duration.zero : end!.difference(start!);
}

/// A week (Mon–Sun) at a glance: planned production against capacity, and collections due.
class WeekSummary {
  const WeekSummary({required this.plannedSeconds, required this.capacitySeconds, required this.collectionsDue, required this.fittings});

  final int plannedSeconds;
  final int capacitySeconds;
  final int collectionsDue;
  final int fittings;

  /// Planned production ÷ available bench hours (0 when there is no capacity set).
  double get load => capacitySeconds == 0 ? 0 : plannedSeconds / capacitySeconds;
}

/// Local calendar date (no time).
DateTime dayOf(DateTime t) => DateTime(t.year, t.month, t.day);

/// Monday of the week containing [day].
DateTime weekStart(DateTime day) => dayOf(day).subtract(Duration(days: day.weekday - 1));

/// ISO-8601 week number ("Week 42").
int isoWeek(DateTime day) {
  final thursday = dayOf(day).add(Duration(days: 4 - day.weekday));
  final dayOfYear = thursday.difference(DateTime(thursday.year)).inDays;
  return dayOfYear ~/ 7 + 1;
}
