import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nutofe/app/app.dart';
import 'package:nutofe/core/network/api_client.dart';
import 'package:nutofe/core/providers.dart';

import '../../support/fakes.dart';

void main() {
  late MemoryTokenStore tokens;
  late FakeAdapter adapter;

  Future<void> pumpApp(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      retry: (_, _) => null,
      overrides: [
        tokenStoreProvider.overrideWithValue(tokens),
        apiClientProvider.overrideWith((ref) => ApiClient(baseUrl: 'http://api.test/api/v1', tokens: tokens, adapter: adapter)),
      ],
      child: const NutofeApp(),
    ));
    await tester.pumpAndSettle();
  }

  setUp(() {
    tokens = MemoryTokenStore();
    adapter = FakeAdapter((_) => FakeReply.ok(null));
  });

  testWidgets('signed-out users land on sign-in', (tester) async {
    await pumpApp(tester);
    expect(find.text('Welcome back'), findsOneWidget);
    expect(find.text('Sign In'), findsOneWidget);
  });

  testWidgets('validates before calling the server', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.text('Sign In'));
    await tester.pumpAndSettle();

    expect(find.text('Enter your email.'), findsOneWidget);
    expect(find.text('Enter your password.'), findsOneWidget);
    expect(adapter.requests, isEmpty);
  });

  testWidgets('shows the server message on wrong credentials', (tester) async {
    adapter.handler = (_) => FakeReply.error(401, 'INVALID_CREDENTIALS', 'Incorrect email or password.');
    await pumpApp(tester);

    await tester.enterText(find.byType(TextFormField).at(0), 'owner@nutofe.test');
    await tester.enterText(find.byType(TextFormField).at(1), 'wrong-password');
    await tester.tap(find.text('Sign In'));
    await tester.pumpAndSettle();

    expect(find.text('Incorrect email or password.'), findsOneWidget);
  });

  testWidgets('successful sign-in opens the app shell with the bottom navigation', (tester) async {
    adapter.handler = (_) => FakeReply.ok(loginJson());
    await pumpApp(tester);

    await tester.enterText(find.byType(TextFormField).at(0), 'owner@nutofe.test');
    await tester.enterText(find.byType(TextFormField).at(1), 'Correct-Horse-42');
    await tester.tap(find.text('Sign In'));
    await tester.pumpAndSettle();

    for (final label in ['Dashboard', 'Jobs', 'Calendar', 'Customers', 'More']) {
      expect(find.text(label), findsWidgets, reason: label);
    }
  });

  testWidgets('More shows administration only to admins', (tester) async {
    adapter.handler = (_) => FakeReply.ok(loginJson(role: 'admin'));
    tokens
      ..access = 'nat_1'
      ..refresh = 'nrt_1'
      ..session = {'user': userJson(role: 'admin'), 'business': businessJson};
    adapter.handler = (_) => FakeReply.ok({'user': userJson(role: 'admin'), 'business': businessJson});
    await pumpApp(tester);

    await tester.tap(find.text('More'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Audit log'), 200);

    expect(find.text('SYSTEM ADMINISTRATION'), findsOneWidget);
    expect(find.text('Users'), findsOneWidget);
  });
}
