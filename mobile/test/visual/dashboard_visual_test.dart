@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nutofe/app/app.dart';
import 'package:nutofe/core/local/local_store.dart';
import 'package:nutofe/core/network/api_client.dart';
import 'package:nutofe/core/providers.dart';
import 'package:nutofe/features/sync/domain/local_ops.dart';

import '../support/fake_backend.dart';
import '../support/fakes.dart';

/// Screenshot of the dashboard (compare with design/stitch/tailor_owner_dashboard).
///   flutter test --tags golden --update-goldens
/// Dates, times and the running timer are relative to now, so re-render and review by eye.
Future<void> _loadFonts() async {
  final jakarta = FontLoader('PlusJakartaSans');
  for (final weight in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
    jakarta.addFont(rootBundle.load('assets/fonts/PlusJakartaSans-$weight.ttf'));
  }
  await jakarta.load();
  final noto = FontLoader('NotoSansFallback');
  for (final weight in [400, 500, 600, 700]) {
    noto.addFont(rootBundle.load('assets/fonts/NotoSans-latin-ext-$weight.ttf'));
  }
  await noto.load();
  await (FontLoader('packages/material_symbols_icons/MaterialSymbolsOutlined')
        ..addFont(rootBundle.load('packages/material_symbols_icons/lib/fonts/MaterialSymbolsOutlined.ttf')))
      .load();
}

void main() {
  setUpAll(_loadFonts);

  late FakeBackend backend;
  late MemoryTokenStore tokens;

  setUp(() {
    tokens = MemoryTokenStore()
      ..access = 'nat_1'
      ..refresh = 'nrt_1'
      ..session = {'user': userJson(name: 'Marcus Owusu'), 'business': businessJson};
    backend = FakeBackend();
    final kofi = backend.addCustomer('Kofi Mensah')['id'] as String;
    final kwame = backend.addCustomer('Kwame Asante')['id'] as String;
    final ama = backend.addCustomer('Ama Mensah')['id'] as String;
    final suit = backend.jobs.addJob(kofi, priority: 'high', dueInDays: 5, done: 1, actualSeconds: {1: 5400});
    backend.jobs.addJob(kwame, jobTypeId: 6, status: 'queued', dueInDays: 1);
    final blazer = backend.jobs.addJob(ama, jobTypeId: 2, done: 1, dueInDays: 3);
    final cutting = backend.server.all(Tables.tasks).firstWhere((t) => t['job_id'] == suit['id'] && t['task_type_id'] == 2)['id'] as String;
    backend.jobs.runTimer(cutting, elapsed: const Duration(hours: 1, minutes: 14, seconds: 28));
    final day = businessDayStart(backend.config, businessToday(backend.config, DateTime.now()));
    backend
      ..addAppointment('Final Fitting', day.add(const Duration(hours: 14, minutes: 30)).toLocal(), customerId: ama, jobId: blazer['id'] as String, location: 'Fitting Room 1')
      ..addAppointment('Collection', day.add(const Duration(hours: 16)).toLocal(), type: 'collection', customerId: kwame)
      ..addMaterial('White Silk Basting Thread', categoryId: 2, unit: 'spool', stock: 3, min: 10, reorder: 20)
      ..addTool('Juki Industrial Sewing #02', boughtDaysAgo: 57, interval: 60, location: 'Bench 02', brand: 'Juki DDL-9000C')
      ..addInsight(
        '#${suit['job_number']} may slip a day',
        severity: 'warning',
        body: '18 h of work left this week. At the current cutting pace, #${suit['job_number']} (3-Piece Suit) finishes a day after its due date unless cutting is done today.',
        action: {'type': 'open_job', 'job_id': suit['id'], 'label': 'Open job'},
      );
  });

  testWidgets('dashboard', (tester) async {
    tester.view.physicalSize = const Size(412 * 2, 2300 * 2);
    tester.view.devicePixelRatio = 2;
    tester.view.padding = const FakeViewPadding(top: 24 * 2, bottom: 16 * 2);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      retry: (_, _) => null,
      overrides: [
        tokenStoreProvider.overrideWithValue(tokens),
        apiClientProvider.overrideWith((ref) => ApiClient(baseUrl: 'http://api.test/api/v1', tokens: tokens, adapter: backend.adapter)),
      ],
      child: const NutofeApp(),
    ));
    for (var i = 0; i < 15; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/dashboard.png'));
  });
}
