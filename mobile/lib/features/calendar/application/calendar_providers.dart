import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/local/local_store.dart';
import '../../../core/network/api_exception.dart';
import '../../sync/application/sync_providers.dart';
import '../data/appointments_api.dart';
import '../domain/calendar.dart';
import '../domain/calendar_builder.dart';

final appointmentsApiProvider = Provider<AppointmentsApi>((ref) => AppointmentsApi(ref.watch(syncEngineProvider)));

/// Calendar items from [range.$1] (inclusive) to [range.$2] (exclusive), local dates.
final calendarItemsProvider = Provider.family<AsyncValue<List<CalendarItem>>, (DateTime, DateTime)>(
  (ref, range) => fromStore(ref, (p) => CalendarBuilder(p).items(range.$1, range.$2)),
);

/// Week at a glance; key = the Monday.
final weekSummaryProvider = Provider.family<AsyncValue<WeekSummary>, DateTime>((ref, monday) => fromStore(ref, (p) => CalendarBuilder(p).week(monday)));

final appointmentProvider = Provider.family<AsyncValue<Appointment>, String>((ref, id) => fromStore(ref, (p) {
      final row = p.store.get(Tables.appointments, id);
      if (row == null || row['deleted_at'] != null) throw const NotFoundException('This appointment was not found. It may have been removed on another device.');
      return Appointment.fromJson(p.appointment(row));
    }));

/// A job's appointments (fittings, collection), by start time.
final jobAppointmentsProvider = Provider.family<AsyncValue<List<Appointment>>, String>((ref, jobId) => fromStore(
      ref,
      (p) => (p.store.all(Tables.appointments).where((a) => a['job_id'] == jobId && a['deleted_at'] == null).map((a) => Appointment.fromJson(p.appointment(a))).toList()
        ..sort((a, b) => a.startsAt.compareTo(b.startsAt))),
    ));

/// The next open appointment that has not ended yet (timer screen "Next up in the salon").
final nextAppointmentProvider = Provider<Appointment?>((ref) {
  final p = ref.watch(presenterProvider).value;
  if (p == null) return null;
  final now = DateTime.now();
  final upcoming = p.store
      .all(Tables.appointments)
      .where((a) => a['deleted_at'] == null && (a['status'] == 'scheduled' || a['status'] == 'confirmed'))
      .map((a) => Appointment.fromJson(p.appointment(a)))
      .where((a) => a.endsAt.isAfter(now))
      .toList()
    ..sort((a, b) => a.startsAt.compareTo(b.startsAt));
  return upcoming.firstOrNull;
});
