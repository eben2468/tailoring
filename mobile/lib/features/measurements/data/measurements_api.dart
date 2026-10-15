import 'package:uuid/uuid.dart';

import '../../../core/local/local_store.dart';
import '../../../core/network/api_exception.dart';
import '../../sync/data/sync_engine.dart';
import '../domain/measurement.dart';

/// Recording and discarding measurement sets (works offline). Reads come from the local copy.
class MeasurementsApi {
  const MeasurementsApi(this._sync);

  final SyncEngine _sync;

  /// Records a new set. The id is generated here so a retry never saves twice; the time is the
  /// moment it was measured (also when it reaches the server later).
  Future<MeasurementSet> record(
    String customerId, {
    required MeasurementUnit unit,
    required List<MeasurementEntry> entries,
    String? notes,
    String? supersedesSetId,
  }) async {
    final id = const Uuid().v7();
    final name = _sync.store.get(Tables.customers, customerId)?['full_name'] ?? 'customer';
    final body = {
      'id': id,
      'entered_unit': unit.code,
      'notes': (notes == null || notes.trim().isEmpty) ? null : notes.trim(),
      'supersedes_set_id': supersedesSetId,
      'values': entries.map((e) => e.toJson()).toList(),
    };
    await _sync.perform(
      label: 'Measurements for $name',
      method: 'POST',
      path: '/customers/$customerId/measurements',
      body: body,
      // Queued offline: keep the moment it was measured (online the server's clock is used).
      queuedBody: {...body, 'measured_at': DateTime.now().toUtc().toIso8601String()},
    );
    final row = _sync.store.get(Tables.measurementSets, id);
    final presenter = _sync.presenter();
    if (row == null || presenter == null) throw const NotFoundException('The measurements were saved but are not on this phone yet. Pull to refresh.');
    return MeasurementSet.fromJson(presenter.measurementSet(row));
  }

  Future<void> discard(String setId) => _sync.perform(label: 'Remove a measurement record', method: 'DELETE', path: '/measurement-sets/$setId');
}
