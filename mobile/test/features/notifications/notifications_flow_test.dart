import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nutofe/app/app.dart';
import 'package:nutofe/core/local/local_store.dart';
import 'package:nutofe/core/network/api_client.dart';
import 'package:nutofe/core/providers.dart';
import 'package:nutofe/features/sync/application/sync_providers.dart';

import '../../support/fake_backend.dart';
import '../../support/fakes.dart';

void main() {
  late FakeBackend backend;
  late MemoryTokenStore tokens;
  late LocalStore store;

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<ProviderContainer> pumpApp(WidgetTester tester) async {
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
    return ProviderScope.containerOf(tester.element(find.byType(NutofeApp)));
  }

  Future<void> openBell(WidgetTester tester) async {
    await tester.tap(find.byTooltip('Notifications').first);
    await settle(tester);
  }

  setUp(() {
    backend = FakeBackend();
    store = LocalStore.memory();
    tokens = MemoryTokenStore()
      ..access = 'nat_1'
      ..refresh = 'nrt_1'
      ..session = {'user': userJson(), 'business': businessJson};
  });

  testWidgets('notifications arrive with the sync; opening one marks it read and goes to its page', (tester) async {
    final wool = backend.addMaterial('Super 150s Wool', stock: 3, min: 5)['id'] as String;
    backend
      ..addNotification('Low stock: Super 150s Wool', body: '3 m left (minimum 5 m).', route: '/inventory/$wool')
      ..addNotification('Overdue: #024 3-Piece Suit', type: 'job_overdue', severity: 'critical', body: 'Kofi Mensah · due 2 days ago.', minutesAgo: 60 * 30)
      ..addNotification('Service due: Juki #02', type: 'maintenance_due', minutesAgo: 60 * 50, read: true);
    await pumpApp(tester);

    await tester.tap(find.text('More').last);
    await settle(tester);
    expect(find.text('2 unread'), findsOneWidget);

    await openBell(tester);
    expect(find.text('Notifications'), findsWidgets);
    expect(find.text('TODAY'), findsOneWidget);
    expect(find.text('EARLIER'), findsOneWidget);
    expect(find.text('3 m left (minimum 5 m).'), findsOneWidget);

    await tester.tap(find.text('Low stock: Super 150s Wool'));
    await settle(tester);
    expect(find.text('Super 150s Wool'), findsWidgets, reason: 'opens the material page');
    expect(backend.notificationRow(1)['read_at'], isNotNull);

    await tester.pageBack();
    await settle(tester);
    expect(find.text('1 unread'), findsOneWidget);
    await tester.tap(find.text('Mark all read'));
    await settle(tester);
    expect(backend.notificationRow(2)['read_at'], isNotNull);
    expect(find.text('Everything read'), findsOneWidget);
  });

  testWidgets('read without signal: saved on the phone and sent when back online', (tester) async {
    backend.addNotification('Due today: #027 Linen Kaftan Set', type: 'job_due_today');
    final container = await pumpApp(tester);
    await openBell(tester);

    backend.adapter.offline = true;
    await tester.tap(find.text('Mark all read'));
    await settle(tester);
    expect(find.text('Everything read'), findsOneWidget);
    expect(store.outbox.single.op, 'notification.read_all');
    expect(backend.notificationRow(1)['read_at'], isNull);

    backend.adapter.offline = false;
    unawaited(container.read(syncControllerProvider.notifier).syncNow());
    await settle(tester);
    expect(store.outbox, isEmpty);
    expect(backend.notificationRow(1)['read_at'], isNotNull);
  });

  testWidgets('nothing to show', (tester) async {
    await pumpApp(tester);
    await openBell(tester);
    expect(find.text('All quiet'), findsOneWidget);
  });
}
