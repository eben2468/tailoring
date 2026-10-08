import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:uuid/uuid.dart';

/// Session secrets and identity, kept only in the platform keystore
/// (Android Keystore-backed encryption / iOS Keychain). Never in shared preferences or logs.
abstract interface class TokenStore {
  Future<String?> accessToken();
  Future<String?> refreshToken();
  Future<void> saveTokens({required String access, required String refresh});

  /// Last known profile + business settings (JSON), so the app opens offline.
  Future<Map<String, dynamic>?> cachedSession();
  Future<void> saveCachedSession(Map<String, dynamic> json);

  /// Stable per-installation UUIDv7 — the device identity for offline sync.
  Future<String> deviceId();

  /// Removes tokens and the cached session (keeps the device id).
  Future<void> clearSession();
}

class SecureTokenStore implements TokenStore {
  SecureTokenStore([FlutterSecureStorage? storage]) : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  static const _access = 'access_token';
  static const _refresh = 'refresh_token';
  static const _session = 'cached_session';
  static const _device = 'device_id';

  // Access token is read on every request: keep it in memory after the first read.
  String? _accessCache;
  bool _accessLoaded = false;

  @override
  Future<String?> accessToken() async {
    if (!_accessLoaded) {
      _accessCache = await _storage.read(key: _access);
      _accessLoaded = true;
    }
    return _accessCache;
  }

  @override
  Future<String?> refreshToken() => _storage.read(key: _refresh);

  @override
  Future<void> saveTokens({required String access, required String refresh}) async {
    _accessCache = access;
    _accessLoaded = true;
    await _storage.write(key: _access, value: access);
    await _storage.write(key: _refresh, value: refresh);
  }

  @override
  Future<Map<String, dynamic>?> cachedSession() async {
    final raw = await _storage.read(key: _session);
    if (raw == null) return null;
    try {
      return jsonDecode(raw) as Map<String, dynamic>;
    } on FormatException {
      return null;
    }
  }

  @override
  Future<void> saveCachedSession(Map<String, dynamic> json) => _storage.write(key: _session, value: jsonEncode(json));

  @override
  Future<String> deviceId() async {
    final existing = await _storage.read(key: _device);
    if (existing != null) return existing;
    final id = const Uuid().v7();
    await _storage.write(key: _device, value: id);
    return id;
  }

  @override
  Future<void> clearSession() async {
    _accessCache = null;
    _accessLoaded = true;
    await _storage.delete(key: _access);
    await _storage.delete(key: _refresh);
    await _storage.delete(key: _session);
  }
}
