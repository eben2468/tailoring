import '../../../core/network/api_client.dart';

/// /auth/* endpoints (see docs/API_REFERENCE.md §3).
class AuthApi {
  const AuthApi(this._client);

  final ApiClient _client;

  /// Returns token pair + user + business settings.
  Future<Map<String, dynamic>> login({
    required String email,
    required String password,
    required String deviceId,
    required String platform,
  }) async =>
      await _client.postPublic('/auth/login', body: {
        'email': email,
        'password': password,
        'device_id': deviceId,
        'platform': platform,
      }) as Map<String, dynamic>;

  Future<Map<String, dynamic>> me() async => await _client.get('/auth/me') as Map<String, dynamic>;

  Future<Map<String, dynamic>> updateProfile({required String fullName, String? phone}) async =>
      await _client.patch('/auth/me', body: {'full_name': fullName, 'phone': phone}) as Map<String, dynamic>;

  Future<void> changePassword({required String current, required String next}) =>
      _client.post('/auth/change-password', body: {'current_password': current, 'new_password': next});

  Future<void> logout() => _client.post('/auth/logout');

  Future<int> logoutAll() async {
    final data = await _client.post('/auth/logout-all') as Map<String, dynamic>;
    return (data['sessions_revoked'] as num?)?.toInt() ?? 0;
  }
}
