@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nutofe/app/app.dart';
import 'package:nutofe/core/network/api_client.dart';
import 'package:nutofe/core/providers.dart';

import '../support/fake_backend.dart';
import '../support/fakes.dart';

/// Screenshots of the jobs screens. Compare with design/stitch/production_jobs_management,
/// job_024_details_production_stages and create_new_bespoke_job.
///   flutter test --tags golden --update-goldens
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

  /// [height] in logical pixels: long screens are captured whole.
  Future<void> pumpApp(WidgetTester tester, {double height = 915}) async {
    tester.view.physicalSize = Size(412 * 2, height * 2);
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
    await tester.pumpAndSettle();
    await tester.tap(find.text('Jobs').last);
    await tester.pumpAndSettle();
  }

  Future<void> shoot(WidgetTester tester, String name) async {
    await tester.pumpAndSettle();
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/$name.png'));
  }

  setUp(() {
    tokens = MemoryTokenStore()
      ..access = 'nat_1'
      ..refresh = 'nrt_1'
      ..session = {'user': userJson(name: 'Marcus Owusu'), 'business': businessJson};
    backend = FakeBackend();
    final kofi = backend.addCustomer('Kofi Mensah', phone: '+233241110001', sets: 2)['id'] as String;
    final kwame = backend.addCustomer('Kwame Asante', phone: '+233241110002')['id'] as String;
    final yaw = backend.addCustomer('Yaw Boateng', phone: '+233241110003')['id'] as String;
    backend
      ..customers.first['style_preferences'] = 'Dark matte horn buttons, contrast burgundy cupro lining, hand-embroidered monogram "K.M."'
      ..addSet(kofi, {3: 106.68, 4: 86.36}, at: DateTime.utc(2026, 10, 4));
    backend.jobs
      ..addJob(kofi, priority: 'high', dueInDays: 2, done: 2, actualSeconds: {2: 3 * 3600 + 1800}, checklist: ['Assemble canvas chest piece', 'Set sleeves & shoulder pads', 'Waistcoat pocket welts'])
      ..addJob(kwame, jobTypeId: 6, dueInDays: 1, done: 1)
      ..addJob(yaw, dueInDays: 4, done: 3, actualSeconds: {3: 5400})
      ..addJob(kofi, jobTypeId: 6, status: 'queued', dueInDays: 12);
  });

  testWidgets('jobs list', (tester) async {
    await pumpApp(tester);
    await shoot(tester, 'jobs_list');
  });

  testWidgets('job sheet', (tester) async {
    await pumpApp(tester, height: 2300);
    await tester.tap(find.text('View Sheet').first);
    await shoot(tester, 'job_sheet');
  });

  testWidgets('new job', (tester) async {
    await pumpApp(tester, height: 1900);
    await tester.tap(find.text('Add Job'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Choose customer'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Kofi Mensah').last);
    await shoot(tester, 'job_new');
  });

  testWidgets('stage sheet', (tester) async {
    await pumpApp(tester, height: 2300);
    await tester.tap(find.text('View Sheet').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('3. Sewing & Assembly'));
    await shoot(tester, 'job_stage_sheet');
  });
}
