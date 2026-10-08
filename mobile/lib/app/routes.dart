/// Route paths (one place, so links never drift).
abstract final class Routes {
  static const splash = '/splash';
  static const login = '/login';

  // Bottom-nav sections
  static const dashboard = '/dashboard';
  static const jobs = '/jobs';
  static const calendar = '/calendar';
  static const customers = '/customers';
  static const more = '/more';

  // Pushed over the shell
  static const customerNew = '/customers/new';
  static String customer(String id) => '/customers/$id';
  static String customerEdit(String id) => '/customers/$id/edit';
  static String recordMeasurements(String customerId) => '/customers/$customerId/measurements/new';
  static String measurementHistory(String customerId) => '/customers/$customerId/measurements';
  static String measurementSet(String customerId, String setId) => '/customers/$customerId/measurements/$setId';

  // Jobs (/jobs/new before /jobs/:id)
  static String jobNew({String? customerId}) => customerId == null ? '/jobs/new' : '/jobs/new?customer=$customerId';
  static String job(String id) => '/jobs/$id';
  static String jobEdit(String id) => '/jobs/$id/edit';
  static String taskTimer(String jobId, String taskId) => '/jobs/$jobId/tasks/$taskId/timer';
  static String taskLogs(String jobId, String taskId) => '/jobs/$jobId/tasks/$taskId/logs';

  // Production configuration (settings)
  static const garmentTypes = '/settings/garments';
  static String garmentType(int id) => '/settings/garments/$id';

  static const notifications = '/notifications';
  static const profile = '/profile';
  static const changePassword = '/profile/password';
  static const adminUsers = '/admin/users';
  static const adminUserNew = '/admin/users/new';
  static String adminUser(int id) => '/admin/users/$id';
  static const auditLog = '/admin/audit-log';

  /// A module whose backend is not built yet (inventory, tools, reports, AI).
  static String module(String key) => '/module/$key';
}
