import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/widgets/app_bottom_nav.dart';
import '../core/widgets/brand_mark.dart';
import '../features/admin/presentation/audit_log_screen.dart';
import '../features/admin/presentation/new_user_screen.dart';
import '../features/admin/presentation/user_detail_screen.dart';
import '../features/admin/presentation/users_screen.dart';
import '../features/ai/presentation/ai_screen.dart';
import '../features/auth/application/session_controller.dart';
import '../features/auth/presentation/login_screen.dart';
import '../features/calendar/presentation/appointment_form_screen.dart';
import '../features/calendar/presentation/appointment_screen.dart';
import '../features/calendar/presentation/calendar_screen.dart';
import '../features/customers/presentation/customer_form_screen.dart';
import '../features/customers/presentation/customer_profile_screen.dart';
import '../features/customers/presentation/customers_screen.dart';
import '../features/dashboard/presentation/dashboard_screen.dart';
import '../features/inventory/presentation/inventory_item_form_screen.dart';
import '../features/inventory/presentation/inventory_item_screen.dart';
import '../features/inventory/presentation/inventory_screen.dart';
import '../features/jobs/presentation/garment_templates_screen.dart';
import '../features/jobs/presentation/job_detail_screen.dart';
import '../features/jobs/presentation/job_form_screen.dart';
import '../features/jobs/presentation/jobs_screen.dart';
import '../features/measurements/presentation/measurement_history_screen.dart';
import '../features/measurements/presentation/record_measurements_screen.dart';
import '../features/settings/presentation/change_password_screen.dart';
import '../features/notifications/presentation/notifications_screen.dart';
import '../features/reports/domain/reports.dart';
import '../features/reports/presentation/reports_screen.dart';
import '../features/settings/presentation/category_settings_screen.dart';
import '../features/settings/presentation/more_screen.dart';
import '../features/settings/presentation/profile_screen.dart';
import '../features/sync/presentation/sync_screen.dart';
import '../features/tools/presentation/tool_form_screen.dart';
import '../features/tools/presentation/tool_screen.dart';
import '../features/tools/presentation/tools_screen.dart';
import '../features/timer/presentation/timer_screen.dart';
import '../features/timer/presentation/timer_widgets.dart';
import '../features/timer/presentation/work_logs_screen.dart';
import 'module_not_ready.dart';
import 'modules.dart';
import 'routes.dart';

final _rootKey = GlobalKey<NavigatorState>(debugLabel: 'root');

