import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nutofe/app/app.dart';
import 'package:nutofe/core/network/api_client.dart';
import 'package:nutofe/core/providers.dart';
import 'package:nutofe/features/measurements/domain/measurement.dart';

import '../../support/fake_backend.dart';
import '../../support/fakes.dart';

void main() {
  late FakeBackend backend;
  late MemoryTokenStore tokens;

  Future<void> pumpApp(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.625;
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

  setUp(() {
    backend = FakeBackend();
    tokens = MemoryTokenStore()
      ..access = 'nat_1'
      ..refresh = 'nrt_1'
      ..session = {'user': userJson(), 'business': businessJson};
  });

  test('unit conversion and formatting', () {
    expect(MeasurementUnit.inch.format(106.68), '42.0');
    expect(MeasurementUnit.inch.format(47.625), '18.75');
    expect(MeasurementUnit.cm.format(47.625), '47.6');
    expect(MeasurementUnit.inch.toCm(18.75), closeTo(47.625, 1e-9));
  });

  testWidgets('empty list invites adding the first customer', (tester) async {
    await pumpApp(tester);
    expect(find.text('No customers yet'), findsOneWidget);
    expect(find.text('Add customer'), findsOneWidget);
  });

  testWidgets('list shows customers with measurement status and searches by name', (tester) async {
    final kofi = backend.addCustomer('Kofi Mensah', phone: '+233241110001')['id'] as String;
    backend
      ..addCustomer('Ama Owusu', phone: '+233201110002')
      ..jobs.addJob(kofi);
    await pumpApp(tester);

    expect(find.text('Kofi Mensah'), findsOneWidget);
    expect(find.text('+233 24 111 0001'), findsOneWidget);
    expect(find.text('1 active job'), findsOneWidget);
    expect(find.text('Not measured'), findsNWidgets(2)); // summaries are calculated from the local copy
    expect(find.text('2 active customers'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, 'ama');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
    expect(find.text('Ama Owusu'), findsOneWidget);
    expect(find.text('Kofi Mensah'), findsNothing);
  });

  testWidgets('adding a customer with an existing phone warns and can open the existing record', (tester) async {
    backend.addCustomer('Kofi Mensah', phone: '+233241110001');
    await pumpApp(tester);

    await tester.tap(find.text('Customer'));
    await tester.pump(const Duration(milliseconds: 600)); // name field autofocuses: its cursor blink never settles
    await tester.enterText(find.byType(TextFormField).at(0), 'Kofi M.');
    await tester.enterText(find.byType(TextFormField).at(1), '+233241110001');
    await tester.tap(find.text('Add customer'));
    await tester.pumpAndSettle();

    expect(find.text('This number is already saved'), findsOneWidget);
    expect(find.text('Save anyway'), findsOneWidget);
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.text('Kofi Mensah'), findsWidgets);
    expect(find.text('Measurements'), findsOneWidget); // profile tabs
    expect(backend.customers, hasLength(1), reason: 'no duplicate was created');
  });

  testWidgets('profile dossier shows current measurements in the customer unit, with history', (tester) async {
    final kofi = backend.addCustomer('Kofi Mensah', phone: '+233241110001');
    backend
      ..addSet(kofi['id'] as String, {3: 104.14, 4: 85.09}, at: DateTime.utc(2026, 9, 1))
      ..addSet(kofi['id'] as String, {4: 86.995}, at: DateTime.utc(2026, 10, 1), texts: {20: 'Low right'}, notes: 'Erect posture');
    await pumpApp(tester);

    await tester.tap(find.text('Kofi Mensah'));
    await tester.pumpAndSettle();

    expect(find.text('Direct Call'), findsOneWidget);
    expect(find.text('WhatsApp'), findsOneWidget);
    expect(find.text('Imperial (in)'), findsOneWidget);
    expect(find.text('41.0'), findsOneWidget); // chest from the older set (104.14 cm)
    expect(find.text('34.25'), findsOneWidget); // waist from the newer partial set
    expect(find.text('Shoulder Slope: Low right'), findsOneWidget);
    expect(find.text('Erect posture'), findsOneWidget);

    await tester.tap(find.text('Imperial (in)'));
    await tester.pumpAndSettle();
    expect(find.text('104.1'), findsOneWidget); // switched to cm

    await tester.scrollUntilVisible(find.text('History'), 200);
    await tester.tap(find.text('History'));
    await tester.pumpAndSettle();
    expect(find.text('Kofi Mensah · 2 recordings'), findsOneWidget);
    expect(find.text('Latest'), findsOneWidget);
  });

  testWidgets('recording measurements sends only filled values, in the chosen unit', (tester) async {
    final kofi = backend.addCustomer('Kofi Mensah');
    await pumpApp(tester);
    await tester.tap(find.text('Kofi Mensah'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Record measurements'));
    await tester.pumpAndSettle();

    expect(find.text('Enter at least one measurement'), findsOneWidget);
    await tester.enterText(find.byType(TextField).at(0), '42');
    await tester.tap(find.text('Low right'));
    await tester.pumpAndSettle();
    expect(find.text('Save 2 measurements'), findsOneWidget);

    await tester.tap(find.text('Save 2 measurements'));
    await tester.pumpAndSettle();

    final saved = backend.sets.single;
    expect(saved['customer_id'], kofi['id']);
    expect(saved['entered_unit'], 'in');
    expect((saved['values'] as List).map((v) => (v as Map)['field_id']), containsAll([3, 20]));
    expect(find.text('Measurements'), findsOneWidget, reason: 'back on the profile');
  });

  testWidgets('out-of-range values are caught before sending', (tester) async {
    backend.addCustomer('Kofi Mensah');
    await pumpApp(tester);
    await tester.tap(find.text('Kofi Mensah'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Record measurements'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).at(0), '5');
    await tester.pump();
    await tester.tap(find.text('Save 1 measurement'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Between 23.62 and 78.74 in'), findsOneWidget);
    expect(backend.sets, isEmpty);
  });
}
