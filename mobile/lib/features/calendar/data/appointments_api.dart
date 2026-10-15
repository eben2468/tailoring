import 'package:uuid/uuid.dart';

import '../../../core/local/local_store.dart';
import '../../../core/network/api_exception.dart';
import '../../sync/data/sync_engine.dart';
import '../domain/calendar.dart';

/// Appointment fields from the booking form.
class AppointmentDraft {
  const AppointmentDraft({
    required this.type,
    required this.title,
    required this.startsAt,
    required this.endsAt,
    this.customerId,
    this.jobId,
    this.jobTaskId,
    this.location,
    this.reminderMinutesBefore,
    this.notes,
  });

  final AppointmentType type;
  final String title;
  final DateTime startsAt;
  final DateTime endsAt;
  final String? customerId;
  final String? jobId;
  final String? jobTaskId;
  final String? location;
  final int? reminderMinutesBefore;
  final String? notes;

  Map<String, dynamic> toJson() => {
        'appointment_type': type.name,
        'title': title.trim(),
        'customer_id': customerId,
        'job_id': jobId,
        'job_task_id': jobTaskId,
        'starts_at': startsAt.toUtc().toIso8601String(),
        'ends_at': endsAt.toUtc().toIso8601String(),
        'location': location == null || location!.trim().isEmpty ? null : location!.trim(),
        'reminder_minutes_before': reminderMinutesBefore,
        'notes': notes == null || notes!.trim().isEmpty ? null : notes!.trim(),
      };
}

/// Appointment writes (docs/API_REFERENCE.md §11). Work offline; reads come from the local copy.
class AppointmentsApi {
  const AppointmentsApi(this._sync);

  final SyncEngine _sync;

  Appointment _read(String id) {
    final presenter = _sync.presenter();
    final row = _sync.store.get(Tables.appointments, id);
    if (presenter == null || row == null || row['deleted_at'] != null) throw const NotFoundException('This appointment was not found.');
    return Appointment.fromJson(presenter.appointment(row));
  }

  /// [allowOverlap] confirms booking over another appointment (409 SCHEDULE_CONFLICT otherwise).
  Future<Appointment> create(AppointmentDraft draft, {bool allowOverlap = false}) async {
    final id = const Uuid().v7();
    await _sync.perform(
      label: 'Book ${draft.title}',
      method: 'POST',
      path: '/appointments',
      body: {'id': id, ...draft.toJson(), if (allowOverlap) 'allow_overlap': true},
    );
    return _read(id);
  }

  Future<Appointment> update(Appointment existing, AppointmentDraft draft, {bool allowOverlap = false}) async {
    await _sync.perform(
      label: 'Change ${draft.title}',
      method: 'PATCH',
      path: '/appointments/${existing.id}',
      body: {'version': existing.version, ...draft.toJson(), if (allowOverlap) 'allow_overlap': true},
    );
    return _read(existing.id);
  }

  Future<Appointment> setStatus(Appointment a, AppointmentStatus status) async {
    await _sync.perform(label: '${a.title}: ${status.label.toLowerCase()}', method: 'POST', path: '/appointments/${a.id}/status', body: {'status': status.api});
    return _read(a.id);
  }

  Future<void> delete(Appointment a) => _sync.perform(label: 'Delete ${a.title}', method: 'DELETE', path: '/appointments/${a.id}');
}
