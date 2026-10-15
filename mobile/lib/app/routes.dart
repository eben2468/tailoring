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

  // Appointments (/appointments/new before /appointments/:id)
  static String appointmentNew({DateTime? date, String? customerId, String? jobId, String? type}) {
    final query = {
      if (date != null) 'date': '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}',
      'customer': ?customerId,
      'job': ?jobId,
      'type': ?type,
    };
    return Uri(path: '/appointments/new', queryParameters: query.isEmpty ? null : query).toString();
  }

  static String appointment(String id) => '/appointments/$id';
  static String appointmentEdit(String id) => '/appointments/$id/edit';

  // Inventory (/inventory/new before /inventory/:id)
  static const inventory = '/inventory';
  static const inventoryNew = '/inventory/new';
  static String inventoryItem(String id) => '/inventory/$id';
  static String inventoryEdit(String id) => '/inventory/$id/edit';
  static const inventoryCategories = '/settings/inventory-categories';

  // Tools (/tools/new before /tools/:id)
  static const tools = '/tools';
  static const toolNew = '/tools/new';
  static String tool(String id) => '/tools/$id';
  static String toolEdit(String id) => '/tools/$id/edit';
  static const toolCategories = '/settings/tool-categories';

  static const ai = '/ai';

  // Reports
  static const reports = '/reports';
  static String report(String key) => '/reports/$key';

  // Production configuration (settings)
  static const garmentTypes = '/settings/garments';
  static String garmentType(int id) => '/settings/garments/$id';

  static const sync = '/sync';
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
