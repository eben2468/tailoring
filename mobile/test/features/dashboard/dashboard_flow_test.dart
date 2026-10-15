import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nutofe/app/app.dart';
import 'package:nutofe/app/router.dart';
import 'package:nutofe/core/local/local_store.dart';
import 'package:nutofe/core/network/api_client.dart';
import 'package:nutofe/core/providers.dart';
import 'package:nutofe/features/sync/application/sync_providers.dart';
import 'package:nutofe/features/sync/domain/local_ops.dart';

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

  Finder scrollable() => find.byType(Scrollable).first;

  /// Scrolls [finder] into view and on, clear of the bottom navigation and timer bar.
  Future<void> reveal(WidgetTester tester, Finder finder) async {
    await tester.pump(); // build what the last scroll revealed, so the search starts from the right place
    await tester.scrollUntilVisible(finder, 300, scrollable: scrollable());
    await Scrollable.ensureVisible(tester.element(finder), alignment: 0.5);
    await settle(tester);
  }

  String stage(String jobId, int taskTypeId) =>
      backend.server.all(Tables.tasks).firstWhere((t) => t['job_id'] == jobId && t['task_type_id'] == taskTypeId)['id'] as String;

  /// A: high priority, cutting with the timer running · B: queued, due today · C: 2 days late, at its fitting.
  ({Map<String, dynamic> a, Map<String, dynamic> b, Map<String, dynamic> c}) seed() {
    final kofi = backend.addCustomer('Kofi Mensah')['id'] as String;
    final a = backend.jobs.addJob(kofi, priority: 'high', dueInDays: 5, done: 1);
    final b = backend.jobs.addJob(kofi, status: 'queued', dueInDays: 0);
    final c = backend.jobs.addJob(kofi, jobTypeId: 2, done: 1, dueInDays: -2);
    backend.jobs.runTimer(stage(a['id'] as String, 2));
    final today = businessToday(backend.config, DateTime.now());
    backend
      ..addAppointment('Baste fitting', businessDayStart(backend.config, today).add(const Duration(hours: 14)).toLocal(), customerId: kofi, jobId: c['id'] as String, location: 'Fitting Room 1')
      ..addMaterial('White silk thread', unit: 'spool', stock: 3, min: 10)
      ..addMaterial('Black thread', unit: 'spool', stock: 40, min: 5)
      ..addTool('Juki #02', boughtDaysAgo: 100, interval: 60)
      ..addInsight('#${c['job_number']} is likely to finish late', body: '2-Piece Suit: 6 h of work left.', action: {'type': 'open_job', 'job_id': c['id'], 'label': 'Open job'});
    return (a: a, b: b, c: c);
  }

  setUp(() {
    backend = FakeBackend();
    store = LocalStore.memory();
    tokens = MemoryTokenStore()
      ..access = 'nat_1'
      ..refresh = 'nrt_1'
      ..session = {'user': userJson(), 'business': businessJson};
  });

  testWidgets('the day on one screen: KPIs, workload, AI card, schedule, priority jobs and alerts', (tester) async {
    final jobs = seed();
    final container = await pumpApp(tester);

    expect(find.textContaining(', Marcus'), findsOneWidget);
    expect(find.textContaining('1 fitting scheduled'), findsOneWidget);
    expect(find.text('2'), findsWidgets, reason: 'two active jobs');
    expect(find.text('1 at fitting'), findsOneWidget);
    expect(find.text('1 FIT'), findsOneWidget);
    expect(find.text('Up to 2 days late'), findsOneWidget);
    expect(find.text('4.0h remaining'), findsOneWidget, reason: 'cutting 3 h (running) + fitting 1 h');
    expect(find.text('Cutting (3.0h)'), findsOneWidget);
    expect(find.text('Fitting (1.0h)'), findsOneWidget);
    expect(find.text('#${jobs.c['job_number']} is likely to finish late'), findsOneWidget);

    await reveal(tester, find.text('Fabric Cutting — Kofi Mensah'));
    expect(find.text('Pause Timer'), findsOneWidget);
    expect(find.text('Baste fitting — Kofi Mensah'), findsOneWidget);
    expect(find.text('FITTING ROOM 1'), findsOneWidget);
    expect(find.text('4 Tasks'), findsOneWidget, reason: 'timer, appointment, then C fitting and B measurement up next');
    await reveal(tester, find.text('Measurement & Pattern Drafting — Kofi Mensah'));
    expect(find.text('Baste Fitting — Kofi Mensah'), findsOneWidget);

    await reveal(tester, find.text('Priority Commission Jobs'));
    expect(find.text('View All 3'), findsOneWidget);
    await reveal(tester, find.text('2 Alerts'));
    await reveal(tester, find.text('Juki #02'));
    expect(find.text('White silk thread'), findsOneWidget);
    expect(find.text('3 spools left (Min: 10 spools)'), findsOneWidget);
    expect(find.text('Black thread'), findsNothing, reason: 'enough stock');
    expect(find.text('Maintenance overdue by 40 days'), findsOneWidget);

    await tester.tap(find.text('Restock'));
    await settle(tester);
    expect(find.byType(BottomSheet), findsOneWidget);
    Navigator.of(tester.element(find.byType(BottomSheet))).pop();
    await settle(tester);

    await tester.drag(scrollable(), const Offset(0, 4000)); // back to the top
    await settle(tester);
    await tester.tap(find.text('Open job'));
    await settle(tester);
    expect(container.read(routerProvider).state.uri.toString(), '/jobs/${jobs.c['id']}');
    expect(backend.insightRow(1)['insight_status'], 'seen');
  });

  testWidgets('pause the running timer, then start the next stage in the queue', (tester) async {
    final jobs = seed();
    final container = await pumpApp(tester);

    await reveal(tester, find.text('Pause Timer'));
    await tester.tap(find.text('Pause Timer'));
    await settle(tester);
    expect(backend.jobs.running, isNull);
    expect(find.text('Paused. Work logged.'), findsOneWidget);
    expect(find.text('Pause Timer'), findsNothing);

    // Up next in due order: C's fitting (2 days late), B's measurement (due today), A's cutting.
    await tester.tap(find.text('Start Next'));
    await settle(tester);
    expect(backend.jobs.running?['job_task_id'], stage(jobs.c['id'] as String, 4));
    expect(container.read(routerProvider).state.uri.toString(), '/jobs/${jobs.c['id']}/tasks/${stage(jobs.c['id'] as String, 4)}/timer');
  });

  testWidgets('an empty business: a calm dashboard with nothing invented', (tester) async {
    await pumpApp(tester);
    expect(find.text('All on schedule'), findsOneWidget);
    expect(find.text('No visits today'), findsOneWidget);
    expect(find.text('No stage is in progress or planned for today.'), findsOneWidget);
    expect(find.text('NUTƆFE AI INSIGHT'), findsNothing);
    await reveal(tester, find.text('Stock and tools are in good shape.'));
    expect(find.text('Nothing is planned for today and no job is waiting.'), findsOneWidget);
    expect(find.text('No jobs in production.'), findsOneWidget);
  });
}
