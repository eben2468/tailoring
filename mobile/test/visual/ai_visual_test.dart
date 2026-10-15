@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nutofe/app/app.dart';
import 'package:nutofe/core/network/api_client.dart';
import 'package:nutofe/core/providers.dart';
import 'package:nutofe/app/router.dart';

import '../support/fake_backend.dart';
import '../support/fakes.dart';

/// Screenshot of the AI assistant (compare with design/stitch/sartor_ai_business_assistant).
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

  testWidgets('ai assistant', (tester) async {
    final backend = FakeBackend();
    final job = backend.jobs.addJob(backend.addCustomer('Kofi Mensah')['id'] as String, dueInDays: 2);
    backend
      ..addInsight('#${job['job_number']} is likely to finish late', severity: 'critical',
          body: '3-Piece Suit: 12 h of work left with 9.5 h of work ahead of it. At the current bench capacity it finishes Thu 15 Oct, 1 day after its due date (Wed 14 Oct).',
          action: {'type': 'open_job', 'job_id': job['id'], 'label': 'Open job'})
      ..addInsight('Silk Basting Thread runs out in about 6 days', type: 'inventory_forecast', body: 'Using about 3.5 spools a week; 3 spools left. Usual restock: 10 spools.', action: {'type': 'restock', 'item_id': 'x', 'quantity': 10, 'label': 'Restock'});
    final tokens = MemoryTokenStore()
      ..access = 'nat_1'
      ..refresh = 'nrt_1'
      ..session = {'user': userJson(name: 'Marcus Owusu'), 'business': businessJson};
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
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(tester.element(find.byType(NutofeApp)));
    // ignore: unawaited_futures
    container.read(routerProvider).push('/ai');
    await tester.pumpAndSettle();
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/ai_assistant.png'));
  });
}
