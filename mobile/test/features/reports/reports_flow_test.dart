import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nutofe/app/app.dart';
import 'package:nutofe/core/local/local_store.dart';
import 'package:nutofe/core/network/api_client.dart';
import 'package:nutofe/core/providers.dart';
import 'package:nutofe/features/reports/domain/reports.dart';
import 'package:nutofe/features/reports/presentation/report_widgets.dart';
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

  Future<void> pumpReports(WidgetTester tester) async {
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
    await tester.tap(find.text('Reports'));
    await settle(tester);
  }

  Future<void> open(WidgetTester tester, String title) async {
    await tester.tap(find.text(title));
    await settle(tester);
  }

  setUp(() {
    backend = FakeBackend();
    store = LocalStore.memory();
    tokens = MemoryTokenStore()
      ..access = 'nat_1'
      ..refresh = 'nrt_1'
      ..session = {'user': userJson(), 'business': businessJson};
  });

  test('ranges and labels', () {
    final today = DateTime(2026, 10, 9);
    expect((ReportPreset.last30.range(today).fromYmd, ReportPreset.last30.range(today).toYmd), ('2026-09-10', '2026-10-09'));
    expect((ReportPreset.thisMonth.range(today).fromYmd, ReportPreset.thisMonth.range(today).toYmd), ('2026-10-01', '2026-10-09'));
    expect((ReportPreset.lastMonth.range(today).fromYmd, ReportPreset.lastMonth.range(today).toYmd), ('2026-09-01', '2026-09-30'));
    expect((ReportPreset.last12Months.range(today).fromYmd, ReportPreset.last12Months.range(today).toYmd), ('2025-10-10', '2026-10-09'));
    expect(ReportPreset.lastMonth.range(DateTime(2026, 1, 15)).fromYmd, '2025-12-01');
    expect(hoursLabel(41400), '11.5 h');
    expect(hoursLabel(86400), '24 h');
    expect(signedHours(-3600), '−1 h');
    expect(signedPercent(-4.2), '−4.2%');
    expect(signedPercent(null), '—');
    expect(periodLabel('2026-10-06', 'week'), '6 Oct');
    expect(periodLabel('2026-10-01', 'month'), 'Oct');
  });

  testWidgets('the hub lists the reports; a report shows the server figures for the chosen range', (tester) async {
    await pumpReports(tester);
    for (final k in ReportKind.values) {
      expect(find.text(k.title), findsOneWidget);
    }

    await open(tester, 'Jobs & Deadlines');
    expect(find.text('50%'), findsOneWidget);
    expect(find.text('1.5 days early on average'), findsOneWidget);
    expect(find.text('11.5 days'), findsOneWidget);
    expect(find.text('Orders and completions'), findsOneWidget);
    final now = DateTime.now();
    final range = ReportPreset.last30.range(now);
    expect(backend.adapter.requests.last.uri.queryParameters, {'from': range.fromYmd, 'to': range.toYmd});

    await tester.tap(find.text('7 days'));
    await settle(tester);
    expect(backend.adapter.requests.last.uri.queryParameters['from'], ReportPreset.last7.range(now).fromYmd);
  });

  testWidgets('every report renders its figures', (tester) async {
    await pumpReports(tester);
    final expected = {
      'Hours & Estimates': ['−1 h', '11.5 h', 'Sewing'],
      'Workload & Capacity': ['8.3%', '12 h'],
      'Customers': ['Kofi Mensah', 'Ama Mensah'],
      'Inventory': ['GHS 4,980.50', 'Horsehair Canvas', 'Super 150s Wool'],
      'Tools & Maintenance': ['10 days overdue', 'In 3 days', 'Steam Press'],
    };
    for (final MapEntry(key: title, value: texts) in expected.entries) {
      await open(tester, title);
      for (final text in texts) {
        await tester.scrollUntilVisible(find.text(text).first, 300, scrollable: find.byType(Scrollable).first);
        expect(find.text(text), findsWidgets, reason: '$title shows $text');
      }
      expect(tester.takeException(), isNull);
      await tester.pageBack();
      await settle(tester);
    }
  });

  testWidgets('a report opened before is shown offline with its time; never opened, it says so', (tester) async {
    await pumpReports(tester);
    await open(tester, 'Customers');
    expect(find.text('Kofi Mensah'), findsOneWidget);
    await tester.pageBack();
    await settle(tester);

    backend.adapter.offline = true;
    await open(tester, 'Customers');
    expect(find.textContaining('Offline · figures from'), findsOneWidget);
    expect(find.text('Kofi Mensah'), findsOneWidget);
    await tester.pageBack();
    await settle(tester);

    await open(tester, 'Inventory');
    expect(find.text('GHS 4,980.50'), findsNothing);
    expect(find.text('You are offline'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
  });
}
