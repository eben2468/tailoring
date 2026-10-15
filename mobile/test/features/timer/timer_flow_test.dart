import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nutofe/app/app.dart';
import 'package:nutofe/core/network/api_client.dart';
import 'package:nutofe/core/providers.dart';
import 'package:nutofe/features/timer/domain/timer.dart';
import 'package:nutofe/features/timer/presentation/timer_widgets.dart';

import '../../support/fake_backend.dart';
import '../../support/fakes.dart';

void main() {
  late FakeBackend backend;
  late MemoryTokenStore tokens;
  late String kofi;

  /// The live clock ticks every second, so pumpAndSettle would never settle: pump frames instead.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> pumpApp(WidgetTester tester) async {
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
    await settle(tester);
    await tester.tap(find.text('Jobs').last);
    await settle(tester);
  }

  setUp(() {
    backend = FakeBackend();
    kofi = backend.addCustomer('Kofi Mensah', phone: '+233241110001')['id'] as String;
    tokens = MemoryTokenStore()
      ..access = 'nat_1'
      ..refresh = 'nrt_1'
      ..session = {'user': userJson(), 'business': businessJson};
  });

  test('clock text and server clock offset', () {
    expect(clockText(const Duration(hours: 2, minutes: 35, seconds: 44)), '02:35:44');
    final started = DateTime.utc(2026, 10, 8, 9);
    // The server is 10 minutes ahead of the phone: elapsed time follows the server clock.
    final timer = ActiveTimer.fromJson({
        'id': 'a', 'task_id': 't', 'entry_type': 'timer', 'started_at': started.toIso8601String(), 'ended_at': null,
        'duration_seconds': 0, 'is_running': true, 'version': 1,
        'task': {'id': 't', 'name': 'Sewing', 'job_id': 'j', 'job_title': 'Suit', 'customer_name': 'Kofi'},
    }, const Duration(minutes: 10));
    expect(timer.elapsed(DateTime.utc(2026, 10, 8, 10)), const Duration(hours: 1, minutes: 10));
  });

  testWidgets('start the timer from a job card, pause, and the timer bar follows', (tester) async {
    backend.jobs.addJob(kofi, dueInDays: 3, done: 2);
    await pumpApp(tester);

    await tester.tap(find.text('Start Timer'));
    await settle(tester);
    expect(find.text('ACTIVE SESSION'), findsOneWidget);
    expect(find.text('STAGE 3 • SEWING'), findsOneWidget);
    expect(find.text('Pause Work'), findsOneWidget);
    expect(backend.jobs.running, isNotNull);

    // Back on the list: the running-timer bar and "Open Timer".
    await tester.pageBack();
    await settle(tester);
    expect(find.textContaining('Sewing & Assembly · #024 Kofi Mensah'), findsOneWidget);
    expect(find.text('Open Timer'), findsOneWidget);

    await tester.tap(find.text('Open Timer'));
    await settle(tester);
    await tester.enterText(find.byType(TextField), 'Sleeves set');
    await tester.tap(find.text('Pause Work'));
    await settle(tester);
    expect(backend.jobs.running, isNull);
    expect(backend.jobs.logs.map((l) => l['note']), contains('Sleeves set'));
    expect(find.text('Resume Work'), findsOneWidget);
    expect(find.text('PAUSED'), findsOneWidget);
  });

  testWidgets('a timer running when the app starts is restored; Log & Finish completes the stage', (tester) async {
    final job = backend.jobs.addJob(kofi, dueInDays: 3, done: 1);
    final cutting = ((job['tasks'] as List)[1] as Map)['id'] as String;
    backend.jobs.runTimer(cutting, elapsed: const Duration(hours: 1, minutes: 5));
    await pumpApp(tester);

    expect(find.textContaining('01:05:0'), findsOneWidget); // the bar, from the server's start time
    await tester.tap(find.textContaining('Fabric Cutting · #024'));
    await settle(tester);
    expect(find.text('ACTIVE SESSION'), findsOneWidget);

    await tester.tap(find.text('+15m Adjust'));
    await settle(tester);
    expect(find.text('15 minutes added to Fabric Cutting.'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5)); // let the snackbar go
    await settle(tester);

    await tester.tap(find.text('Log & Finish'));
    await settle(tester);
    final task = (backend.jobs.jobs.single['tasks'] as List)[1] as Map;
    expect(task['status'], 'completed');
    expect(backend.jobs.actualSeconds(task['id'] as String), inInclusiveRange(900 + 3900, 900 + 3900 + 5)); // +15 m adjustment + the 1 h 05 m session
    expect(find.text('ACTIVE SESSION'), findsNothing); // back on the list
    expect(find.text('Start Timer'), findsOneWidget);
  });

  testWidgets('starting another job while a timer runs offers to switch', (tester) async {
    final first = backend.jobs.addJob(kofi, dueInDays: 3, done: 1);
    final cutting = ((first['tasks'] as List)[1] as Map)['id'] as String;
    backend.jobs
      ..addJob(kofi, dueInDays: 5, done: 2)
      ..runTimer(cutting);
    await pumpApp(tester);
    // The second card's button sits under the bottom bar: scroll it into view.
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -500));
    await settle(tester);

    await tester.tap(find.text('Start Timer'));
    await settle(tester);
    expect(find.text('Switch the timer?'), findsOneWidget);
    await tester.tap(find.text('Switch to Sewing & Assembly'));
    await settle(tester);

    expect(find.text('ACTIVE SESSION'), findsOneWidget);
    expect(find.text('STAGE 3 • SEWING'), findsOneWidget);
    expect(backend.jobs.logs.where((l) => l['job_task_id'] == cutting), hasLength(1)); // the cutting session was closed
  });

  testWidgets('work log lists sessions and manual entries', (tester) async {
    final job = backend.jobs.addJob(kofi, dueInDays: 3, done: 1);
    final cutting = ((job['tasks'] as List)[1] as Map)['id'] as String;
    backend.jobs.runTimer(cutting, elapsed: const Duration(minutes: 30));
    await pumpApp(tester);
    await tester.tap(find.textContaining('Fabric Cutting · #024'));
    await settle(tester);
    await tester.tap(find.byTooltip('More'));
    await settle(tester);
    await tester.tap(find.text('Work log for this stage'));
    await settle(tester);

    expect(find.text('Work Log'), findsOneWidget);
    expect(find.text('Running'), findsOneWidget);
    expect(find.text('Add Work'), findsOneWidget);
  });
}