/// go_router with an auth gate:
///   restoring → /splash · signed out → /login · signed in → shell with 5 bottom-nav branches.
/// Detail screens are pushed on the root navigator (over the bottom bar, as in the designs).
final routerProvider = Provider<GoRouter>((ref) {
  final refresh = ValueNotifier<int>(0);
  ref
    ..listen(sessionControllerProvider, (_, _) => refresh.value++)
    ..onDispose(refresh.dispose);

  return GoRouter(
    navigatorKey: _rootKey,
    initialLocation: Routes.dashboard,
    refreshListenable: refresh,
    redirect: (context, state) {
      final session = ref.read(sessionControllerProvider);
      final location = state.matchedLocation;
      if (session.isLoading && !session.hasValue) return location == Routes.splash ? null : Routes.splash;

      final signedIn = session.value != null;
      final onAuthPage = location == Routes.login || location == Routes.splash;
      if (!signedIn) return location == Routes.login ? null : Routes.login;
      if (onAuthPage) return Routes.dashboard;
      if (location.startsWith('/admin') && !(session.value?.user.isAdmin ?? false)) return Routes.more;
      return null;
    },
    routes: [
      GoRoute(path: Routes.splash, builder: (_, _) => const _SplashScreen()),
      GoRoute(path: Routes.login, builder: (_, _) => const LoginScreen()),
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => _AppShell(shell: shell),
        branches: [
          _branch(Routes.dashboard, const DashboardScreen()),
          _branch(Routes.jobs, const JobsScreen()),
          _branch(Routes.calendar, const CalendarScreen()),
          _branch(Routes.customers, const CustomersScreen()),
          _branch(Routes.more, const MoreScreen()),
        ],
      ),
      // Customers & measurements (order matters: /customers/new before /customers/:id)
      _pushed(Routes.customerNew, (_) => const CustomerFormScreen()),
      _pushed('/customers/:id', (s) => CustomerProfileScreen(customerId: s.pathParameters['id']!)),
      _pushed('/customers/:id/edit', (s) => CustomerFormScreen(customerId: s.pathParameters['id'])),
      _pushed('/customers/:id/measurements/new', (s) => RecordMeasurementsScreen(customerId: s.pathParameters['id']!)),
      _pushed('/customers/:id/measurements', (s) => MeasurementHistoryScreen(customerId: s.pathParameters['id']!)),
      _pushed('/customers/:id/measurements/:setId', (s) => MeasurementSetScreen(customerId: s.pathParameters['id']!, setId: s.pathParameters['setId']!)),
      // Jobs (order matters: /jobs/new before /jobs/:id)
      _pushed('/jobs/new', (s) => JobFormScreen(customerId: s.uri.queryParameters['customer'])),
      _pushed('/jobs/:id', (s) => JobDetailScreen(jobId: s.pathParameters['id']!)),
      _pushed('/jobs/:id/edit', (s) => JobFormScreen(jobId: s.pathParameters['id'])),
      _pushed('/jobs/:id/tasks/:taskId/timer', (s) => TimerScreen(jobId: s.pathParameters['id']!, taskId: s.pathParameters['taskId']!)),
      _pushed('/jobs/:id/tasks/:taskId/logs', (s) => WorkLogsScreen(jobId: s.pathParameters['id']!, taskId: s.pathParameters['taskId']!)),
      // Appointments (order matters: /appointments/new before /appointments/:id)
      _pushed('/appointments/new', (s) => AppointmentFormScreen(
            date: DateTime.tryParse(s.uri.queryParameters['date'] ?? ''),
            customerId: s.uri.queryParameters['customer'],
            jobId: s.uri.queryParameters['job'],
            type: s.uri.queryParameters['type'],
          )),
      _pushed('/appointments/:id', (s) => AppointmentScreen(appointmentId: s.pathParameters['id']!)),
      _pushed('/appointments/:id/edit', (s) => AppointmentFormScreen(appointmentId: s.pathParameters['id'])),
      // Inventory (order matters: /inventory/new before /inventory/:id)
      _pushed(Routes.inventory, (_) => const InventoryScreen()),
      _pushed(Routes.inventoryNew, (_) => const InventoryItemFormScreen()),
      _pushed('/inventory/:id', (s) => InventoryItemScreen(itemId: s.pathParameters['id']!)),
      _pushed('/inventory/:id/edit', (s) => InventoryItemFormScreen(itemId: s.pathParameters['id'])),
      _pushed(Routes.inventoryCategories, (_) => const CategorySettingsScreen(kind: CategoryKind.materials)),
      // Tools (order matters: /tools/new before /tools/:id)
      _pushed(Routes.tools, (_) => const ToolsScreen()),
      _pushed(Routes.toolNew, (_) => const ToolFormScreen()),
      _pushed('/tools/:id', (s) => ToolScreen(toolId: s.pathParameters['id']!)),
      _pushed('/tools/:id/edit', (s) => ToolFormScreen(toolId: s.pathParameters['id'])),
      _pushed(Routes.toolCategories, (_) => const CategorySettingsScreen(kind: CategoryKind.tools)),
      _pushed(Routes.ai, (_) => const AiScreen()),
      _pushed(Routes.reports, (_) => const ReportsScreen()),
      _pushed('/reports/:key', (s) {
        final kind = ReportKind.byKey(s.pathParameters['key']!);
        return kind == null ? const ReportsScreen() : ReportScreen(kind: kind);
      }),
      _pushed(Routes.garmentTypes, (_) => const GarmentTypesScreen()),
      _pushed('/settings/garments/:id', (s) => GarmentTemplateScreen(jobTypeId: int.parse(s.pathParameters['id']!))),
      _pushed(Routes.sync, (_) => const SyncScreen()),
      _pushed(Routes.profile, (_) => const ProfileScreen()),
      _pushed(Routes.changePassword, (_) => const ChangePasswordScreen()),
      _pushed(Routes.notifications, (_) => const NotificationsScreen()),
      _pushed(Routes.adminUsers, (_) => const UsersScreen()),
      _pushed(Routes.adminUserNew, (_) => const NewUserScreen()),
      _pushed('/admin/users/:id', (state) => UserDetailScreen(userId: int.parse(state.pathParameters['id']!))),
      _pushed(Routes.auditLog, (_) => const AuditLogScreen()),
      _pushed('/module/:key', (state) {
        final module = AppModule.byKey(state.pathParameters['key']!) ?? AppModule.dashboard;
        return ModuleNotReadyScreen(module: module);
      }),
    ],
  );
});

StatefulShellBranch _branch(String path, Widget screen) => StatefulShellBranch(routes: [GoRoute(path: path, builder: (_, _) => screen)]);

GoRoute _pushed(String path, Widget Function(GoRouterState) build) => GoRoute(
      path: path,
      parentNavigatorKey: _rootKey,
      builder: (_, state) => build(state),
    );

/// Bottom-nav shell; tapping the active tab returns it to its first screen.
class _AppShell extends StatelessWidget {
  const _AppShell({required this.shell});

  final StatefulNavigationShell shell;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBody: true,
      body: shell,
      // The running-timer strip sits on the dock; extendBody adds both heights to the body's bottom padding.
      bottomNavigationBar: Column(mainAxisSize: MainAxisSize.min, children: [
        const SyncBanner(),
        const TimerBar(),
        AppBottomNav(
          currentIndex: shell.currentIndex,
          onSelected: (i) => shell.goBranch(i, initialLocation: i == shell.currentIndex),
        ),
      ]),
    );
  }
}

class _SplashScreen extends StatelessWidget {
  const _SplashScreen();

  @override
  Widget build(BuildContext context) => const Scaffold(body: Center(child: BrandMark(size: 56)));
}
