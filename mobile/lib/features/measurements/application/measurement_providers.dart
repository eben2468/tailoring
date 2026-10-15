import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/local/local_store.dart';
import '../../../core/network/api_exception.dart';
import '../../auth/application/session_controller.dart';
import '../../customers/domain/customer.dart';
import '../../sync/application/sync_providers.dart';
import '../data/measurements_api.dart';
import '../domain/measurement.dart';

final measurementsApiProvider = Provider<MeasurementsApi>((ref) => MeasurementsApi(ref.watch(syncEngineProvider)));

/// Active measurement groups and fields (configuration bundle).
final measurementFieldsProvider = Provider<AsyncValue<List<MeasurementGroup>>>((ref) => fromStore(ref, (p) => [
      for (final g in p.config.measurementGroups)
        if (g['is_active'] != false)
          MeasurementGroup.fromJson({
            ...g,
            'fields': (g['fields'] as List).cast<Map<String, dynamic>>().where((f) => f['is_active'] != false).toList(),
          }),
    ]));

final currentMeasurementsProvider = Provider.family<AsyncValue<CurrentMeasurements>, String>(
  (ref, customerId) => fromStore(ref, (p) => CurrentMeasurements.fromJson(p.currentMeasurements(customerId))),
);

/// Full history, newest first.
final measurementHistoryProvider = Provider.family<AsyncValue<List<MeasurementSet>>, String>(
  (ref, customerId) => fromStore(ref, (p) => p.measurementHistory(customerId).map(MeasurementSet.fromJson).toList()),
);

final measurementSetProvider = Provider.family<AsyncValue<MeasurementSet>, String>((ref, setId) => fromStore(ref, (p) {
      final row = p.store.get(Tables.measurementSets, setId);
      if (row == null || row['deleted_at'] != null) throw const NotFoundException('This measurement record was not found.');
      return MeasurementSet.fromJson(p.measurementSet(row));
    }));

/// The studio default unit from the signed-in session (settings: measurements.default_unit).
final defaultMeasurementUnitProvider = Provider<String?>((ref) => ref.watch(sessionControllerProvider).value?.business.defaultMeasurementUnit);

/// Unit to display for a customer: their preference, else the studio default.
MeasurementUnit displayUnitFor(Customer? customer, String? studioDefault) => MeasurementUnit.parse(customer?.preferredUnit ?? studioDefault);
