@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nutofe/app/app.dart';
import 'package:nutofe/core/network/api_client.dart';
import 'package:nutofe/core/providers.dart';

import '../support/fakes.dart';

/// Renders screens with the real fonts and icons to PNGs (test/visual/goldens/) so they can be
/// compared side by side with the Stitch screenshots in design/stitch/.
///
///   flutter test --tags golden --update-goldens   # regenerate screenshots
///
/// Excluded from the normal run (font rasterisation differs between operating systems).
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

  late MemoryTokenStore tokens;
  late FakeAdapter adapter;

  Future<void> pumpApp(WidgetTester tester, {bool signedIn = true, String role = 'admin'}) async {
    tester.view.physicalSize = const Size(412 * 2, 915 * 2);
    tester.view.devicePixelRatio = 2;
    tester.view.padding = const FakeViewPadding(top: 24 * 2, bottom: 16 * 2);
    addTearDown(tester.view.reset);
    if (signedIn) {
      tokens
        ..access = 'nat_1'
        ..refresh = 'nrt_1'
        ..session = {'user': userJson(role: role, name: 'Marcus Owusu'), 'business': businessJson};
    }
    await tester.pumpWidget(ProviderScope(
      retry: (_, _) => null,
      overrides: [
        tokenStoreProvider.overrideWithValue(tokens),
        apiClientProvider.overrideWith((ref) => ApiClient(baseUrl: 'http://api.test/api/v1', tokens: tokens, adapter: adapter)),
      ],
      child: const NutofeApp(),
    ));
    await tester.pumpAndSettle();
  }

  Future<void> shoot(WidgetTester tester, String name) async {
    await tester.pumpAndSettle();
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/$name.png'));
  }

  setUp(() {
    tokens = MemoryTokenStore();
    adapter = FakeAdapter((request) {
      final path = request.path;
      if (path.endsWith('/auth/me')) return FakeReply.ok({'user': userJson(role: 'admin', name: 'Marcus Owusu'), 'business': businessJson});
      if (path.endsWith('/admin/users')) {
        return FakeReply.ok([
          {...userJson(role: 'admin', name: 'Marcus Owusu'), 'is_active': true, 'is_locked': false, 'last_login_at': DateTime.now().toUtc().toIso8601String(), 'created_at': '2026-10-01T09:00:00.000Z'},
          {...userJson(name: 'Ama Mensah'), 'id': 2, 'email': 'ama@nutofe.test', 'is_active': true, 'is_locked': true, 'last_login_at': '2026-10-06T09:00:00.000Z', 'created_at': '2026-10-01T09:00:00.000Z'},
          {...userJson(name: 'Kojo Asante'), 'id': 3, 'email': 'kojo@nutofe.test', 'is_active': false, 'is_locked': false, 'last_login_at': null, 'created_at': '2026-10-02T09:00:00.000Z'},
        ], meta: {'pagination': {'page': 1, 'per_page': 50, 'total': 3, 'total_pages': 1}});
      }
      if (path.endsWith('/admin/audit-logs')) {
        final now = DateTime.now().toUtc();
        return FakeReply.ok([
          {'id': 3, 'action': 'auth.login', 'user_name': 'Marcus Owusu', 'entity_type': 'user', 'entity_id': '1', 'ip_address': '172.18.0.1', 'created_at': now.subtract(const Duration(minutes: 3)).toIso8601String()},
          {'id': 2, 'action': 'auth.login_failed', 'user_name': 'Ama Mensah', 'entity_type': 'user', 'entity_id': '2', 'ip_address': '102.176.4.9', 'created_at': now.subtract(const Duration(hours: 2)).toIso8601String()},
          {'id': 1, 'action': 'admin.password_reset', 'user_name': 'Marcus Owusu', 'entity_type': 'user', 'entity_id': '2', 'ip_address': '172.18.0.1', 'created_at': now.subtract(const Duration(days: 1)).toIso8601String()},
        ], meta: {'pagination': {'page': 1, 'per_page': 50, 'total': 3, 'total_pages': 1}});
      }
      return FakeReply.ok(null);
    });
  });

  testWidgets('login', (tester) async {
    await pumpApp(tester, signedIn: false);
    await shoot(tester, 'login');
  });

  testWidgets('login with error', (tester) async {
    adapter.handler = (_) => FakeReply.error(401, 'INVALID_CREDENTIALS', 'Incorrect email or password.');
    await pumpApp(tester, signedIn: false);
    await tester.enterText(find.byType(TextFormField).at(0), 'owner@nutofe.test');
    await tester.enterText(find.byType(TextFormField).at(1), 'wrong');
    await tester.tap(find.text('Sign In'));
    await shoot(tester, 'login_error');
  });

  testWidgets('dashboard tab (module not built yet)', (tester) async {
    await pumpApp(tester);
    await shoot(tester, 'dashboard_pending');
  });

  testWidgets('more', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.text('More'));
    await shoot(tester, 'more');
  });

  testWidgets('profile', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.text('More'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Marcus Owusu'));
    await shoot(tester, 'profile');
  });

  testWidgets('users', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.text('More'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Sign out'), 300);
    await tester.tap(find.text('Users'));
    await shoot(tester, 'users');
  });

  testWidgets('new user', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.text('More'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Sign out'), 300);
    await tester.tap(find.text('Users'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add'));
    await shoot(tester, 'new_user');
  });

  testWidgets('audit log', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.text('More'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Sign out'), 300);
    await tester.tap(find.text('Audit log'));
    await shoot(tester, 'audit_log');
  });
}
