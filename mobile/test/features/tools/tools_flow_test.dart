import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nutofe/app/app.dart';
import 'package:nutofe/core/local/local_store.dart';
import 'package:nutofe/core/network/api_client.dart';
import 'package:nutofe/core/network/api_exception.dart';
import 'package:nutofe/core/providers.dart';
import 'package:nutofe/core/widgets/filter_pills.dart';
import 'package:nutofe/features/calendar/domain/calendar.dart';
import 'package:nutofe/features/calendar/domain/calendar_builder.dart';
import 'package:nutofe/features/sync/application/sync_providers.dart';
import 'package:nutofe/features/sync/domain/config_bundle.dart';
import 'package:nutofe/features/sync/domain/local_ops.dart';
import 'package:nutofe/features/sync/domain/presenter.dart';
import 'package:nutofe/features/tools/domain/tools.dart';

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

  Future<ProviderContainer> pumpTools(WidgetTester tester) async {
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
    await tester.tap(find.text('More').last);
    await settle(tester);
    await tester.tap(find.text('Tools & Equipment'));
    await settle(tester);
    return ProviderScope.containerOf(tester.element(find.byType(NutofeApp)));
  }

  Finder pills(int row) => find.byType(BottomSheet).evaluate().isEmpty ? find.byType(FilterPills).at(row) : find.descendant(of: find.byType(BottomSheet), matching: find.byType(FilterPills)).at(row);

  /// Taps a chip in the [row]-th horizontal pill row, scrolling it into view first.
  Future<void> tapPill(WidgetTester tester, String label, {int row = 0}) async {
    // Not dragUntilVisible: its final ensureVisible scrolls the page and hides the row under the header.
    final width = tester.view.physicalSize.width / tester.view.devicePixelRatio;
    bool onScreen() => find.text(label).evaluate().isNotEmpty && tester.getCenter(find.text(label)).dx < width - 60;
    for (var i = 0; i < 15 && !onScreen(); i++) {
      await tester.drag(pills(row), const Offset(-120, 0));
      await tester.pump(const Duration(milliseconds: 300));
    }
    await tester.tap(find.text(label));
  }

  String today() => businessToday(backend.config, DateTime.now());

  setUp(() {
    backend = FakeBackend();
    store = LocalStore.memory();
    tokens = MemoryTokenStore()
      ..access = 'nat_1'
      ..refresh = 'nrt_1'
      ..session = {'user': userJson(), 'business': businessJson};
  });

  group('maintenance rules (same as the server)', () {
    test('next date and state follow the cycle, the last service and a manual date', () {
      expect(MaintenanceRules.addDays('2026-10-30', 3), '2026-11-02');
      expect(MaintenanceRules.daysBetween('2026-10-09', '2026-10-01'), -8);
      expect(MaintenanceRules.next(intervalDays: 60, purchaseDate: '2026-01-01', createdDate: '2026-05-01'), '2026-03-02');
      expect(MaintenanceRules.next(intervalDays: 60, last: '2026-09-01', purchaseDate: '2026-01-01', createdDate: '2026-05-01'), '2026-10-31');
      expect(MaintenanceRules.next(override: '2026-12-24', intervalDays: 60, createdDate: '2026-05-01'), '2026-12-24');
      expect(MaintenanceRules.next(createdDate: '2026-05-01'), isNull);
      expect(MaintenanceRules.state('2026-10-08', 'operational', '2026-10-09', 7), (state: 'overdue', days: -1));
      expect(MaintenanceRules.state('2026-10-16', 'operational', '2026-10-09', 7), (state: 'due_soon', days: 7));
      expect(MaintenanceRules.state('2026-10-17', 'operational', '2026-10-09', 7), (state: 'ok', days: 8));
      expect(MaintenanceRules.state('2026-10-01', 'retired', '2026-10-09', 7), (state: 'none', days: null));
    });

    test('logging maintenance clears the manual date, sets condition and status; summary ranks the alerts', () {
      final juki = backend.addTool('Lockstitch #01', boughtDaysAgo: 100, interval: 60, condition: 'fair', status: 'needs_service')['id'] as String;
      final soon = backend.addTool('Lockstitch #02', boughtDaysAgo: 55, interval: 60)['id'] as String;
      final broken = backend.addTool('Steam Press', categoryId: 2, status: 'out_of_service')['id'] as String;
      backend.addTool('Old Singer', boughtDaysAgo: 400, interval: 30, status: 'retired');

      var p = Presenter(backend.server, backend.config);
      final summary = ToolSummary.fromJson(p.toolSummary());
      expect([summary.total, summary.operational, summary.needsService, summary.outOfService, summary.retired, summary.dueSoon, summary.overdue], [4, 1, 1, 1, 1, 1, 1]);
      expect(summary.alerts.map((t) => t.id), [juki, broken, soon]);

      backend.apply('PATCH', '/tools/$juki', {'version': 1, 'next_maintenance_override': MaintenanceRules.addDays(today(), 2)});
      expect(() => backend.apply('PATCH', '/tools/$juki', {'version': 2, 'next_maintenance_override': MaintenanceRules.addDays(today(), -1)}),
          throwsA(isA<ValidationException>().having((e) => e.forField('next_maintenance_override'), 'field', 'The next maintenance date cannot be in the past.')));
      backend.apply('POST', '/tools/$juki/maintenance', {'id': backend.newId(), 'maintenance_type': 'routine', 'condition_after': 'excellent', 'operational_status': 'operational'});

      p = Presenter(backend.server, backend.config);
      final tool = Tool.fromJson(p.tool(backend.toolRow(juki)));
      expect([tool.nextOverride, tool.condition, tool.status, tool.maintenanceState, tool.daysUntilDue, tool.maintenanceCount], [null, ToolCondition.excellent, ToolStatus.operational, MaintenanceState.ok, 60, 1]);
      expect(() => backend.apply('POST', '/tools/$juki/maintenance', {'maintenance_type': 'routine', 'performed_on': MaintenanceRules.addDays(today(), 1)}),
          throwsA(isA<ValidationException>().having((e) => e.forField('performed_on'), 'field', 'Maintenance cannot be logged for a future date.')));

      backend.apply('POST', '/tools/$broken/archive', {});
      expect(() => backend.apply('POST', '/tools/$broken/maintenance', {'maintenance_type': 'repair'}), throwsA(isA<ConflictException>().having((e) => e.code, 'code', 'TOOL_ARCHIVED')));
    });

    test('service due dates show in the calendar', () {
      backend.addTool('Lockstitch #02', boughtDaysAgo: 55, interval: 60, location: 'Bench 02');
      final now = DateTime.now();
      final day = DateTime(now.year, now.month, now.day).add(const Duration(days: 5));
      final items = CalendarBuilder(Presenter(backend.server, backend.config)).items(day, day.add(const Duration(days: 1)));
      expect(items.single.kind, CalendarKind.maintenance);
      expect(items.single.title, 'Service due: Lockstitch #02');
      expect(items.single.subtitle, 'Sewing Machines • Bench 02');
    });
  });

  testWidgets('tools screen: fleet banner, the most urgent tool, chips and the roster', (tester) async {
    backend
      ..addTool('Lockstitch Machine #01', boughtDaysAgo: 30, interval: 60, location: 'Bench 01', brand: 'Juki DDL-9000C')
      ..addTool('Lockstitch Machine #02', boughtDaysAgo: 57, interval: 60, location: 'Bench 02')
      ..addTool('Steam Press Iron', categoryId: 2, boughtDaysAgo: 10, interval: 90);
    await pumpTools(tester);

    expect(find.text('Equip & Calibrate'), findsOneWidget);
    expect(find.text('Total Units'), findsOneWidget);
    expect(find.text('IMMINENT ACTION'), findsOneWidget);
    expect(find.text('3 Days Left'), findsOneWidget);
    expect(find.text('All Equipment (3)'), findsOneWidget);
    expect(find.text('Sewing Machines (2)'), findsOneWidget);
    expect(find.text('Due in 30 days'), findsOneWidget);
    expect(find.text('Svc Due'), findsOneWidget);

    await tapPill(tester, 'Irons & Pressing (1)');
    await settle(tester);
    expect(find.text('Lockstitch Machine #01'), findsNothing);
    expect(find.text('Steam Press Iron'), findsOneWidget);
  });

  testWidgets('record maintenance from the imminent action card', (tester) async {
    final juki = backend.addTool('Lockstitch Machine #02', boughtDaysAgo: 70, interval: 60, status: 'needs_service', condition: 'fair')['id'] as String;
    await pumpTools(tester);
    expect(find.text('10 Days Overdue'), findsOneWidget);

    await tester.tap(find.text('Log Service'));
    await settle(tester);
    expect(find.text('Record maintenance'), findsOneWidget);
    await tester.enterText(find.descendant(of: find.byType(BottomSheet), matching: find.byType(TextField)).first, 'Oil flush');
    await tapPill(tester, 'Excellent', row: 1);
    await tester.tap(find.text('Save maintenance'));
    await settle(tester);

    final log = backend.logsOf(juki).single;
    expect([log['maintenance_type'], log['description'], log['performed_on'], log['condition_after']], ['routine', 'Oil flush', today(), 'excellent']);
    expect(backend.toolRow(juki)['operational_status'], 'operational', reason: 'a tool waiting for service is back in order after it');
    expect(find.text('Maintenance logged for Lockstitch Machine #02.'), findsOneWidget);
    expect(find.text('IMMINENT ACTION'), findsNothing);
    expect(find.text('Due in 60 days'), findsOneWidget);
  });

  testWidgets('register a tool, then remove a maintenance entry made by mistake', (tester) async {
    await pumpTools(tester);
    await tester.tap(find.text('Register tool'));
    await settle(tester);

    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), 'Tailor Shears 13"');
    await tapPill(tester, 'Cutting Tools');
    await tester.enterText(fields.at(1), 'Ernest Wright');
    await tester.enterText(fields.at(3), 'Cutting Table A');
    await tester.enterText(fields.at(4), '120');
    await tester.tap(find.text('Register tool').last);
    await settle(tester);

    final tool = backend.server.all(Tables.tools).single;
    expect([tool['tool_name'], tool['category_id'], tool['brand_model'], tool['storage_location'], tool['maintenance_interval_days']], ['Tailor Shears 13"', 3, 'Ernest Wright', 'Cutting Table A', 120]);
    expect(find.text('Due in 120 days'), findsOneWidget, reason: 'opens the new tool; the cycle counts from today');

    backend.logService(tool['id'] as String, 0, type: 'sharpening', description: 'Typed on the wrong tool');
    final container = ProviderScope.containerOf(tester.element(find.byType(NutofeApp)));
    unawaited(container.read(syncControllerProvider.notifier).syncNow());
    await settle(tester);
    expect(find.text('Typed on the wrong tool'), findsOneWidget);

    await tester.ensureVisible(find.byTooltip('Remove entry'));
    await tester.tap(find.byTooltip('Remove entry'));
    await settle(tester);
    await tester.tap(find.text('Remove'));
    await settle(tester);
    expect(backend.logsOf(tool['id'] as String), isEmpty);
    expect(find.text('Typed on the wrong tool'), findsNothing);
  });

  testWidgets('maintenance logged without signal shows at once and reaches the server later', (tester) async {
    final iron = backend.addTool('Steam Press Iron', categoryId: 2, boughtDaysAgo: 100, interval: 90)['id'] as String;
    final container = await pumpTools(tester);

    backend.adapter.offline = true;
    await tester.tap(find.text('Log Service'));
    await settle(tester);
    await tapPill(tester, 'Cleaning');
    await tester.tap(find.text('Save maintenance'));
    await settle(tester);
    expect(find.text('Due in 90 days'), findsOneWidget);
    expect(store.outbox.single.op, 'tool.maintenance');
    expect(backend.logsOf(iron), isEmpty);

    backend.adapter.offline = false;
    unawaited(container.read(syncControllerProvider.notifier).syncNow());
    await settle(tester);
    expect(store.outbox, isEmpty);
    expect(backend.logsOf(iron).single['maintenance_type'], 'cleaning');
  });
}
