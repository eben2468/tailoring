import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nutofe/app/app.dart';
import 'package:nutofe/app/router.dart';
import 'package:nutofe/core/local/local_store.dart';
import 'package:nutofe/core/network/api_client.dart';
import 'package:nutofe/core/providers.dart';
import 'package:nutofe/features/notifications/application/push_controller.dart';
import 'package:nutofe/features/notifications/data/push_messaging.dart';
import 'package:nutofe/features/sync/application/sync_providers.dart';

import '../../support/fake_backend.dart';
import '../../support/fakes.dart';

/// Stands in for Firebase Cloud Messaging.
class FakePush implements PushMessaging {
  String? currentToken = 'fcm-token-1';
  int permissionRequests = 0;
  PushMessage? launchedFrom;
  final refreshes = StreamController<String>.broadcast();
  final messages = StreamController<PushMessage>.broadcast();
  final taps = StreamController<PushMessage>.broadcast();

  @override
  Future<bool> requestPermission() async {
    permissionRequests++;
    return true;
  }

  @override
  Future<String?> token() async => currentToken;

  @override
  Stream<String> get tokenRefreshes => refreshes.stream;

  @override
  Stream<PushMessage> get foreground => messages.stream;

  @override
  Stream<PushMessage> get opened => taps.stream;

  @override
  Future<PushMessage?> initial() async => launchedFrom;
}

void main() {
  late FakeBackend backend;
  late MemoryTokenStore tokens;
  late FakePush push;

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
        localStoreProvider.overrideWithValue(LocalStore.memory()),
        pushMessagingProvider.overrideWithValue(push),
      ],
      child: const NutofeApp(),
    ));
    await settle(tester);
    return ProviderScope.containerOf(tester.element(find.byType(NutofeApp)));
  }

  setUp(() {
    backend = FakeBackend();
    push = FakePush();
    tokens = MemoryTokenStore()
      ..access = 'nat_1'
      ..refresh = 'nrt_1'
      ..session = {'user': userJson(), 'business': businessJson};
  });

  testWidgets('signed in: asks once for permission and registers the token, again when it changes', (tester) async {
    await pumpApp(tester);
    expect(push.permissionRequests, 1);
    expect(backend.pushToken, 'fcm-token-1');

    push.refreshes.add('fcm-token-2');
    await settle(tester);
    expect(backend.pushToken, 'fcm-token-2');
  });

  testWidgets('a message while the app is open syncs, so the bell shows it', (tester) async {
    await pumpApp(tester);
    backend.addNotification('Low stock: Wool');
    final pulls = backend.requests.where((r) => r.endsWith('/sync/pull')).length;

    push.messages.add(const PushMessage(route: '/inventory/x'));
    await settle(tester);
    expect(backend.requests.where((r) => r.endsWith('/sync/pull')).length, greaterThan(pulls));
  });

  testWidgets('tapping a notification opens its screen; without a route, the notification centre', (tester) async {
    final kofi = backend.addCustomer('Kofi Mensah')['id'] as String;
    final job = backend.jobs.addJob(kofi, dueInDays: 1);
    final container = await pumpApp(tester);
    String location() => container.read(routerProvider).state.uri.toString();

    push.taps.add(PushMessage(route: '/jobs/${job['id']}'));
    await settle(tester);
    expect(location(), '/jobs/${job['id']}');

    push.taps.add(const PushMessage());
    await settle(tester);
    expect(location(), '/notifications');
  });

  testWidgets('started from a notification: opens its screen', (tester) async {
    push.launchedFrom = const PushMessage(route: '/ai');
    final container = await pumpApp(tester);
    expect(container.read(routerProvider).state.uri.toString(), '/ai');
  });

  testWidgets('signed out: no token is sent', (tester) async {
    tokens
      ..access = null
      ..refresh = null
      ..session = null;
    await pumpApp(tester);
    expect(backend.pushToken, isNull);
    expect(push.permissionRequests, 0);
    expect(find.text('Sign In'), findsOneWidget);
  });

  test('push is off without Firebase (the default)', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    expect(container.read(pushMessagingProvider), isNull);
    expect(() => container.read(pushControllerProvider), returnsNormally);
  });
}
