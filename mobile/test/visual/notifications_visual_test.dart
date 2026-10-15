@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nutofe/app/app.dart';
import 'package:nutofe/core/network/api_client.dart';
import 'package:nutofe/core/providers.dart';

import '../support/fake_backend.dart';
import '../support/fakes.dart';

/// Screenshot of the notification centre (not designed in Stitch: checked against the design system).
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

  testWidgets('notifications', (tester) async {
    final backend = FakeBackend()
      ..addNotification('Low stock: Silk Basting Thread', body: '3 spools left (minimum 10 spools).', route: '/inventory/x')
      ..addNotification('Due today: #027 Linen Kaftan Set', type: 'job_due_today', body: 'Kwame Asante · still in production.', minutesAgo: 40)
      ..addNotification('Baste fitting at 10:00', type: 'appointment_reminder', severity: 'info', body: 'Kofi Mensah · Fitting Room 1 · Today', minutesAgo: 90)
      ..addNotification('Overdue: #022 Dinner Jacket', type: 'job_overdue', severity: 'critical', body: 'Yaw Boateng · due 2 days ago.', minutesAgo: 60 * 30, read: true)
      ..addNotification('Service due: Lockstitch Machine #02', type: 'maintenance_due', body: 'Due in 3 days.', minutesAgo: 60 * 50, read: true);
    final tokens = MemoryTokenStore()
      ..access = 'nat_1'
      ..refresh = 'nrt_1'
      ..session = {'user': userJson(name: 'Marcus Owusu'), 'business': businessJson};
    tester.view.physicalSize = const Size(412 * 2, 1100 * 2);
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
    await tester.tap(find.byTooltip('Notifications').first);
    await tester.pumpAndSettle();
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/notifications.png'));
  });
}
