import '../../../core/local/local_store.dart';
import '../../sync/domain/presenter.dart';
import 'calendar.dart';

/// The calendar, assembled on the device from the local copy (ARCHITECTURE §10): appointments,
/// planned production blocks (stages with scheduled_start/end), all-day job dates (due, collection) and
/// tool service due dates.
/// Nothing is duplicated: each item points back at its source row.
class CalendarBuilder {
  CalendarBuilder(this.p);

  final Presenter p;

  static const _openJobs = ['draft', 'queued', 'in_progress', 'on_hold', 'ready_for_collection'];

  Map<String, dynamic>? _job(String? id) => id == null ? null : p.store.get(Tables.jobs, id);

  String? _customerName(String? customerId) => customerId == null ? null : p.store.get(Tables.customers, customerId)?['full_name'] as String?;

  /// Items whose day falls in [from, to) (local dates), sorted: all-day first, then by start time.
  List<CalendarItem> items(DateTime from, DateTime to, {bool includeClosed = false}) {
    final out = <CalendarItem>[];
    bool inRange(DateTime day) => !day.isBefore(from) && day.isBefore(to);

    for (final a in p.store.all(Tables.appointments)) {
      if (a['deleted_at'] != null) continue;
      final appointment = Appointment.fromJson(p.appointment(a));
      if (!includeClosed && (appointment.status == AppointmentStatus.cancelled)) continue;
      final day = dayOf(appointment.startsAt);
      if (!inRange(day)) continue;
      out.add(CalendarItem(
        kind: CalendarKind.appointment,
        title: appointment.title,
        subtitle: [appointment.customerName, if (appointment.jobNumber != null) 'Job #${appointment.jobNumber}'].whereType<String>().join(' • '),
        day: day,
        start: appointment.startsAt,
        end: appointment.endsAt,
        status: appointment.status.label,
        appointment: appointment,
        jobId: appointment.jobId,
        customerName: appointment.customerName,
        jobNumber: appointment.jobNumber,
      ));
    }

    for (final t in p.store.all(Tables.tasks)) {
      if (t['deleted_at'] != null || t['scheduled_start'] == null) continue;
      final job = _job(t['job_id'] as String);
      if (job == null || job['deleted_at'] != null || !_openJobs.contains(job['status'])) continue;
      final start = DateTime.parse(t['scheduled_start'] as String).toLocal();
      final end = t['scheduled_end'] == null ? start.add(const Duration(hours: 1)) : DateTime.parse(t['scheduled_end'] as String).toLocal();
      final day = dayOf(start);
      if (!inRange(day)) continue;
      final customer = _customerName(job['customer_id'] as String?);
      out.add(CalendarItem(
        kind: CalendarKind.production,
        title: t['task_name'] as String,
        subtitle: [customer, if (job['job_number'] != null) 'Job #${job['job_number']}'].whereType<String>().join(' • '),
        day: day,
        start: start,
        end: end,
        status: switch (t['status']) {
          'in_progress' => 'In Progress',
          'completed' => 'Done',
          'skipped' => 'Skipped',
          _ => job['status'] == 'queued' ? 'Queued' : 'Scheduled',
        },
        jobId: job['id'] as String,
        taskId: t['id'] as String,
        customerName: customer,
        jobNumber: job['job_number'] as String?,
      ));
    }

    final todayKey = DateTime.now();
    for (final j in p.store.all(Tables.jobs)) {
      if (j['deleted_at'] != null || !_openJobs.contains(j['status'])) continue;
      final customer = _customerName(j['customer_id'] as String?);
      final number = j['job_number'] as String?;
      void addDate(String key, CalendarKind kind, String label) {
        final value = j[key] as String?;
        if (value == null) return;
        final day = DateTime.parse(value);
        if (!inRange(day)) return;
        out.add(CalendarItem(
          kind: kind,
          title: '$label: ${j['title']}',
          subtitle: [customer, if (number != null) 'Job #$number'].whereType<String>().join(' • '),
          day: day,
          jobId: j['id'] as String,
          customerName: customer,
          jobNumber: number,
          isOverdue: kind == CalendarKind.due && day.isBefore(dayOf(todayKey)) && j['status'] != 'ready_for_collection',
        ));
      }

      if (j['status'] != 'ready_for_collection') addDate('due_date', CalendarKind.due, 'Due');
      addDate('collection_date', CalendarKind.collection, 'Collection');
    }

    // Tool service due dates (active, not retired tools with a schedule).
    for (final t in p.store.all(Tables.tools)) {
      if (t['deleted_at'] != null || t['archived_at'] != null) continue;
      final tool = p.tool(t);
      final next = tool['next_maintenance_date'] as String?;
      if (next == null || tool['maintenance_state'] == 'none') continue;
      final day = DateTime.parse(next);
      if (!inRange(day)) continue;
      out.add(CalendarItem(
        kind: CalendarKind.maintenance,
        title: 'Service due: ${tool['tool_name']}',
        subtitle: [tool['category_name'], tool['storage_location']].whereType<String>().join(' • '),
        day: day,
        toolId: t['id'] as String,
        isOverdue: tool['maintenance_state'] == 'overdue',
      ));
    }

    out.sort((a, b) {
      final d = a.day.compareTo(b.day);
      if (d != 0) return d;
      if (a.allDay != b.allDay) return a.allDay ? -1 : 1;
      return (a.start ?? a.day).compareTo(b.start ?? b.day);
    });
    return out;
  }

  /// Production planned this week against bench capacity (settings: schedule.capacity_hours_per_day ×
  /// open days in schedule.working_hours), collections due and fittings booked.
  WeekSummary week(DateTime monday) {
    final end = monday.add(const Duration(days: 7));
    final items = this.items(monday, end);
    final hours = (p.config.settings['schedule.capacity_hours_per_day'] as num?)?.toDouble() ?? 8;
    final working = p.config.settings['schedule.working_hours'];
    const keys = ['mon', 'tue', 'wed', 'thu', 'fri', 'sat', 'sun'];
    final openDays = working is Map ? keys.where((k) => working[k] != null).length : 6;
    return WeekSummary(
      plannedSeconds: items.where((i) => i.kind == CalendarKind.production).fold(0, (s, i) => s + i.duration.inSeconds),
      capacitySeconds: (hours * 3600 * openDays).round(),
      collectionsDue: items.where((i) => i.kind == CalendarKind.collection || i.appointment?.type == AppointmentType.collection).length,
      fittings: items.where((i) => i.appointment?.type == AppointmentType.fitting && i.appointment!.status.isOpen).length,
    );
  }
}
