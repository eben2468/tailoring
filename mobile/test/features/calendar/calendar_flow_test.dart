import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nutofe/app/app.dart';
import 'package:nutofe/core/local/local_store.dart';
import 'package:nutofe/core/network/api_client.dart';
import 'package:nutofe/core/providers.dart';
import 'package:nutofe/features/calendar/domain/calendar.dart';
import 'package:nutofe/features/calendar/domain/calendar_builder.dart';
import 'package:nutofe/features/sync/domain/config_bundle.dart';
import 'package:nutofe/features/sync/domain/presenter.dart';

import '../../support/fake_backend.dart';
import '../../support/fakes.dart';

void main() {
  late FakeBackend backend;
  late MemoryTokenStore tokens;
  late String kofi;
  final today = dayOf(DateTime.now());
  DateTime at(int hour, [int minute = 0, int days = 0]) => today.add(Duration(days: days, hours: hour, minutes: minute));

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
    await tester.pumpAndSettle();
    await tester.tap(find.text('Calendar').last);
    await tester.pumpAndSettle();
  }

  /// Plans a stage of [job] as a block today.
  void plan(Map<String, dynamic> job, int index, DateTime start, Duration length) {
    final task = (job['tasks'] as List)[index] as Map<String, dynamic>;
    backend.apply('PATCH', '/tasks/${task['id']}', {
      'version': backend.server.get(Tables.tasks, task['id'] as String)!['version'],
      'scheduled_start': start.toUtc().toIso8601String(),
      'scheduled_end': start.add(length).toUtc().toIso8601String(),
    });
  }

  setUp(() {
    backend = FakeBackend();
    kofi = backend.addCustomer('Kofi Mensah', phone: '+233241110001')['id'] as String;
    tokens = MemoryTokenStore()
      ..access = 'nat_1'
      ..refresh = 'nrt_1'
      ..session = {'user': userJson(), 'business': businessJson};
  });

  test('ISO week numbers and week capacity', () {
    expect(isoWeek(DateTime(2026, 10, 15)), 42);
    expect(isoWeek(DateTime(2027, 1, 1)), 53); // Friday: still the last week of 2026
    expect(weekStart(DateTime(2026, 10, 15)), DateTime(2026, 10, 12));

    final b = FakeBackend();
    final c = b.addCustomer('Kofi')['id'] as String;
    final job = b.jobs.addJob(c);
    final monday = weekStart(DateTime.now());
    final task = (job['tasks'] as List)[2] as Map<String, dynamic>;
    b.apply('PATCH', '/tasks/${task['id']}', {
      'version': b.server.get(Tables.tasks, task['id'] as String)!['version'],
      'scheduled_start': monday.add(const Duration(hours: 9)).toUtc().toIso8601String(),
      'scheduled_end': monday.add(const Duration(hours: 13)).toUtc().toIso8601String(),
    });
    final summary = CalendarBuilder(Presenter(b.server, ConfigBundle.fromJson(b.configJson))).week(monday);
    expect(summary.plannedSeconds, 4 * 3600);
    expect(summary.capacitySeconds, 6 * 8 * 3600); // six open days × 8 h
    expect(summary.load, closeTo(4 / 48, 1e-9));
  });

  testWidgets('week view shows the day\'s production blocks, appointments and job dates', (tester) async {
    final job = backend.jobs.addJob(kofi, dueInDays: 0, done: 2);
    plan(job, 2, at(8, 30), const Duration(hours: 4));
    final ama = backend.addCustomer('Ama Mensah')['id'] as String;
    backend
      ..addAppointment('Structured blazer fitting', at(13, 30), customerId: ama, location: 'Fitting Room 1', status: 'confirmed')
      ..addAppointment('Next week fitting', at(10, 0, 7), customerId: ama);
    await pumpApp(tester);

    expect(find.text('Atelier Schedule'), findsOneWidget);
    expect(find.text('Week ${isoWeek(today)}'), findsOneWidget);
    expect(find.text('TODAY'), findsOneWidget);
    expect(find.text('1 Fitting • 4.0h Production Today'), findsOneWidget);
    expect(find.text('4.0h planned of 48.0h'), findsOneWidget);

    await tester.scrollUntilVisible(find.text('Sewing & Assembly'), 300, scrollable: find.byType(Scrollable).first);
    expect(find.text('ATELIER PRODUCTION WORK'), findsOneWidget);
    expect(find.text('08:30 – 12:30'), findsWidgets);
    expect(find.text('Due: 3-Piece Suit'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Ama Mensah'), 300, scrollable: find.byType(Scrollable).first);
    expect(find.text('Structured blazer fitting'), findsOneWidget);
    expect(find.text('Fitting Room 1'), findsOneWidget);
    expect(find.text('Confirmed'), findsOneWidget);
    expect(find.text('Next week fitting'), findsNothing);
  });

  testWidgets('book a fitting for a job: linked to its fitting stage; overlaps ask first', (tester) async {
    final job = backend.jobs.addJob(kofi, jobTypeId: 2, status: 'queued', dueInDays: 10);
    // Something is already booked at the form's default slot (the next whole hour, between 08:00 and 17:00).
    final slot = DateTime.now().add(const Duration(hours: 1));
    final booked = DateTime(today.year, today.month, today.day, slot.hour.clamp(8, 17));
    backend.addAppointment('Consultation', booked, type: 'consultation', minutes: 60);
    await pumpApp(tester);

    await tester.tap(find.text('Schedule'));
    await tester.pumpAndSettle();
    expect(find.text('New appointment'), findsOneWidget);
    await tester.tap(find.text('Choose customer'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Kofi Mensah').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('#024 2-Piece Suit'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextField, 'Fitting — 2-Piece Suit'), findsOneWidget, reason: 'title suggested from the job');

    await tester.tap(find.text('Book Fitting'));
    await tester.pumpAndSettle();
    expect(find.text('Time already booked'), findsOneWidget);
    await tester.tap(find.text('Book anyway'));
    await tester.pumpAndSettle();

    final fitting = backend.appointments.firstWhere((a) => a['appointment_type'] == 'fitting');
    expect(fitting['job_id'], job['id']);
    expect(fitting['job_task_id'], ((job['tasks'] as List)[1] as Map)['id'], reason: 'linked to the Baste Fitting stage');
    expect(DateTime.parse(fitting['starts_at'] as String).toLocal(), booked);
    expect(find.text('Atelier Schedule'), findsOneWidget, reason: 'back on the calendar');
  });

  testWidgets('confirm, then cancel an appointment from its screen', (tester) async {
    final a = backend.addAppointment('Forward fitting', at(15), customerId: kofi);
    await pumpApp(tester);
    await tester.scrollUntilVisible(find.text('Forward fitting'), 300, scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('Forward fitting'));
    await tester.pumpAndSettle();

    expect(find.text('Appointment'), findsWidgets);
    await tester.tap(find.text('Confirm'));
    await tester.pumpAndSettle();
    expect(backend.server.get(Tables.appointments, a['id'] as String)!['status'], 'confirmed');
    expect(find.text('Confirm'), findsNothing);

    await tester.scrollUntilVisible(find.text('Cancel appointment'), 200, scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('Cancel appointment'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel appointment').last);
    await tester.pumpAndSettle();
    expect(backend.server.get(Tables.appointments, a['id'] as String)!['status'], 'cancelled');
    expect(find.text('Mark done'), findsNothing, reason: 'cancelled appointments are read-only');
  });

  testWidgets('month view dots lead to the day view', (tester) async {
    backend.addAppointment('Collection', at(16, 0, 3), type: 'collection', customerId: kofi);
    await pumpApp(tester);
    await tester.tap(find.text('Month'));
    await tester.pumpAndSettle();
    final target = today.add(const Duration(days: 3));
    await tester.tap(find.text('${target.day}').last);
    await tester.pumpAndSettle();
    expect(find.textContaining(RegExp('${target.day}')), findsWidgets);
    await tester.scrollUntilVisible(find.text('Collection').first, 300, scrollable: find.byType(Scrollable).first);
    expect(find.text('Collection'), findsWidgets);
  });
}
