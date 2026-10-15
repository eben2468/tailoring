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

/// Screenshots of inventory (compare with design/stitch/inventory_materials).
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
  late String wool;

  Future<void> pumpInventory(WidgetTester tester, {double height = 915}) async {
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
    await tester.tap(find.text('More').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Inventory'));
    await tester.pumpAndSettle();
  }

  setUp(() {
    tokens = MemoryTokenStore()
      ..access = 'nat_1'
      ..refresh = 'nrt_1'
      ..session = {'user': userJson(name: 'Marcus Owusu'), 'business': businessJson};
    backend = FakeBackend();
    final kofi = backend.addCustomer('Kofi Mensah')['id'] as String;
    final job = backend.jobs.addJob(kofi, dueInDays: 4, done: 1)['id'] as String;
    wool = backend.addMaterial('Super 150s Wool — Midnight Navy', stock: 25, min: 5, reorder: 25, cost: 145, location: 'Rack B-04', sku: 'FAB-0001')['id'] as String;
    backend
      ..apply('POST', '/inventory/items/$wool/transactions', {'id': backend.newId(), 'transaction_type': 'usage', 'quantity': 6.5, 'job_id': job, 'note': 'Cut jacket and trousers'})
      ..apply('POST', '/inventory/items/$wool/transactions', {'id': backend.newId(), 'transaction_type': 'purchase', 'quantity': 10, 'unit_cost': 140, 'reference': 'INV-2231'});
    backend
      ..addMaterial('Silk Basting Thread No. 40 — White', categoryId: 2, unit: 'spool', stock: 3, min: 10, reorder: 10, location: 'Spool Box 01', sku: 'THR-0001')
      ..addMaterial('Bemberg Cupro Lining — Burgundy', categoryId: 5, stock: 14, min: 4, reorder: 20, cost: 38, location: 'Rack C-02', sku: 'LIN-0001')
      ..addMaterial('Horn Buttons — Dark Brown 24L/32L', categoryId: 3, unit: 'set', stock: 6, min: 2, reorder: 5, cost: 28, location: 'Drawer A-12', sku: 'BTN-0001')
      ..addMaterial('Horsehair Canvas — Medium', min: 5, reorder: 25, location: 'Roll Bin 03', sku: 'CAN-0001');
  });

  testWidgets('inventory list', (tester) async {
    await pumpInventory(tester, height: 2300);
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/inventory_list.png'));
  });

  testWidgets('material detail', (tester) async {
    await pumpInventory(tester, height: 1700);
    await tester.tap(find.text('Super 150s Wool — Midnight Navy').first);
    await tester.pumpAndSettle();
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/inventory_item.png'));
  });

  testWidgets('use material sheet', (tester) async {
    await pumpInventory(tester);
    await tester.tap(find.text('Use for Job').first);
    await tester.pumpAndSettle();
    await tester.enterText(find.descendant(of: find.byType(BottomSheet), matching: find.byType(TextField)).first, '3.5');
    await tester.pumpAndSettle();
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/inventory_use_sheet.png'));
  });

  testWidgets('new material', (tester) async {
    await pumpInventory(tester, height: 1700);
    await tester.tap(find.text('Material'));
    await tester.pumpAndSettle();
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/inventory_new.png'));
  });
}
