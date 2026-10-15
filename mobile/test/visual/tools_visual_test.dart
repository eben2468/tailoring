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

/// Screenshots of tools & equipment (compare with design/stitch/tools_equipment).
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

  Future<void> pumpTools(WidgetTester tester, {double height = 915}) async {
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
    await tester.tap(find.text('Tools & Equipment'));
    await tester.pumpAndSettle();
  }

  setUp(() {
    tokens = MemoryTokenStore()
      ..access = 'nat_1'
      ..refresh = 'nrt_1'
      ..session = {'user': userJson(name: 'Marcus Owusu'), 'business': businessJson};
    backend = FakeBackend();
    final juki1 = backend.addTool('Lockstitch Machine #01', boughtDaysAgo: 900, interval: 60, condition: 'excellent', location: 'Bench 01', brand: 'Juki DDL-9000C')['id'] as String;
    final juki2 = backend.addTool('Lockstitch Machine #02', boughtDaysAgo: 900, interval: 60, location: 'Bench 02', brand: 'Juki DDL-9000C')['id'] as String;
    final iron = backend.addTool('Steam Press Iron', categoryId: 2, boughtDaysAgo: 400, interval: 90, location: 'Station B', brand: 'Veit 4232')['id'] as String;
    final shears = backend.addTool('Tailor Shears 13"', categoryId: 3, boughtDaysAgo: 300, interval: 120, location: 'Cutting Table A', brand: 'Ernest Wright Turton')['id'] as String;
    backend
      ..logService(juki1, 14, description: 'Lubrication & needle-bar alignment')
      ..logService(juki1, 74, type: 'inspection')
      ..logService(juki2, 57, description: 'Oil flush')
      ..logService(iron, 76, type: 'cleaning', description: 'Descaling')
      ..logService(shears, 112, type: 'sharpening', description: 'Blade honing');
  });

  testWidgets('tools list', (tester) async {
    await pumpTools(tester, height: 1900);
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/tools_list.png'));
  });

  testWidgets('tool detail', (tester) async {
    await pumpTools(tester, height: 1300);
    await tester.tap(find.text('Lockstitch Machine #01'));
    await tester.pumpAndSettle();
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/tool_detail.png'));
  });

  testWidgets('record maintenance sheet', (tester) async {
    await pumpTools(tester, height: 1100);
    await tester.tap(find.text('Log Service'));
    await tester.pumpAndSettle();
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/tool_maintenance_sheet.png'));
  });

  testWidgets('register tool', (tester) async {
    await pumpTools(tester, height: 1500);
    await tester.ensureVisible(find.text('Register New Tool'));
    await tester.tap(find.text('Register New Tool'));
    await tester.pumpAndSettle();
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/tool_new.png'));
  });
}
