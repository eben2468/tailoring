import '../../../core/network/api_client.dart';

/// An owner/admin account as seen by the admin.
class AdminUser {
  const AdminUser({
    required this.id,
    required this.fullName,
    required this.email,
    required this.role,
    required this.isActive,
    required this.isLocked,
    this.phone,
    this.lastLoginAt,
    this.createdAt,
  });

  factory AdminUser.fromJson(Map<String, dynamic> json) => AdminUser(
        id: (json['id'] as num).toInt(),
        fullName: json['full_name'] as String,
        email: json['email'] as String,
        phone: json['phone'] as String?,
        role: json['role'] as String,
        isActive: json['is_active'] as bool? ?? true,
        isLocked: json['is_locked'] as bool? ?? false,
        lastLoginAt: DateTime.tryParse(json['last_login_at'] as String? ?? '')?.toLocal(),
        createdAt: DateTime.tryParse(json['created_at'] as String? ?? '')?.toLocal(),
      );

  final int id;
  final String fullName;
  final String email;
  final String? phone;
  final String role;
  final bool isActive;
  final bool isLocked;
  final DateTime? lastLoginAt;
  final DateTime? createdAt;
}

/// One audit trail entry.
class AuditEntry {
  const AuditEntry({required this.id, required this.action, required this.createdAt, this.userName, this.entityType, this.entityId, this.ipAddress, this.changes});

  factory AuditEntry.fromJson(Map<String, dynamic> json) => AuditEntry(
        id: (json['id'] as num).toInt(),
        action: json['action'] as String,
        userName: json['user_name'] as String?,
        entityType: json['entity_type'] as String?,
        entityId: json['entity_id'] as String?,
        ipAddress: json['ip_address'] as String?,
        changes: json['changes'] is Map<String, dynamic> ? json['changes'] as Map<String, dynamic> : null,
        createdAt: DateTime.parse(json['created_at'] as String).toLocal(),
      );

  final int id;
  final String action;
  final String? userName;
  final String? entityType;
  final String? entityId;
  final String? ipAddress;
  final Map<String, dynamic>? changes;
  final DateTime createdAt;
}

/// /admin/* endpoints (admin role only).
class AdminApi {
  const AdminApi(this._client);

  final ApiClient _client;

  Future<Paged<AdminUser>> users({int page = 1}) => _client.getPaged('/admin/users', AdminUser.fromJson, query: {'page': page, 'per_page': 50});

  Future<AdminUser> user(int id) async => AdminUser.fromJson(await _client.get('/admin/users/$id') as Map<String, dynamic>);

  Future<AdminUser> createUser({required String fullName, required String email, required String role, required String password, String? phone}) async =>
      AdminUser.fromJson(await _client.post('/admin/users', body: {
        'full_name': fullName,
        'email': email,
        'role': role,
        'password': password,
        'phone': phone,
      }) as Map<String, dynamic>);

  Future<AdminUser> updateUser(int id, Map<String, dynamic> changes) async =>
      AdminUser.fromJson(await _client.patch('/admin/users/$id', body: changes) as Map<String, dynamic>);

  Future<void> resetPassword(int id, String password) => _client.post('/admin/users/$id/reset-password', body: {'password': password});

  Future<int> revokeSessions(int id) async =>
      ((await _client.post('/admin/users/$id/revoke-sessions') as Map<String, dynamic>)['sessions_revoked'] as num).toInt();

  Future<Paged<AuditEntry>> auditLog({int page = 1, String? action}) =>
      _client.getPaged('/admin/audit-logs', AuditEntry.fromJson, query: {'page': page, 'per_page': 50, 'action': action});
}
