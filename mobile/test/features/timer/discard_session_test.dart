import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nutofe/app/app.dart';
import 'package:nutofe/core/network/api_client.dart';
import 'package:nutofe/core/providers.dart';

import '../../support/fake_backend.dart';
import '../../support/fakes.dart';

void main() {
  // Regression: the reason sheet disposed its text controller while still closing (crashed on a phone).
  testWidgets('a running session can be discarded offline with a reason', (tester) async {
    final backend = FakeBackend();
    final tokens = MemoryTokenStore()
      ..access = 'nat_1'
      ..refresh = 'nrt_1'
      ..session = {'user': userJson(), 'business': businessJson};
    final kofi = backend.addCustomer('Kofi Mensah')['id'] as String;
    final job = backend.jobs.addJob(kofi, dueInDays: 3, done: 1);
    backend.jobs.runTimer(((job['tasks'] as List)[1] as Map)['id'] as String);
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
    Future<void> settle() async {
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }
    await settle();
    await tester.tap(find.textContaining('Fabric Cutting ·'));
    await settle();
    backend.adapter.offline = true;
    await tester.tap(find.byTooltip('More'));
    await settle();
    await tester.tap(find.text('Discard this session'));
    await settle();
    await tester.enterText(find.byType(TextField).last, 'Test session');
    await tester.tap(find.text('Discard session'));
    await settle();
    expect(find.text('Session discarded. It does not count towards the hours.'), findsOneWidget);
  });
}
