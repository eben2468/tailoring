import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nutofe/core/network/api_exception.dart';
import 'package:nutofe/core/theme/app_colors.dart';
import 'package:nutofe/core/theme/app_text.dart';
import 'package:nutofe/core/theme/app_theme.dart';
import 'package:nutofe/core/utils/formatters.dart';
import 'package:nutofe/core/widgets/app_bottom_nav.dart';
import 'package:nutofe/core/widgets/app_button.dart';
import 'package:nutofe/core/widgets/initials_avatar.dart';
import 'package:nutofe/core/widgets/state_views.dart';
import 'package:nutofe/core/widgets/status_pill.dart';

Widget _wrap(Widget child) => MaterialApp(theme: AppTheme.light(), home: Scaffold(body: Center(child: child)));

void main() {
  test('type scale matches the Stitch config', () {
    expect(AppText.headlineLg.fontSize, 22);
    expect(AppText.headlineLg.fontWeight, FontWeight.w600);
    expect(AppText.metricNum.fontSize, 20);
    expect(AppText.metricNum.fontFeatures, contains(const FontFeature.tabularFigures()));
    expect(AppText.labelSm.letterSpacing, closeTo(0.44, 0.001)); // 11px × 0.04em
    expect(AppText.titleSm.fontFamily, 'PlusJakartaSans');
  });

  test('initials', () {
    expect(InitialsAvatar.initialsOf('Kofi Mensah'), 'KM');
    expect(InitialsAvatar.initialsOf('  ama  '), 'A');
    expect(InitialsAvatar.initialsOf('Kwame Asante Boateng'), 'KB');
    expect(InitialsAvatar.initialsOf(''), '?');
  });

  test('relative time', () {
    final now = DateTime(2026, 10, 8, 15, 0);
    expect(Fmt.relative(now.subtract(const Duration(seconds: 20)), now: now), 'Just now');
    expect(Fmt.relative(now.subtract(const Duration(minutes: 5)), now: now), '5 min ago');
    expect(Fmt.relative(DateTime(2026, 10, 8, 9, 5), now: now), 'Today 09:05');
    expect(Fmt.relative(DateTime(2026, 10, 7, 9, 5), now: now), 'Yesterday 09:05');
    expect(Fmt.auditAction('auth.login_failed'), 'Login failed');
  });

  testWidgets('primary button uses midnight navy and 48px height', (tester) async {
    await tester.pumpWidget(_wrap(AppButton(label: 'Start Timer', onPressed: () {})));
    final size = tester.getSize(find.byType(AppButton));
    expect(size.height, 48);
    final button = tester.widget<TextButton>(find.byType(TextButton));
    expect(button.style!.backgroundColor!.resolve({}), AppColors.primaryContainer);
  });

  testWidgets('loading button is disabled and shows progress', (tester) async {
    var taps = 0;
    await tester.pumpWidget(_wrap(AppButton(label: 'Save', loading: true, onPressed: () => taps++)));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.tap(find.byType(AppButton));
    expect(taps, 0);
  });

  testWidgets('status pill pairs saturated text with soft background', (tester) async {
    await tester.pumpWidget(_wrap(const StatusPill(label: 'High Priority', tone: StatusTone.danger)));
    final text = tester.widget<Text>(find.text('High Priority'));
    expect(text.style!.color, AppColors.onErrorContainer);
  });

  testWidgets('bottom nav shows the five Stitch destinations and reports taps', (tester) async {
    var selected = -1;
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(bottomNavigationBar: AppBottomNav(currentIndex: 0, onSelected: (i) => selected = i)),
    ));
    for (final label in ['Dashboard', 'Jobs', 'Calendar', 'Customers', 'More']) {
      expect(find.text(label), findsOneWidget);
    }
    await tester.tap(find.text('Customers'));
    expect(selected, 3);
  });

  testWidgets('error view picks copy by exception type and shows the reference', (tester) async {
    await tester.pumpWidget(_wrap(const ErrorView(error: NetworkException())));
    expect(find.text('You are offline'), findsOneWidget);

    await tester.pumpWidget(_wrap(ErrorView(error: const ServerException('Something went wrong on our side. Please try again.', 'INTERNAL_ERROR', 'abc123'), onRetry: () {})));
    expect(find.text('Something went wrong'), findsOneWidget);
    expect(find.text('Reference: abc123'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
  });
}
