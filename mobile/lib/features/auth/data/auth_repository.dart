import 'package:flutter/foundation.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/network/token_store.dart';
import '../domain/session.dart';
import 'auth_api.dart';

/// Owns the session lifecycle: sign-in, offline restore, profile refresh and sign-out.
class AuthRepository {
  AuthRepository(this._api, this._tokens);

  final AuthApi _api;
  final TokenStore _tokens;

  Future<Session> signIn(String email, String password) async {
    final data = await _api.login(
      email: email.trim().toLowerCase(),
      password: password,
      deviceId: await _tokens.deviceId(),
      platform: defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android',
    );
    await _tokens.saveTokens(access: data['access_token'] as String, refresh: data['refresh_token'] as String);
    return _store(data);
  }

  /// The last signed-in session from secure storage (works offline), or null.
  Future<Session?> restore() async {
    if (await _tokens.refreshToken() == null) return null;
    final cached = await _tokens.cachedSession();
    return cached == null ? null : Session.fromJson(cached);
  }

  /// Re-reads the profile/settings from the server and updates the cache.
  Future<Session> refreshProfile() async => _store(await _api.me());

  Future<Session> updateProfile({required String fullName, String? phone}) async {
    final data = await _api.updateProfile(fullName: fullName, phone: phone);
    final cached = await _tokens.cachedSession();
    final user = AppUser.fromJson(data['user'] as Map<String, dynamic>);
    final session = cached == null
        ? Session(user: user, business: BusinessSettings.fromJson(const {}))
        : Session.fromJson(cached).copyWith(user: user);
    await _tokens.saveCachedSession(session.toJson());
    return session;
  }

  Future<void> changePassword(String current, String next) => _api.changePassword(current: current, next: next);

  /// Revokes the session on the server when reachable; always clears local secrets.
  Future<void> signOut() async {
    try {
      await _api.logout();
    } on ApiException {
      // Offline or already revoked: the local session is cleared regardless.
    }
    await _tokens.clearSession();
  }

  Future<int> signOutEverywhere() async {
    final count = await _api.logoutAll();
    await _tokens.clearSession();
    return count;
  }

  Future<void> clearLocal() => _tokens.clearSession();

  Future<Session> _store(Map<String, dynamic> data) async {
    final session = Session(
      user: AppUser.fromJson(data['user'] as Map<String, dynamic>),
      business: BusinessSettings.fromJson(data['business'] as Map<String, dynamic>),
    );
    await _tokens.saveCachedSession(session.toJson());
    return session;
  }
}
