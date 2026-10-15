import 'dart:convert';
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nutofe/app/app.dart';
import 'package:nutofe/core/local/local_store.dart';
import 'package:nutofe/core/network/api_client.dart';
import 'package:nutofe/core/providers.dart';
import 'package:nutofe/features/sync/application/sync_providers.dart';
import 'package:nutofe/features/sync/data/sync_engine.dart';
import 'package:nutofe/features/sync/domain/config_bundle.dart';
import 'package:nutofe/features/sync/domain/local_ops.dart';
import 'package:nutofe/features/sync/domain/presenter.dart';

import '../../support/fake_backend.dart';
import '../../support/fakes.dart';

void main() {
  late FakeBackend backend;
  late MemoryTokenStore tokens;
  late LocalStore store;
  late String kofi;

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<ProviderContainer> pumpApp(WidgetTester tester, {String tab = 'Jobs'}) async {
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
    await tester.tap(find.text(tab).last);
    await settle(tester);
    return ProviderScope.containerOf(tester.element(find.byType(NutofeApp)));
  }

  Map<String, dynamic> serverTask(String jobId, int index) => (backend.jobs.jobs.firstWhere((j) => j['id'] == jobId)['tasks'] as List)[index] as Map<String, dynamic>;

  setUp(() {
    backend = FakeBackend();
    store = LocalStore.memory();
    kofi = backend.addCustomer('Kofi Mensah', phone: '+233241110001')['id'] as String;
    tokens = MemoryTokenStore()
      ..access = 'nat_1'
      ..refresh = 'nrt_1'
      ..session = {'user': userJson(), 'business': businessJson};
  });

  testWidgets('work done offline shows at once, waits in the queue, and reaches the server on reconnect', (tester) async {
    final job = backend.jobs.addJob(kofi, dueInDays: 3, done: 3);
    final container = await pumpApp(tester);
    await tester.tap(find.text('View Sheet'));
    await settle(tester);

    backend.adapter.offline = true; // the workshop loses signal
    await tester.tap(find.text('Mark Stage Complete'));
    await settle(tester);

    expect(find.text('Finishing & Buttonholes completed.'), findsOneWidget);
    expect(find.text('Ready for Collection'), findsWidgets, reason: 'the sheet moved on using the local copy');
    expect(serverTask(job['id'] as String, 3)['status'], 'in_progress', reason: 'nothing reached the server yet');
    expect(store.outbox.single.label, 'Finishing & Buttonholes: done');

    await tester.pageBack();
    await settle(tester);
    expect(find.text('Offline · 1 change saved on this phone'), findsOneWidget);

    backend.adapter.offline = false;
    unawaited(container.read(syncControllerProvider.notifier).syncNow());
    await settle(tester);
    expect(serverTask(job['id'] as String, 3)['status'], 'completed');
    expect(store.outbox, isEmpty);
    expect(find.textContaining('Offline'), findsNothing);
  });

  testWidgets('a timer started without signal keeps its real start time when it syncs', (tester) async {
    final job = backend.jobs.addJob(kofi, dueInDays: 3, done: 2);
    final container = await pumpApp(tester);

    backend.adapter.offline = true;
    final tappedAt = DateTime.now().toUtc();
    await tester.tap(find.text('Start Timer'));
    await settle(tester);
    expect(find.text('ACTIVE SESSION'), findsOneWidget);
    expect(backend.jobs.running, isNull);
    expect(store.outbox.single.body['occurred_at'], isNotNull);

    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 1200))); // signal comes back a little later (real time)
    backend.adapter.offline = false;
    unawaited(container.read(syncControllerProvider.notifier).syncNow());
    await settle(tester);

    final running = backend.jobs.running!;
    expect(running['job_task_id'], serverTask(job['id'] as String, 2)['id']);
    expect(DateTime.parse(running['started_at'] as String).difference(tappedAt).inMilliseconds.abs(), lessThan(1000));
  });

  testWidgets('a change edited elsewhere in the meantime needs a decision, and "Keep my version" resends it', (tester) async {
    final container = await pumpApp(tester, tab: 'Customers');
    await tester.tap(find.text('Kofi Mensah'));
    await settle(tester);
    await tester.tap(find.byTooltip('Edit customer'));
    await settle(tester);

    backend.adapter.offline = true;
    await tester.enterText(find.byType(TextFormField).at(0), 'Kofi A. Mensah');
    await tester.tap(find.text('Save changes'));
    await settle(tester);
    expect(store.outbox, hasLength(1));

    // Meanwhile another device changed the same customer.
    backend.apply('PATCH', '/customers/$kofi', {'version': 1, 'notes': 'Prefers mornings'});

    backend.adapter.offline = false;
    unawaited(container.read(syncControllerProvider.notifier).syncNow());
    await settle(tester);
    expect(store.outbox.single.status, OutboxStatus.failed);
    expect(store.outbox.single.errorCode, 'CONFLICT_VERSION');

    await tester.pageBack(); // the form closed on save: profile → customers list
    await settle(tester);
    expect(find.text('1 change needs your attention'), findsOneWidget);
    await tester.tap(find.text('1 change needs your attention'));
    await settle(tester);
    expect(find.text('This customer was changed on another device. Reload to see the latest details.'), findsOneWidget);

    await tester.tap(find.text('Keep my version'));
    await settle(tester);
    expect(backend.customers.single['full_name'], 'Kofi A. Mensah');
    expect(backend.customers.single['notes'], 'Prefers mornings', reason: 'the other device\'s change to another field is kept');
    expect(store.outbox, isEmpty);
  });

  testWidgets('a duplicate phone found only when syncing can be saved anyway or discarded', (tester) async {
    final container = await pumpApp(tester, tab: 'Customers');
    backend.addCustomer('Ama Owusu', phone: '+233201110002'); // added on another phone, not pulled yet

    backend.adapter.offline = true;
    await tester.tap(find.text('Customer'));
    await tester.pump(const Duration(milliseconds: 600));
    await tester.enterText(find.byType(TextFormField).at(0), 'Ama O.');
    await tester.enterText(find.byType(TextFormField).at(1), '020 111 0002');
    await tester.tap(find.text('Add customer'));
    await settle(tester);
    expect(find.text('Ama O.'), findsWidgets, reason: 'saved on the phone');

    backend.adapter.offline = false;
    unawaited(container.read(syncControllerProvider.notifier).syncNow());
    await settle(tester);
    expect(store.outbox.single.errorCode, 'DUPLICATE_PHONE');

    unawaited(container.read(syncEngineProvider).discard(store.outbox.single));
    await settle(tester);
    expect(store.outbox, isEmpty);
    expect(store.all(Tables.customers).map((c) => c['full_name']), isNot(contains('Ama O.')), reason: 'the refused customer is removed from the phone');
    expect(backend.customers.where((c) => c['full_name'] == 'Ama O.'), isEmpty);
  });

  testWidgets('first start without a connection explains and retries', (tester) async {
    backend.adapter.offline = true;
    await pumpApp(tester);
    expect(find.text('You are offline'), findsOneWidget);
    backend.adapter.offline = false;
    await tester.tap(find.text('Try again'));
    await settle(tester);
    expect(find.text('Production Jobs'), findsOneWidget);
  });

  test('the local copy survives restarts (file storage), and the queue keeps its order', () {
    final dir = Directory.systemTemp.createTempSync('nutofe_store');
    addTearDown(() => dir.deleteSync(recursive: true));
    final path = '${dir.path}/nutofe.db';

    final first = LocalStore.open(path)
      ..put(Tables.customers, {'id': 'c1', 'full_name': 'Kofi', 'deleted_at': null})
      ..setMeta('sync_cursor', '42')
      ..enqueue(OutboxItem(seq: 0, op: 'customer.create', method: 'POST', path: '/customers', body: const {'id': 'c1'}, label: 'Add Kofi', createdAt: DateTime.utc(2026)))
      ..enqueue(OutboxItem(seq: 0, op: 'customer.update', method: 'PATCH', path: '/customers/c1', body: const {'version': 1}, label: 'Edit Kofi', createdAt: DateTime.utc(2026)));
    first.dispose();

    final again = LocalStore.open(path);
    addTearDown(again.dispose);
    expect(again.get(Tables.customers, 'c1')!['full_name'], 'Kofi');
    expect(again.meta('sync_cursor'), '42');
    expect(again.outbox.map((o) => o.label), ['Add Kofi', 'Edit Kofi']);
    again.wipe();
    expect(again.all(Tables.customers), isEmpty);
    expect(again.outbox, isEmpty);
  });

  test('rows of a table added to sync later are downloaded once, with a fresh configuration', () async {
    final backend = FakeBackend();
    backend.addAppointment('Fitting', DateTime.now().add(const Duration(days: 1)));
    final store = LocalStore.memory()
      ..setMeta('sync_cursor', '9999') // synced before appointments were part of sync
      ..setMeta('sync_tables', 'customers,measurement_sets,jobs,job_tasks,job_task_checklist_items,work_logs')
      // the older app's configuration: same version, but without inventory categories
      ..setMeta('config', jsonEncode({...backend.configJson, 'inventory_categories': []}));
    addTearDown(store.dispose);
    final tokens = MemoryTokenStore()..access = 'nat_1';
    final engine = SyncEngine(client: ApiClient(baseUrl: 'http://api.test/api/v1', tokens: tokens, adapter: backend.adapter), store: store, actor: () => (id: 1, name: 'Owner'));
    await engine.pull();
    expect(store.all(Tables.appointments).single['title'], 'Fitting');
    expect(engine.config!.inventoryCategories, isNotEmpty);
    expect(store.meta('sync_tables'), Tables.all.join(','));
  });

  test('local hours and progress follow the server rules', () {
    final backend = FakeBackend();
    final customer = backend.addCustomer('Kofi')['id'] as String;
    final job = backend.jobs.addJob(customer, done: 1, actualSeconds: {1: 7 * 3600}, status: 'in_progress');
    final config = ConfigBundle.fromJson(backend.configJson);
    final sheet = Presenter(backend.server, config, userId: 1).job(backend.server.get(Tables.jobs, job['id'] as String)!, detail: true);
    final tasks = (sheet['tasks'] as List).cast<Map<String, dynamic>>();

    expect(tasks[0]['progress_percent'], 100.0); // completed
    expect(tasks[1]['actual_seconds'], 7 * 3600); // 7 h logged on a 3 h estimate
    expect(tasks[1]['progress_percent'], 99.0); // capped until completed
    expect(tasks[1]['overrun_seconds'], 4 * 3600);
    final hours = sheet['hours'] as Map<String, dynamic>;
    expect(hours['estimated_seconds'], (13.5 * 3600).round());
    expect(hours['remaining_seconds'], 8 * 3600, reason: 'overrun on one stage hides no work left on others');

    // Same example as the architecture document: 12 h estimated, 7 h done → 5 h left, 58.33 %.
    final t = Hours.task(status: 'in_progress', estimated: 12 * 3600, actual: 7 * 3600);
    expect(t.remaining, 5 * 3600);
    expect(t.progress, 58.33);

    expect(normalizePhone('024 111 0001'), '+233241110001');
    expect(normalizePhone('233241110001'), '+233241110001');
  });
}