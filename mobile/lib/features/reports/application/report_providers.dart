import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../../sync/application/sync_providers.dart';
import '../data/reports_api.dart';
import '../domain/reports.dart';

final reportsApiProvider = Provider<ReportsApi>((ref) => ReportsApi(ref.watch(apiClientProvider), ref.watch(localStoreProvider)));

/// The range picked on the reports screens (shared by all reports while the app runs).
final reportPresetProvider = NotifierProvider<ReportPresetController, ReportPreset>(ReportPresetController.new);

class ReportPresetController extends Notifier<ReportPreset> {
  @override
  ReportPreset build() => ReportPreset.last30;

  void select(ReportPreset preset) => state = preset;
}

final reportProvider = FutureProvider.autoDispose.family<ReportResult, (ReportKind, ReportRange)>(
  (ref, args) => ref.watch(reportsApiProvider).fetch(args.$1, args.$2),
);
