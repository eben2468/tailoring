import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../../auth/application/session_controller.dart';
import '../../customers/domain/customer.dart';
import '../data/measurements_api.dart';
import '../domain/measurement.dart';

final measurementsApiProvider = Provider<MeasurementsApi>((ref) => MeasurementsApi(ref.watch(apiClientProvider)));

/// Field configuration (kept for the session; it rarely changes).
final measurementFieldsProvider = FutureProvider<List<MeasurementGroup>>((ref) => ref.watch(measurementsApiProvider).fields());

final currentMeasurementsProvider =
    FutureProvider.autoDispose.family<CurrentMeasurements, String>((ref, customerId) => ref.watch(measurementsApiProvider).current(customerId));

/// Full history (newest first). One page of 50 sets covers years of fittings.
final measurementHistoryProvider =
    FutureProvider.autoDispose.family<List<MeasurementSet>, String>((ref, customerId) async => (await ref.watch(measurementsApiProvider).history(customerId)).items);

final measurementSetProvider = FutureProvider.autoDispose.family<MeasurementSet, String>((ref, setId) => ref.watch(measurementsApiProvider).set(setId));

/// The studio default unit from the signed-in session (settings: measurements.default_unit).
final defaultMeasurementUnitProvider = Provider<String?>((ref) => ref.watch(sessionControllerProvider).value?.business.defaultMeasurementUnit);

/// Unit to display for a customer: their preference, else the studio default.
MeasurementUnit displayUnitFor(Customer? customer, String? studioDefault) => MeasurementUnit.parse(customer?.preferredUnit ?? studioDefault);
