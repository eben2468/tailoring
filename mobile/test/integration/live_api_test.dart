@Tags(['live'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:nutofe/core/network/api_client.dart';
import 'package:nutofe/core/network/api_exception.dart';
import 'package:nutofe/features/admin/data/admin_api.dart';
import 'package:nutofe/features/auth/data/auth_api.dart';
import 'package:nutofe/features/auth/data/auth_repository.dart';
import 'package:nutofe/features/customers/data/customers_api.dart';
import 'package:nutofe/features/customers/domain/customer.dart';
import 'package:nutofe/features/jobs/data/jobs_api.dart';
import 'package:nutofe/features/jobs/domain/job.dart';
import 'package:nutofe/features/measurements/data/measurements_api.dart';
import 'package:nutofe/features/measurements/domain/measurement.dart';

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

  test('customers and measurements against the real API', () async {
    // Reuses the admin session (admin has business access) to stay under the login rate limit.
    final tokens = MemoryTokenStore();
    final client = ApiClient(baseUrl: _baseUrl, tokens: tokens);
    await AuthRepository(AuthApi(client), tokens).signIn('admin@nutofe.test', 'Nutofe-Dev-2026!');
    final customers = CustomersApi(client);
    final measurements = MeasurementsApi(client);
    final stamp = DateTime.now().millisecondsSinceEpoch % 100000000;
    final phone = '+23324${stamp.toString().padLeft(7, '0').substring(0, 7)}';

    // Create (local Ghana format is normalised server-side), then the duplicate warning.
    final created = await customers.create(CustomerDraft(fullName: 'Live Test $stamp', phone: '0${phone.substring(4)}'));
    expect(created.phone, phone);
    expect(created.version, 1);
    await expectLater(
      customers.create(CustomerDraft(fullName: 'Live Dupe $stamp', phone: phone)),
      throwsA(isA<ConflictException>().having((e) => e.code, 'code', 'DUPLICATE_PHONE')),
    );
    expect((await customers.phoneCheck(phone)).single.id, created.id);

    // Optimistic locking.
    final updated = await customers.update(created.id, created.version, CustomerDraft(fullName: created.fullName, phone: phone, notes: 'Prefers mornings'));
    expect(updated.version, 2);
    await expectLater(
      customers.update(created.id, 1, CustomerDraft(fullName: created.fullName, phone: phone)),
      throwsA(isA<ConflictException>().having((e) => e.code, 'code', 'CONFLICT_VERSION')),
    );

    // Measurements: inches in, cm stored, partial re-measure, current = latest per field.
    final groups = await measurements.fields();
    final chest = groups.expand((g) => g.fields).firstWhere((f) => f.code == 'chest');
    final waist = groups.expand((g) => g.fields).firstWhere((f) => f.code == 'waist');
    await measurements.record(created.id, unit: MeasurementUnit.inch, entries: [MeasurementEntry.length(chest.id, 42), MeasurementEntry.length(waist.id, 34.5)]);
    await measurements.record(created.id, unit: MeasurementUnit.inch, entries: [MeasurementEntry.length(waist.id, 34.25)]);

    final current = await measurements.current(created.id);
    expect(MeasurementUnit.inch.format(current.byField(chest.id)!.valueCm!), '42.0');
    expect(MeasurementUnit.inch.format(current.byField(waist.id)!.valueCm!), '34.25');
    expect((await measurements.history(created.id)).items, hasLength(2));

    final invalid = await measurements
        .record(created.id, unit: MeasurementUnit.inch, entries: [MeasurementEntry.length(chest.id, 200)])
        .then<Object>((_) => fail('should fail'), onError: (Object e) => e);
    expect((invalid as ValidationException).forField('values.0.value'), contains('between'));

    // Jobs: create from the garment template with edited hours, work a stage, status rules.
    final jobs = JobsApi(client);
    final suit = (await jobs.jobTypes()).firstWhere((t) => t.name == '3-Piece Suit');
    final planned = [for (final t in suit.tasks) PlannedTask(taskType: t.taskType, name: t.name, estimatedSeconds: t.taskType.isMilestone ? 0 : 7200)];
    final sets = (await measurements.history(created.id)).items;
    var job = await jobs.create(
      customerId: created.id,
      jobTypeId: suit.id,
      draft: false,
      fields: JobDraft(priority: JobPriority.high, measurementSetId: sets.first.id, fabricNote: 'Live test fabric'),
      tasks: planned,
    );
    expect(job.status, JobStatus.queued);
    expect(job.jobNumber, matches(RegExp(r'^\d{3,}$')));
    expect(job.hours.estimatedSeconds, 7200 * planned.where((t) => !t.taskType.isMilestone).length);
    expect(job.measurementSetId, sets.first.id);

    job = await jobs.setTaskStatus(job.tasks.first, TaskStatus.completed);
    expect(job.status, JobStatus.inProgress); // completing work moves a queued job into production
    expect(job.currentTask!.name, job.tasks[1].name);
    expect(job.tasks.first.progressPercent, 100);

    await expectLater(jobs.setStatus(job.id, JobStatus.readyForCollection), throwsA(isA<ConflictException>().having((e) => e.code, 'code', 'TASKS_INCOMPLETE')));
    job = await jobs.setStatus(job.id, JobStatus.cancelled, reason: 'Live test clean-up');
    expect(job.status, JobStatus.cancelled);
    expect((await jobs.list(filter: 'cancelled', customerId: created.id)).items.single.id, job.id);

    await customers.setArchived(created.id, archived: true); // keep the dev list tidy
  });
}
