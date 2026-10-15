@Tags(['live'])
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:nutofe/core/local/local_store.dart';
import 'package:nutofe/core/network/api_client.dart';
import 'package:nutofe/core/network/api_exception.dart';
import 'package:nutofe/features/admin/data/admin_api.dart';
import 'package:nutofe/features/ai/data/ai_api.dart';
import 'package:nutofe/features/ai/domain/ai.dart';
import 'package:nutofe/features/auth/data/auth_api.dart';
import 'package:nutofe/features/auth/data/auth_repository.dart';
import 'package:nutofe/features/calendar/data/appointments_api.dart';
import 'package:nutofe/features/calendar/domain/calendar.dart';
import 'package:nutofe/features/customers/data/customers_api.dart';
import 'package:nutofe/features/customers/domain/customer.dart';
import 'package:nutofe/features/inventory/data/inventory_api.dart';
import 'package:nutofe/features/inventory/domain/inventory.dart';
import 'package:nutofe/features/jobs/data/jobs_api.dart';
import 'package:nutofe/features/jobs/domain/job.dart';
import 'package:nutofe/features/measurements/data/measurements_api.dart';
import 'package:nutofe/features/measurements/domain/measurement.dart';
import 'package:nutofe/features/notifications/data/notifications_api.dart';
import 'package:nutofe/features/reports/data/reports_api.dart';
import 'package:nutofe/features/reports/domain/reports.dart';
import 'package:nutofe/features/sync/data/sync_engine.dart';
import 'package:nutofe/features/timer/data/timer_api.dart';
import 'package:nutofe/features/tools/data/tools_api.dart';
import 'package:nutofe/features/tools/domain/tools.dart';

import '../support/fakes.dart';

/// Contract test: the app's real API layer against the running Laravel backend (demo data).
///
///   docker compose -f infra/docker-compose.yml up -d && docker exec -w /var/www/backend nutofe-php composer reset-dev
///   flutter test --tags live --dart-define=LIVE_API=http://localhost:8080/api/v1
///
/// Makes 3 sign-in requests per run; the API allows about 5 per minute per IP, so wait a minute between runs.
const _baseUrl = String.fromEnvironment('LIVE_API', defaultValue: 'http://localhost:8080/api/v1');

