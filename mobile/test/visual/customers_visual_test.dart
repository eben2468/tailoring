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

/// Screenshots of the customer & measurement screens (compare with design/stitch/customer_profile_measurement_dossier).
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

  Future<void> pumpApp(WidgetTester tester) async {
    tester.view.physicalSize = const Size(412 * 2, 915 * 2);
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
    await tester.tap(find.text('Customers').last);
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
    final kofi = backend.addCustomer('Kofi Mensah', phone: '+233241110001', address: 'East Legon, Accra');
    final kwame = backend.addCustomer('Kwame Asante', phone: '+233271110003')['id'] as String;
    backend
      ..addCustomer('Ama Owusu', phone: '+233201110002')
      ..addCustomer('Yaa Kɔkɔ Boateng', phone: '+233551110004')
      ..addSet(kofi['id'] as String, {3: 106.68, 4: 87.63}, at: DateTime.utc(2026, 9, 1))
      ..addSet(kofi['id'] as String, {4: 86.995}, at: DateTime.utc(2026, 10, 4), texts: {20: 'Low right'}, notes: 'Erect posture, right shoulder ~0.5in low; athletic taper to the waist.');
    backend
      ..addSet(kwame, {3: 101.6}, at: DateTime.utc(2026, 8, 20))
      ..jobs.addJob(kofi['id'] as String, dueInDays: 6, done: 2)
      ..jobs.addJob(kwame, status: 'completed', done: 4);
  });

  testWidgets('customers list', (tester) async {
    await pumpApp(tester);
    await shoot(tester, 'customers_list');
  });

  testWidgets('customer profile', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.text('Kofi Mensah'));
    await shoot(tester, 'customer_profile');
  });

  testWidgets('record measurements', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.text('Kofi Mensah'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit Measures'));
    await shoot(tester, 'record_measurements');
  });

  testWidgets('measurement history', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.text('Kofi Mensah'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('History'));
    await shoot(tester, 'measurement_history');
  });

  testWidgets('new customer form', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.text('Customer'));
    await tester.pump(const Duration(milliseconds: 600));
    FocusManager.instance.primaryFocus?.unfocus();
    await shoot(tester, 'customer_form');
  });
}
