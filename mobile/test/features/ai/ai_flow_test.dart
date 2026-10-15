import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nutofe/app/app.dart';
import 'package:nutofe/app/router.dart';
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

  Future<ProviderContainer> pumpApp(WidgetTester tester, {String? route = '/ai'}) async {
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
    final container = ProviderScope.containerOf(tester.element(find.byType(NutofeApp)));
    if (route != null) {
      unawaited(container.read(routerProvider).push(route));
      await settle(tester);
    }
    return container;
  }

  setUp(() {
    backend = FakeBackend();
    store = LocalStore.memory();
    tokens = MemoryTokenStore()
      ..access = 'nat_1'
      ..refresh = 'nrt_1'
      ..session = {'user': userJson(), 'business': businessJson};
  });

  testWidgets('directives, precision and capacity; acting on a card opens the job, dismissing it hides it', (tester) async {
    final job = backend.jobs.addJob(backend.addCustomer('Kofi Mensah')['id'] as String, dueInDays: 2);
    backend
      ..addInsight('#${job['job_number']} is likely to finish late', severity: 'critical', body: '3-Piece Suit: 12 h of work left.', action: {'type': 'open_job', 'job_id': job['id'], 'label': 'Open job'})
      ..addInsight('Room for about 8 h more this week', type: 'workload', severity: 'info', status: 'seen')
      ..addInsight('Old card', status: 'dismissed');
    await pumpApp(tester);

    expect(find.text('Nutɔfe AI Assistant'), findsOneWidget);
    expect(find.text('Learning from 4 completed jobs, your logged hours and stock use.'), findsOneWidget);
    expect(find.text('Engine: figures only'), findsOneWidget);
    expect(find.text('1 fresh'), findsOneWidget);
    expect(find.text('Old card'), findsNothing, reason: 'dismissed cards stay hidden');
    expect(find.text('High Impact'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('92.3%'), 300, scrollable: find.byType(Scrollable).first);
    expect(find.text('Sewing runs 12.5% longer than estimated over 12 stages.'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('84%'), 300, scrollable: find.byType(Scrollable).first);
    expect(find.text('Optimal Load'), findsOneWidget);

    await tester.drag(find.byType(Scrollable).first, const Offset(0, 3000)); // back to the top
    await settle(tester);
    await tester.tap(find.text('Dismiss').last);
    await settle(tester);
    expect(backend.insightRow(2)['insight_status'], 'dismissed');
    expect(find.text('Room for about 8 h more this week'), findsNothing);

    await tester.tap(find.text('Open job'));
    await settle(tester);
    expect(find.text('3-Piece Suit'), findsWidgets, reason: 'the job sheet opened');
    expect(backend.insightRow(1)['insight_status'], 'seen');
  });

  testWidgets('quick queries are answered in the chat', (tester) async {
    backend.aiAnswers['What should I work on today?'] = 'Work in this order:\n• #024 3-Piece Suit: 12 h left';
    await pumpApp(tester);

    await tester.scrollUntilVisible(find.text('What should I work on today?'), 300, scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('What should I work on today?'));
    await settle(tester);
    await tester.scrollUntilVisible(find.text('from your figures'), 300, scrollable: find.byType(Scrollable).first);
    expect(find.text('Work in this order:\n• #024 3-Piece Suit: 12 h left'), findsOneWidget);
    expect(find.text('from your figures'), findsOneWidget);

    await tester.enterText(find.byType(TextField).last, 'Tell me a joke');
    await tester.tap(find.text('Ask'));
    await settle(tester);
    await tester.scrollUntilVisible(find.text("I don't have data for that."), 300, scrollable: find.byType(Scrollable).first);
    expect(find.text("I don't have data for that."), findsOneWidget);
  });

  testWidgets('without the AI service the cards from the sync still show', (tester) async {
    backend
      ..aiOverview = null
      ..addInsight('Silk thread runs out in about 3 days', type: 'inventory_forecast', severity: 'critical');
    await pumpApp(tester);
    expect(find.text('Silk thread runs out in about 3 days'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('The AI assistant cannot be reached right now. Everything else keeps working.'), 300, scrollable: find.byType(Scrollable).first);
    expect(find.text('The AI assistant cannot be reached right now. Everything else keeps working.'), findsOneWidget);
  });

  testWidgets('new job: suggest hours from finished jobs; the job sheet shows the forecast', (tester) async {
    backend.aiEstimates[2] = 3 * 3600 + 1800; // cutting learned from history: 3.5 h
    final kofi = backend.addCustomer('Kofi Mensah')['id'] as String;
    await pumpApp(tester, route: '/jobs/new?customer=$kofi');

    await tester.tap(find.text('Suggest hours'));
    await settle(tester);
    expect(find.textContaining('Hours for 1 stage set from your finished'), findsOneWidget);
    expect(find.widgetWithText(TextField, '3.5'), findsOneWidget);

    final job = backend.jobs.addJob(kofi, dueInDays: 1);
    backend.aiForecast = {'job_number': job['job_number'], 'position': 2, 'finish_date': '2026-10-15', 'due_date': '2026-10-14', 'risk': 'high', 'reasons': ['10 h of work left', 'Expected to finish Thu 15 Oct', 'Due Wed 14 Oct']};
    final container = ProviderScope.containerOf(tester.element(find.byType(NutofeApp)));
    unawaited(container.read(syncControllerProvider.notifier).syncNow());
    await settle(tester);
    unawaited(container.read(routerProvider).push('/jobs/${job['id']}'));
    await settle(tester);
    await tester.scrollUntilVisible(find.text('AI Production Analysis'), 300, scrollable: find.byType(Scrollable).first);
    expect(find.text('High delay risk'), findsOneWidget);
    expect(find.text('Thu 15 Oct'), findsOneWidget);
    expect(find.text('• Due Wed 14 Oct'), findsOneWidget);
  });
}