void main() {
  test('sign-in, profile, refresh, admin lists and sign-out against the real API', () async {
    final tokens = MemoryTokenStore();
    final client = ApiClient(baseUrl: _baseUrl, tokens: tokens);
    final repo = AuthRepository(AuthApi(client), tokens);

    // Wrong password → typed error with the server's message.
    await expectLater(
      repo.signIn('admin@nutofe.test', 'definitely-wrong'),
      throwsA(isA<UnauthorizedException>().having((e) => e.code, 'code', 'INVALID_CREDENTIALS')),
    );

    final session = await repo.signIn('admin@nutofe.test', 'Nutofe-Dev-2026!');
    expect(session.user.isAdmin, isTrue);
    expect(session.business.name, 'Nutɔfe');
    expect(session.business.currency, 'GHS');
    expect(tokens.access, startsWith('nat_'));

    final refreshed = await repo.refreshProfile();
    expect(refreshed.user.email, 'admin@nutofe.test');

    // Force the refresh path: invalidate the in-memory access token, the client must renew it.
    final oldRefresh = tokens.refresh;
    final validAccess = tokens.access;
    tokens.access = 'nat_invalid';
    await expectLater(repo.refreshProfile(), throwsA(isA<UnauthorizedException>()),
        reason: 'an unknown (not expired) token is UNAUTHENTICATED, which must not trigger a refresh');
    expect(tokens.refresh, oldRefresh);

    final admin = AdminApi(client);
    tokens.access = validAccess; // restore (no extra sign-in: login is rate-limited to a few per minute)
    final users = await admin.users();
    expect(users.items.map((u) => u.email), contains('owner@nutofe.test'));
    final log = await admin.auditLog();
    expect(log.items.first.action, startsWith('auth.'));

    // Validation errors arrive as field maps.
    final error = await admin.createUser(fullName: 'X', email: 'not-an-email', role: 'worker', password: 'short').then<Object>((_) => fail('should fail'), onError: (Object e) => e);
    expect((error as ValidationException).fieldErrors.keys, containsAll(['email', 'role']));

    await repo.signOut();
    expect(tokens.access, isNull);
  });


  test('customers, measurements, jobs and timer through the sync engine against the real API', () async {
    // Reuses the admin account (admin has business access) and signs in once: login is rate-limited.
    final tokens = MemoryTokenStore();
    final client = ApiClient(baseUrl: _baseUrl, tokens: tokens);
    final session = await AuthRepository(AuthApi(client), tokens).signIn('admin@nutofe.test', 'Nutofe-Dev-2026!');
    final store = LocalStore.memory();
    addTearDown(store.dispose);
    final actor = (id: session.user.id, name: session.user.fullName);
    final engine = SyncEngine(client: client, store: store, actor: () => actor);
    await engine.sync(); // first download: business rows + configuration
    expect(engine.config!.jobTypes, isNotEmpty);
    expect(store.all(Tables.customers), isNotEmpty);

    final customers = CustomersApi(engine);
    final measurements = MeasurementsApi(engine);
    final stamp = DateTime.now().millisecondsSinceEpoch % 100000000;
    final phone = '+23324${stamp.toString().padLeft(7, '0').substring(0, 7)}';

    // Create (local Ghana format is normalised server-side), then the duplicate warning.
    final created = await customers.create(CustomerDraft(fullName: 'Live Test $stamp', phone: '0${phone.substring(4)}'));
    expect(created.phone, phone, reason: 'the pulled row carries the server-normalised number');
    expect(created.version, 1);
    await expectLater(
      customers.create(CustomerDraft(fullName: 'Live Dupe $stamp', phone: phone)),
      throwsA(isA<ConflictException>().having((e) => e.code, 'code', 'DUPLICATE_PHONE')),
    );
    expect(customers.phoneCheck(phone).single.id, created.id);

    // Optimistic locking (only changed fields are sent).
    final updated = await customers.update(created.id, created.version, CustomerDraft(fullName: created.fullName, phone: phone, notes: 'Prefers mornings'));
    expect(updated.version, 2);
    await expectLater(
      customers.update(created.id, 1, CustomerDraft(fullName: '${created.fullName} (stale)', phone: phone)),
      throwsA(isA<ConflictException>().having((e) => e.code, 'code', 'CONFLICT_VERSION')),
    );

    // Measurements: inches in, cm stored, partial re-measure, current = latest per field.
    final fields = engine.config!.measurementGroups.expand((g) => (g['fields'] as List).cast<Map<String, dynamic>>());
    final chest = fields.firstWhere((f) => f['code'] == 'chest')['id'] as int;
    final waist = fields.firstWhere((f) => f['code'] == 'waist')['id'] as int;
    await measurements.record(created.id, unit: MeasurementUnit.inch, entries: [MeasurementEntry.length(chest, 42), MeasurementEntry.length(waist, 34.5)]);
    await measurements.record(created.id, unit: MeasurementUnit.inch, entries: [MeasurementEntry.length(waist, 34.25)]);
    final current = CurrentMeasurements.fromJson(engine.presenter()!.currentMeasurements(created.id));
    expect(MeasurementUnit.inch.format(current.byField(chest)!.valueCm!), '42.0');
    expect(MeasurementUnit.inch.format(current.byField(waist)!.valueCm!), '34.25');
    final invalid = await measurements
        .record(created.id, unit: MeasurementUnit.inch, entries: [MeasurementEntry.length(chest, 200)])
        .then<Object>((_) => fail('should fail'), onError: (Object e) => e);
    expect((invalid as ValidationException).forField('values.0.value'), contains('between'));

    // Jobs: created with client stage ids; the server keeps them and assigns the number.
    final jobs = JobsApi(engine);
    final suit = JobType.fromJson(engine.config!.jobTypes.firstWhere((t) => t['name'] == '3-Piece Suit'));
    final planned = [for (final t in suit.tasks) PlannedTask(taskType: t.taskType, name: t.name, estimatedSeconds: t.taskType.isMilestone ? 0 : 7200)];
    final setId = engine.presenter()!.measurementHistory(created.id).first['id'] as String;
    var job = await jobs.create(
      customerId: created.id,
      jobTypeId: suit.id,
      draft: false,
      fields: JobDraft(priority: JobPriority.high, measurementSetId: setId, fabricNote: 'Live test fabric'),
      tasks: planned,
    );
    expect(job.status, JobStatus.queued);
    expect(job.jobNumber, matches(RegExp(r'^\d{3,}$')));
    expect(job.hours.estimatedSeconds, 7200 * planned.where((t) => !t.taskType.isMilestone).length);
    job = await jobs.setTaskStatus(job.tasks.first, TaskStatus.completed);
    expect(job.status, JobStatus.inProgress);
    expect(job.currentTask!.name, job.tasks[1].name);

    // Timer online: one running timer per account; stop old demo timers first.
    final timers = TimerApi(engine);
    if (engine.presenter()!.activeTimer() != null) await timers.stop();
    await timers.start(job.tasks[1].id);
    expect((engine.presenter()!.activeTimer()!['task'] as Map)['id'], job.tasks[1].id);
    await timers.adjust(job.tasks[1].id, const Duration(minutes: 15));
    await expectLater(timers.start(job.tasks[3].id), throwsA(isA<ConflictException>().having((e) => e.code, 'code', 'TIMER_ALREADY_RUNNING')));
    await timers.stop(note: 'Live pause');

    // Offline: the same store, but no connection. Changes are applied locally and queued…
    final offline = SyncEngine(client: ApiClient(baseUrl: 'http://127.0.0.1:9/api/v1', tokens: tokens), store: store, actor: () => actor);
    await TimerApi(offline).start(job.tasks[2].id);
    await JobsApi(offline).addChecklistItem(job.tasks[2].id, 'Offline subtask');
    await TimerApi(offline).stop(note: 'Offline session', complete: true);
    expect(store.outbox.map((o) => o.op), ['timer.start', 'checklist.add', 'timer.stop']);
    expect(Job.fromJson(offline.presenter()!.job(store.get(Tables.jobs, job.id)!, detail: true)).tasks[2].status, TaskStatus.completed);

    // …and replayed in order when the connection returns.
    await engine.sync();
    expect(store.outbox, isEmpty);
    final synced = Job.fromJson(engine.presenter()!.job(store.get(Tables.jobs, job.id)!, detail: true));
    expect(synced.tasks[2].status, TaskStatus.completed);
    expect(synced.tasks[2].checklist.single.label, 'Offline subtask');
    expect(synced.tasks[2].logCount, 1);
    expect(synced.tasks[1].actualSeconds, greaterThanOrEqualTo(900));

    // Appointments: book a fitting for the job, overlap warning, confirm.
    final appointments = AppointmentsApi(engine);
    final slot = DateTime.now().add(Duration(days: 30 + stamp % 300, hours: 2)); // a free, unique slot
    final fitting = await appointments.create(AppointmentDraft(
      type: AppointmentType.fitting,
      title: 'Live fitting $stamp',
      startsAt: slot,
      endsAt: slot.add(const Duration(hours: 1)),
      customerId: created.id,
      jobId: job.id,
    ));
    expect(fitting.status, AppointmentStatus.scheduled);
    expect(fitting.jobNumber, job.jobNumber);
    await expectLater(
      appointments.create(AppointmentDraft(type: AppointmentType.consultation, title: 'Clash', startsAt: slot.add(const Duration(minutes: 30)), endsAt: slot.add(const Duration(minutes: 90)))),
      throwsA(isA<ConflictException>().having((e) => e.code, 'code', 'SCHEDULE_CONFLICT')),
    );
    expect((await appointments.setStatus(fitting, AppointmentStatus.confirmed)).status, AppointmentStatus.confirmed);
    await appointments.setStatus(await appointments.setStatus(fitting, AppointmentStatus.confirmed), AppointmentStatus.cancelled); // tidy

    // Inventory: a material with opening stock, usage for the job, the online stock guard,
    // offline usage past the stock (accepted on replay), then a stock count.
    final inventory = InventoryApi(engine);
    final fabric = (engine.config!.inventoryCategories.firstWhere((c) => c['is_active'] == true)['id'] as num).toInt();
    var material = await inventory.create(
      InventoryItemDraft(categoryId: fabric, name: 'Live thread $stamp', unit: 'spool', minStockLevel: 2, reorderQuantity: 10),
      openingQuantity: 3,
    );
    expect([material.quantityOnHand, material.status], [3, StockStatus.ok]);
    await inventory.record(material, TransactionType.usage, 1, jobId: job.id);
    await expectLater(
      inventory.record(material, TransactionType.usage, 5),
      throwsA(isA<ValidationException>().having((e) => e.code, 'code', 'INSUFFICIENT_STOCK').having((e) => e.forField('quantity'), 'field', 'Only 2 spools in stock. If the shelf holds more, record a stock count first.')),
    );
    await InventoryApi(offline).record(material, TransactionType.usage, 5, note: 'Used offline');
    await engine.sync();
    expect(store.outbox, isEmpty, reason: 'the server accepts usage recorded offline');
    material = InventoryItem.fromJson(engine.presenter()!.inventoryItem(store.get(Tables.inventoryItems, material.id)!));
    expect([material.quantityOnHand, material.status], [-3, StockStatus.negative]);
    await inventory.record(material, TransactionType.adjustment, 10);
    material = InventoryItem.fromJson(engine.presenter()!.inventoryItem(store.get(Tables.inventoryItems, material.id)!));
    expect([material.quantityOnHand, material.jobsUsedThisMonth], [10, 1]);
    expect(engine.presenter()!.jobMaterials(job.id).single['quantity_change'], -1);
    await inventory.setArchived(material, archived: true); // keep the dev list tidy

    // Tools: register with a cycle, overdue from the purchase date, log maintenance (online and offline).
    final toolsApi = ToolsApi(engine);
    final machines = (engine.config!.toolCategories.firstWhere((c) => c['is_active'] == true)['id'] as num).toInt();
    final bought = DateTime.now().subtract(const Duration(days: 100));
    var tool = await toolsApi.create(ToolDraft(categoryId: machines, name: 'Live machine $stamp', purchaseDate: bought, intervalDays: 60, status: ToolStatus.needsService));
    expect([tool.maintenanceState, tool.daysUntilDue], [MaintenanceState.overdue, -40]);
    await toolsApi.logMaintenance(tool, type: MaintenanceType.routine, performedOn: DateTime.now(), conditionAfter: ToolCondition.excellent, status: ToolStatus.operational);
    tool = Tool.fromJson(engine.presenter()!.tool(store.get(Tables.tools, tool.id)!));
    expect([tool.maintenanceState, tool.daysUntilDue, tool.condition, tool.status], [MaintenanceState.ok, 60, ToolCondition.excellent, ToolStatus.operational]);
    await expectLater(
      toolsApi.logMaintenance(tool, type: MaintenanceType.routine, performedOn: DateTime.now().add(const Duration(days: 2))),
      throwsA(isA<ValidationException>().having((e) => e.forField('performed_on'), 'field', 'Maintenance cannot be logged for a future date.')),
    );
    await ToolsApi(offline).logMaintenance(tool, type: MaintenanceType.cleaning, performedOn: DateTime.now(), description: 'Offline clean');
    await engine.sync();
    expect(store.outbox, isEmpty);
    expect(engine.presenter()!.toolLogs(tool.id).map((l) => l['maintenance_type']), containsAll(['routine', 'cleaning']));
    await toolsApi.setArchived(tool, archived: true); // keep the dev list tidy

    // Reports: every report answers for the last 30 days, and the phone keeps a copy for offline use.
    final reports = ReportsApi(client, store);
    final range = ReportPreset.last30.range(DateTime.now());
    for (final kind in ReportKind.values) {
      final report = await reports.fetch(kind, range);
      expect(report.section('period')['from'], range.fromYmd, reason: kind.key);
      expect(report.series, hasLength(30), reason: '${kind.key}: one point per day');
    }
    final jobsReport = await reports.fetch(ReportKind.jobs, range);
    expect(jobsReport.section('totals')['completed'], isA<int>());
    // Notifications: the admin (developer) account receives no business alerts; the calls answer.
    expect((await client.get('/notifications/unread-count') as Map)['unread'], isA<int>());
    await NotificationsApi(engine).markAllRead();
    expect(engine.presenter()!.unreadNotifications(), 0);

    // AI assistant: real AI service behind the core API (figures only unless a Gemini key is set).
    final aiApi = AiApi(client, engine);
    final overview = await aiApi.overview();
    expect(overview.workload['state'], isA<String>());
    final answer = await aiApi.ask([const ChatMessage(fromUser: true, text: 'What should I work on today?')]);
    expect(answer.text, isNotEmpty);
    final estimates = await aiApi.estimate(suit.id, 1);
    expect(estimates, isNotEmpty);
    expect(estimates.every((e) => e.basis == 'history' || e.basis == 'defaults'), isTrue);

    // Dashboard: the phone's offline figures (Presenter.dashboard) match GET /dashboard.
    await engine.sync();
    final server = (await client.get('/dashboard') as Map).cast<String, dynamic>();
    final local = engine.presenter()!.dashboard();
    List<Object?> ids(Map<String, dynamic> d, String key, String field) => [for (final e in d[key] as List) (e as Map)[field]];
    Map<String, Object?> view(Map<String, dynamic> d) => {
          'date': d['date'],
          'shop': d['shop'],
          'counts': d['counts'],
          'appointments_today': d['appointments_today'],
          'workload': d['workload'],
          'schedule': [for (final i in d['schedule'] as List) [(i as Map)['kind'], i['title'], i['task_id'], i['appointment_id'], i['starts_at'], i['remaining_seconds']]],
          'priority_jobs': ids(d, 'priority_jobs', 'id'),
          'inventory': [d['inventory_alert_count'], ids(d, 'inventory_alerts', 'id')],
          'maintenance': [d['maintenance_alert_count'], ids(d, 'maintenance_alerts', 'id')],
          'insights': ids(d, 'insights', 'id'),
        };
    expect(jsonDecode(jsonEncode(view(local))), jsonDecode(jsonEncode(view(server))));

    final offlineReport = await ReportsApi(ApiClient(baseUrl: 'http://127.0.0.1:9/api/v1', tokens: tokens), store).fetch(ReportKind.hours, range);
    expect(offlineReport.stale, isTrue);

    await expectLater(jobs.setStatus(job.id, JobStatus.readyForCollection), throwsA(isA<ConflictException>().having((e) => e.code, 'code', 'TASKS_INCOMPLETE')));
    job = await jobs.setStatus(job.id, JobStatus.cancelled, reason: 'Live test clean-up');
    expect(job.status, JobStatus.cancelled);
    await customers.setArchived(created.id, archived: true); // keep the dev list tidy
  });
}
