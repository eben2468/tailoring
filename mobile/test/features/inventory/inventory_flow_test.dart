import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nutofe/app/app.dart';
import 'package:nutofe/app/router.dart';
import 'package:nutofe/core/local/local_store.dart';
import 'package:nutofe/core/network/api_client.dart';
import 'package:nutofe/core/network/api_exception.dart';
import 'package:nutofe/core/providers.dart';
import 'package:nutofe/features/inventory/domain/inventory.dart';
import 'package:nutofe/features/sync/application/sync_providers.dart';
import 'package:nutofe/features/sync/domain/config_bundle.dart';
import 'package:nutofe/features/sync/domain/presenter.dart';

import '../../support/fake_backend.dart';
import '../../support/fakes.dart';

void main() {
  late FakeBackend backend;
  late MemoryTokenStore tokens;
  late LocalStore store;
  late String kofi;

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<ProviderContainer> pumpInventory(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      retry: (_, _) => null,
      overrides: [
        tokenStoreProvider.overrideWithValue(tokens),
        apiClientProvider.overrideWith((ref) => ApiClient(baseUrl: 'http://api.test/api/v1', tokens: tokens, adapter: backend.adapter)),
        localStoreProvider.overrideWithValue(store),
      ],
      child: const NutofeApp(),
    ));
    await settle(tester);
    await tester.tap(find.text('More').last);
    await settle(tester);
    await tester.tap(find.text('Inventory'));
    await settle(tester);
    return ProviderScope.containerOf(tester.element(find.byType(NutofeApp)));
  }

  Finder sheetField([int index = 0]) => find.descendant(of: find.byType(BottomSheet), matching: find.byType(TextField)).at(index);

  setUp(() {
    backend = FakeBackend();
    store = LocalStore.memory();
    kofi = backend.addCustomer('Kofi Mensah', phone: '+233241110001')['id'] as String;
    tokens = MemoryTokenStore()
      ..access = 'nat_1'
      ..refresh = 'nrt_1'
      ..session = {'user': userJson(), 'business': businessJson};
  });

  group('stock rules (same as the server)', () {
    test('quantities and units read like the API messages', () {
      expect(StockRules.number(39.5), '39.5');
      expect(StockRules.number(12.0), '12');
      expect(StockRules.number(-1.5), '-1.5');
      expect(StockRules.number(100.250), '100.25');
      expect(StockRules.quantity(3, 'spool'), '3 spools');
      expect(StockRules.quantity(1, 'spool'), '1 spool');
      expect(StockRules.quantity(2, 'box'), '2 boxes');
      expect(StockRules.quantity(18.5, 'm'), '18.5 m');
      expect(StockUnits.format(18.5, 'm'), '18.5m');
      expect(StockRules.status(-1, 5), 'negative');
      expect(StockRules.status(0, 0), 'out');
      expect(StockRules.status(5, 5), 'low');
      expect(StockRules.status(5.001, 5), 'ok');
    });

    test('the ledger drives stock, status, alerts and value; voided lines do not count', () {
      final wool = backend.addMaterial('Super 150s Wool', stock: 18.5, min: 5, reorder: 25, cost: 145)['id'] as String;
      final thread = backend.addMaterial('Silk Basting Thread', categoryId: 2, unit: 'spool', stock: 3, min: 10)['id'] as String;
      backend.addMaterial('Horsehair Canvas', min: 5);
      final job = backend.jobs.addJob(kofi)['id'] as String;

      backend.apply('POST', '/inventory/items/$wool/transactions', {'id': backend.newId(), 'transaction_type': 'usage', 'quantity': 3.5, 'job_id': job});
      final mistake = backend.newId();
      backend.apply('POST', '/inventory/items/$wool/transactions', {'id': mistake, 'transaction_type': 'write_off', 'quantity': 10});
      backend.apply('POST', '/inventory/transactions/$mistake/void', {'reason': 'Wrong material'});
      expect(backend.stockOf(wool), 15);

      final p = Presenter(backend.server, backend.config);
      final item = InventoryItem.fromJson(p.inventoryItem(backend.server.get(Tables.inventoryItems, wool)!));
      expect([item.quantityOnHand, item.status, item.jobsUsedThisMonth, item.categoryName], [15, StockStatus.ok, 1, 'Fabric']);
      final summary = InventorySummary.fromJson(p.inventorySummary());
      expect([summary.totalItems, summary.categoryCount, summary.lowStock, summary.outOfStock, summary.negative], [3, 2, 1, 1, 0]);
      expect(summary.alerts.map((i) => i.name), ['Horsehair Canvas', 'Silk Basting Thread']);
      expect(summary.stockValue, 2175); // 15 m × GHS 145
      expect(p.inventoryLedger(wool).first['is_voided'], isTrue);
      expect(p.jobMaterials(job).single['quantity_change'], -3.5);
      expect(thread, isNotEmpty);
    });

    test('online the stock cannot go negative; a change replayed from offline is accepted', () {
      final thread = backend.addMaterial('Silk Basting Thread', categoryId: 2, unit: 'spool', stock: 3, min: 10)['id'] as String;
      void record(Map<String, dynamic> body) => backend.apply('POST', '/inventory/items/$thread/transactions', {'id': backend.newId(), ...body});

      expect(
        () => record({'transaction_type': 'usage', 'quantity': 5}),
        throwsA(isA<ValidationException>()
            .having((e) => e.code, 'code', 'INSUFFICIENT_STOCK')
            .having((e) => e.forField('quantity'), 'field', 'Only 3 spools in stock. If the shelf holds more, record a stock count first.')),
      );
      expect(() => record({'transaction_type': 'usage', 'quantity': 1.5}), throwsA(isA<ValidationException>().having((e) => e.forField('quantity'), 'field', 'Use a whole number of spools.')));
      expect(() => record({'transaction_type': 'purchase', 'quantity': 2, 'job_id': backend.newId()}), throwsA(isA<ValidationException>().having((e) => e.forField('job_id'), 'job', isNotNull)));

      record({'transaction_type': 'usage', 'quantity': 5, 'offline': true});
      expect(backend.stockOf(thread), -2);
      record({'transaction_type': 'adjustment', 'counted_quantity': 12});
      expect(backend.stockOf(thread), 12);
      expect(backend.transactionsOf(thread).last['quantity_change'], 14);
      expect(() => record({'transaction_type': 'adjustment', 'counted_quantity': 12}), throwsA(isA<ValidationException>().having((e) => e.forField('counted_quantity'), 'count', 'The stock already shows 12 spools.')));

      backend.apply('POST', '/inventory/items/$thread/archive', {});
      expect(() => record({'transaction_type': 'purchase', 'quantity': 1}), throwsA(isA<ConflictException>().having((e) => e.code, 'code', 'ITEM_ARCHIVED')));
      expect(
        () => backend
          ..addMaterial('Duplicate', sku: 'THR-1')
          ..addMaterial('Duplicate 2', sku: 'THR-1'),
        throwsA(isA<ValidationException>().having((e) => e.forField('sku'), 'sku', 'Another material already uses this code.')),
      );
    });
  });

  testWidgets('inventory screen: tiles, replenishment alerts, categories and material cards', (tester) async {
    backend
      ..addMaterial('Super 150s Wool — Navy', stock: 18.5, min: 5, reorder: 25, cost: 145, location: 'Rack B-04', sku: 'FAB-0001')
      ..addMaterial('Silk Basting Thread No. 40', categoryId: 2, unit: 'spool', stock: 3, min: 10, reorder: 10)
      ..addMaterial('Horsehair Canvas', min: 5);
    await pumpInventory(tester);

    expect(find.text('Inventory & Materials'), findsOneWidget);
    expect(find.text('MATERIALS'), findsOneWidget);
    expect(find.text('Across 2 categories'), findsOneWidget);
    expect(find.text('Supply Replenishment'), findsOneWidget);
    expect(find.text('2 materials at or below the minimum'), findsOneWidget);
    expect(find.textContaining('3 spools left', findRichText: true), findsOneWidget);
    expect(find.text('Horsehair Canvas'), findsWidgets);
    expect(find.text('Fabric 2'), findsOneWidget);
    expect(find.text('Thread 1'), findsOneWidget);
    expect(find.text('Linings 0'), findsNothing, reason: 'only categories that hold materials get a chip');

    await tester.tap(find.text('Thread 1'));
    await settle(tester);
    expect(find.text('Super 150s Wool — Navy'), findsNothing);
    expect(find.text('Restock (10 spools)'), findsOneWidget);
  });

  testWidgets('use material for a job from its card; too much is refused inline', (tester) async {
    final wool = backend.addMaterial('Super 150s Wool — Navy', stock: 18.5, min: 5, reorder: 25)['id'] as String;
    final job = backend.jobs.addJob(kofi, dueInDays: 5);
    await pumpInventory(tester);

    await tester.tap(find.text('Use for Job'));
    await settle(tester);
    expect(find.text('Use material'), findsWidgets);
    await tester.enterText(sheetField(), '30');
    await tester.tap(find.text('Save'));
    await settle(tester);
    expect(find.text('Only 18.5 m in stock. If the shelf holds more, record a stock count first.'), findsOneWidget);
    expect(backend.stockOf(wool), 18.5);

    await tester.enterText(sheetField(), '3.5');
    await tester.tap(find.text('Not for a particular job'));
    await settle(tester);
    await tester.tap(find.text('#${job['job_number']} · Kofi Mensah'));
    await settle(tester);
    await tester.tap(find.text('Save'));
    await settle(tester);

    expect(backend.stockOf(wool), 15);
    expect(backend.transactionsOf(wool).last['job_id'], job['id']);
    expect(find.text('Used: Super 150s Wool — Navy.'), findsOneWidget);
    expect(find.text('15m'), findsOneWidget);
    expect(find.text('Used in 1 job this month'), findsOneWidget);
  });

  testWidgets('restock from the replenishment card pre-fills the usual order', (tester) async {
    final thread = backend.addMaterial('Silk Basting Thread No. 40', categoryId: 2, unit: 'spool', stock: 3, min: 10, reorder: 10)['id'] as String;
    await pumpInventory(tester);

    await tester.tap(find.text('Restock').first);
    await settle(tester);
    expect(find.text('Receive stock'), findsWidgets);
    expect(tester.widget<TextField>(sheetField()).controller!.text, '10');
    await tester.tap(find.text('Save'));
    await settle(tester);

    expect(backend.stockOf(thread), 13);
    expect(find.text('Supply Replenishment'), findsNothing, reason: 'back above its minimum');
    expect(find.text('In Stock'), findsOneWidget);
  });

  testWidgets('usage recorded without signal is kept even past the stock and replayed as offline', (tester) async {
    final thread = backend.addMaterial('Silk Basting Thread No. 40', categoryId: 2, unit: 'spool', stock: 3, min: 10)['id'] as String;
    final container = await pumpInventory(tester);

    backend.adapter.offline = true;
    await tester.tap(find.text('Silk Basting Thread No. 40').last);
    await settle(tester);
    await tester.tap(find.text('Use for Job'));
    await settle(tester);
    await tester.enterText(sheetField(), '5');
    await tester.tap(find.text('Save'));
    await settle(tester);

    expect(find.text('Recount'), findsOneWidget, reason: 'the local copy shows the negative balance');
    expect(find.text('-2 spools'), findsOneWidget);
    expect(store.outbox.single.body['offline'], isTrue);
    expect(backend.stockOf(thread), 3);

    backend.adapter.offline = false;
    unawaited(container.read(syncControllerProvider.notifier).syncNow());
    await settle(tester);
    expect(store.outbox, isEmpty);
    expect(backend.stockOf(thread), -2, reason: 'the server accepts usage that really happened');

    // A stock count puts it right.
    await tester.tap(find.text('Count'));
    await settle(tester);
    await tester.enterText(sheetField(), '12');
    await tester.tap(find.text('Save count'));
    await settle(tester);
    expect(backend.stockOf(thread), 12);
    expect(find.text('Low Stock'), findsNothing);
  });

  testWidgets('add a material with its opening stock, then void a mistaken entry', (tester) async {
    await pumpInventory(tester);
    await tester.tap(find.text('Material'));
    await settle(tester);

    expect(find.text('New material'), findsOneWidget);
    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), 'Bemberg Cupro Lining — Burgundy');
    await tester.ensureVisible(find.text('Linings'));
    await settle(tester);
    await tester.tap(find.text('Linings'));
    await tester.enterText(fields.at(1), 'LIN-0001');
    await tester.enterText(fields.at(2), 'Rack C-02');
    await tester.enterText(fields.at(4), '14');
    await tester.enterText(fields.at(5), '4');
    await tester.enterText(fields.at(6), '20');
    await tester.tap(find.text('Add material').last);
    await settle(tester);

    final item = backend.server.all(Tables.inventoryItems).single;
    expect([item['item_name'], item['category_id'], item['unit'], item['sku'], item['min_stock_level'], item['reorder_quantity']], ['Bemberg Cupro Lining — Burgundy', 5, 'm', 'LIN-0001', 4.0, 20.0]);
    expect(backend.stockOf(item['id'] as String), 14);
    expect(find.text('14m'), findsOneWidget, reason: 'opens the new material');
    expect(find.text('Opening balance'), findsWidgets);

    await tester.tap(find.text('Write off'));
    await settle(tester);
    await tester.enterText(sheetField(), '2');
    await tester.tap(find.text('Save'));
    await settle(tester);
    expect(backend.stockOf(item['id'] as String), 12);

    await tester.ensureVisible(find.text('Written off'));
    await tester.tap(find.text('Written off'));
    await settle(tester);
    await tester.enterText(find.descendant(of: find.byType(BottomSheet), matching: find.byType(TextField)), 'Typed in the wrong material');
    await tester.tap(find.text('Void entry'));
    await settle(tester);
    expect(backend.stockOf(item['id'] as String), 14);
    expect(find.text('Voided: Typed in the wrong material'), findsOneWidget);
  });

  testWidgets('the job sheet lists the materials used for the job', (tester) async {
    final wool = backend.addMaterial('Super 150s Wool — Navy', stock: 18.5)['id'] as String;
    final job = backend.jobs.addJob(kofi, dueInDays: 5);
    backend
      ..apply('POST', '/inventory/items/$wool/transactions', {'id': backend.newId(), 'transaction_type': 'usage', 'quantity': 3.5, 'job_id': job['id']})
      ..apply('POST', '/inventory/items/$wool/transactions', {'id': backend.newId(), 'transaction_type': 'return', 'quantity': 0.5, 'job_id': job['id']});
    final container = await pumpInventory(tester);
    unawaited(container.read(routerProvider).push('/jobs/${job['id']}'));
    await settle(tester);

    await tester.scrollUntilVisible(find.text('Materials Used'), 300, scrollable: find.byType(Scrollable).first);
    expect(find.text('Super 150s Wool — Navy'), findsOneWidget);
    expect(find.text('3m'), findsOneWidget, reason: '3.5 m used − 0.5 m returned');
  });
}
