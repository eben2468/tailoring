@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nutofe/app/app.dart';
import 'package:nutofe/core/local/local_store.dart';
import 'package:nutofe/core/network/api_client.dart';
import 'package:nutofe/core/providers.dart';
import 'package:nutofe/features/calendar/domain/calendar.dart';

import '../support/fake_backend.dart';
import '../support/fakes.dart';

/// Screenshots of the calendar (compare with design/stitch/atelier_calendar_fittings).
///   flutter test --tags golden --update-goldens
Future<void> _loadFonts() async {
  final jakarta = FontLoader('PlusJakartaSans');
  for (final weight in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
    jakarta.addFont(rootBundle.load('assets/fonts/PlusJakartaSans-$weight.ttf'));
  }
  await jakarta.load();
  final noto = FontLoader('NotoSansFallback');
  for (final weight in [400, 500, 600, 700]) {
    noto.addFont(rootBundle.load('assets/fonts/NotoSans-latin-ext-$weight.ttf'));
  }
  await noto.load();
  await (FontLoader('packages/material_symbols_icons/MaterialSymbolsOutlined')
        ..addFont(rootBundle.load('packages/material_symbols_icons/lib/fonts/MaterialSymbolsOutlined.ttf')))
      .load();
}

void main() {
  setUpAll(_loadFonts);

  late FakeBackend backend;
  late MemoryTokenStore tokens;

  Future<void> pumpApp(WidgetTester tester, {double height = 915}) async {
    tester.view.physicalSize = Size(412 * 2, height * 2);
    tester.view.devicePixelRatio = 2;
    tester.view.padding = const FakeViewPadding(top: 24 * 2, bottom: 16 * 2);
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

  setUp(() {
    tokens = MemoryTokenStore()
      ..access = 'nat_1'
      ..refresh = 'nrt_1'
      ..session = {'user': userJson(name: 'Marcus Owusu'), 'business': businessJson};
    backend = FakeBackend();
    final today = dayOf(DateTime.now());
    final kofi = backend.addCustomer('Kofi Mensah', phone: '+233241110001')['id'] as String;
    final ama = backend.addCustomer('Ama Mensah', phone: '+233241110005')['id'] as String;
    final kwame = backend.addCustomer('Kwame Asante')['id'] as String;
    final suit = backend.jobs.addJob(kofi, dueInDays: 4, done: 1);
    final kaftan = backend.jobs.addJob(kwame, jobTypeId: 6, dueInDays: 0, done: 2);
    void plan(Map<String, dynamic> job, int index, int hour, int hours) {
      final task = (job['tasks'] as List)[index] as Map<String, dynamic>;
      backend.apply('PATCH', '/tasks/${task['id']}', {
        'version': backend.server.get(Tables.tasks, task['id'] as String)!['version'],
        'scheduled_start': today.add(Duration(hours: hour, minutes: 30)).toUtc().toIso8601String(),
        'scheduled_end': today.add(Duration(hours: hour + hours, minutes: 30)).toUtc().toIso8601String(),
      });
    }

    plan(suit, 1, 8, 2);
    plan(kaftan, 2, 10, 2);
    backend
      ..addAppointment('Structured blazer fitting', today.add(const Duration(hours: 13, minutes: 30)), customerId: ama, location: 'Fitting Room 1', status: 'confirmed')
      ..addAppointment('Collection — trench overcoat', today.add(const Duration(hours: 15, minutes: 45)), type: 'collection', minutes: 30, customerId: kofi, jobId: suit['id'] as String, location: 'Front counter')
      ..addAppointment('Baste fitting', today.add(const Duration(days: 2, hours: 10)), customerId: kofi);
  });

  testWidgets('calendar week', (tester) async {
    await pumpApp(tester, height: 2000);
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/calendar_week.png'));
  });

  testWidgets('calendar month', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.text('Month'));
    await tester.pumpAndSettle();
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/calendar_month.png'));
  });

  testWidgets('new appointment', (tester) async {
    await pumpApp(tester, height: 1500);
    await tester.tap(find.text('Schedule'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Choose customer'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Kofi Mensah').last);
    await tester.pumpAndSettle();
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/appointment_new.png'));
  });
}
