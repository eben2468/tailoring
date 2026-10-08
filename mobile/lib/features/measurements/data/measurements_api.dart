import 'package:uuid/uuid.dart';

import '../../../core/network/api_client.dart';
import '../domain/measurement.dart';

/// Measurement configuration, history and recording.
class MeasurementsApi {
  const MeasurementsApi(this._client);

  final ApiClient _client;

  Future<List<MeasurementGroup>> fields() async =>
      (await _client.get('/measurement-fields') as List<dynamic>).cast<Map<String, dynamic>>().map(MeasurementGroup.fromJson).toList();

  Future<CurrentMeasurements> current(String customerId) async =>
      CurrentMeasurements.fromJson(await _client.get('/customers/$customerId/measurements/current') as Map<String, dynamic>);

  Future<Paged<MeasurementSet>> history(String customerId, {int page = 1}) =>
      _client.getPaged('/customers/$customerId/measurements', MeasurementSet.fromJson, query: {'page': page, 'per_page': 50});

  Future<MeasurementSet> set(String setId) async => MeasurementSet.fromJson(await _client.get('/measurement-sets/$setId') as Map<String, dynamic>);

  /// Records a new set. The id is generated here so a retry never saves twice.
  Future<MeasurementSet> record(
    String customerId, {
    required MeasurementUnit unit,
    required List<MeasurementEntry> entries,
    String? notes,
    String? supersedesSetId,
  }) async =>
      MeasurementSet.fromJson(await _client.post('/customers/$customerId/measurements', body: {
        'id': const Uuid().v7(),
        'entered_unit': unit.code,
        'notes': (notes == null || notes.trim().isEmpty) ? null : notes.trim(),
        'supersedes_set_id': supersedesSetId,
        'values': entries.map((e) => e.toJson()).toList(),
      }) as Map<String, dynamic>);

  Future<void> discard(String setId) => _client.delete('/measurement-sets/$setId');
}
