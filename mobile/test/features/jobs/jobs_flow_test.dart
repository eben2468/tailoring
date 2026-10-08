import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nutofe/app/app.dart';
import 'package:nutofe/core/network/api_client.dart';
import 'package:nutofe/core/providers.dart';
import 'package:nutofe/core/utils/formatters.dart';
import 'package:nutofe/core/widgets/filter_pills.dart';
import 'package:nutofe/features/jobs/domain/job.dart';

import '../../support/fake_backend.dart';
import '../../support/fakes.dart';

void main() {
  late FakeBackend backend;
  late MemoryTokenStore tokens;
  late String kofi;

  Future<void> pumpApp(WidgetTester tester, {String tab = 'Jobs'}) async {
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
    await tester.pumpAndSettle();
    await tester.tap(find.text(tab).last);
    await tester.pumpAndSettle();
  }

  Future<void> scrollTo(WidgetTester tester, Finder finder) async {
    await tester.scrollUntilVisible(finder, 300, scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    // scrollUntilVisible aligns the target to the top edge, under the frosted header: pull it back down.
    await tester.drag(find.byType(Scrollable).first, const Offset(0, 250));
    await tester.pumpAndSettle();
  }

  setUp(() {
    backend = FakeBackend();
    kofi = backend.addCustomer('Kofi Mensah', phone: '+233241110001', sets: 1)['id'] as String;
    backend.addCustomer('Ama Owusu', phone: '+233201110002');
    tokens = MemoryTokenStore()
      ..access = 'nat_1'
      ..refresh = 'nrt_1'
      ..session = {'user': userJson(), 'business': businessJson};
  });

  test('hours parsing and due labels', () {
    expect(Fmt.parseHours('2.5'), 9000);
    expect(Fmt.parseHours('2,5'), 9000);
    expect(Fmt.parseHours(''), isNull);
    expect(Fmt.parseHours('-1'), isNull);
    expect(Fmt.hours(37800), '10.5');
    expect(Fmt.dueIn(0), 'today');
    expect(Fmt.dueIn(1), 'tomorrow');
    expect(Fmt.dueIn(-3), '3 days late');
    expect(JobStatus.parse('ready_for_collection'), JobStatus.readyForCollection);
    expect(JobStatus.readyForCollection.api, 'ready_for_collection');
  });

  testWidgets('jobs list shows cards with stage, hours and chip counts; filters change the list', (tester) async {
    backend.jobs
      ..addJob(kofi, priority: 'high', dueInDays: 2, done: 2)
      ..addJob(kofi, jobTypeId: 6, status: 'queued', dueInDays: 20);
    await pumpApp(tester);

    expect(find.text('Production Jobs'), findsOneWidget);
    expect(find.text('All (2)'), findsOneWidget);
    expect(find.text('Active (1)'), findsOneWidget);
    expect(find.text('Pending (1)'), findsOneWidget);
    expect(find.text('High Priority'), findsOneWidget);
    expect(find.text('Sewing Stage'), findsOneWidget);
    expect(find.text('Progress: Sewing & Assembly'), findsOneWidget);
    expect(find.text('ESTIMATED'), findsNWidgets(2));
    expect(find.text('13.5h'), findsOneWidget); // 2.5 + 3 + 6 + 2
    expect(find.text('5.5h'), findsOneWidget); // completed stages

    await tester.dragUntilVisible(find.text('Overdue (0)'), find.byType(FilterPills), const Offset(-200, 0));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Overdue (0)'));
    await tester.pumpAndSettle();
    expect(find.text('Nothing overdue'), findsOneWidget);
  });

  testWidgets('job sheet: mark the stage complete, tick a subtask, then ready and collected', (tester) async {
    final job = backend.jobs.addJob(kofi, dueInDays: 2, done: 3, checklist: ['Draft buttonholes', 'Hand-sew lapels']);
    await pumpApp(tester);
    await tester.tap(find.text('View Sheet'));
    await tester.pumpAndSettle();

    expect(find.text('Kofi Mensah'), findsWidgets);
    expect(find.text('PRODUCTION STATUS'), findsOneWidget);
    expect(find.text('Finishing & Buttonholes'), findsWidgets);

    expect(find.text('Start Work Timer (Finishing)'), findsOneWidget);
    await scrollTo(tester, find.text('Hand-sew lapels'));
    expect(find.text('Active Subtasks'), findsOneWidget);
    await tester.tap(find.text('Hand-sew lapels'));
    await tester.pumpAndSettle();
    expect(backend.requests.where((r) => r.startsWith('PATCH') && r.contains('/checklist-items/')), hasLength(1));

    await tester.tap(find.text('Mark Stage Complete'));
    await tester.pumpAndSettle();
    expect(find.text('Finishing & Buttonholes completed.'), findsOneWidget);
    // All work done: the next step is ready for collection, then collected.
    await tester.tap(find.text('Ready for Collection').last);
    await tester.pumpAndSettle();
    expect((backend.jobs.jobs.first)['status'], 'ready_for_collection');
    expect(find.text('Mark Collected'), findsOneWidget);

    await tester.tap(find.text('Mark Collected'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mark collected'));
    await tester.pumpAndSettle();
    expect(job['status'], 'completed');
    expect(find.text('Mark Collected'), findsNothing); // collected jobs are read-only
  });

  testWidgets('create a job: choose customer, adjust template hours, queue production', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.text('Add Job'));
    await tester.pumpAndSettle();

    expect(find.text('New Commission'), findsOneWidget);
    expect(find.text('Measurement & Pattern Drafting'), findsOneWidget); // first garment preselected
    expect(find.textContaining('13.5 HOURS', findRichText: true), findsOneWidget); // workload from the template

    await tester.tap(find.text('Choose customer'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Kofi Mensah'));
    await tester.pumpAndSettle();
    expect(find.text('INTAKE · 2 OF 3'), findsOneWidget);

    await tester.enterText(find.widgetWithText(TextField, '6.0'), '7.5');
    await tester.pumpAndSettle();
    expect(find.textContaining('15.0 HOURS', findRichText: true), findsOneWidget);

    await tester.tap(find.text('Queue Production'));
    await tester.pumpAndSettle();

    final created = backend.jobs.jobs.single;
    expect(created['customer_id'], kofi);
    expect(((created['tasks'] as List)[2] as Map)['estimated_seconds'], 27000);
    expect(find.text('PRODUCTION STATUS'), findsOneWidget); // replaced by the new job sheet
    expect(find.textContaining('JOB #024'), findsOneWidget);
  });

  testWidgets('drafts cannot start stages until queued', (tester) async {
    backend.jobs.addJob(kofi, status: 'draft');
    await pumpApp(tester);
    await tester.tap(find.text('View Sheet'));
    await tester.pumpAndSettle();

    expect(find.text('Queue Production'), findsOneWidget);
    expect(find.text('Active Subtasks'), findsOneWidget);
    await tester.tap(find.text('Queue Production'));
    await tester.pumpAndSettle();
    expect(backend.jobs.jobs.single['status'], 'queued');
    expect(find.text('Mark Stage Complete'), findsOneWidget);
  });

  testWidgets('customer commissions tab lists their jobs', (tester) async {
    backend.jobs.addJob(kofi, dueInDays: 5, done: 1);
    await pumpApp(tester, tab: 'Customers');
    await tester.tap(find.text('Kofi Mensah'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Commissions'));
    await tester.pumpAndSettle();

    expect(find.text('New Commission'), findsOneWidget);
    await scrollTo(tester, find.textContaining('JOB #024'));
    expect(find.textContaining('JOB #024'), findsOneWidget);
    expect(find.text('Cutting Stage'), findsOneWidget);
  });
}
