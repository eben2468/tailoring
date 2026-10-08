import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:nutofe/core/network/token_store.dart';

/// A canned HTTP response.
class FakeReply {
  const FakeReply(this.status, this.body, {this.headers = const {}});

  final int status;
  final Object? body;
  final Map<String, String> headers;

  static FakeReply ok(Object? data, {String message = 'OK', Map<String, dynamic>? meta}) =>
      FakeReply(200, {'success': true, 'message': message, 'data': data, 'meta': ?meta});

  static FakeReply error(int status, String code, String message, {Map<String, List<String>> errors = const {}, Map<String, String> headers = const {}}) =>
      FakeReply(status, {'success': false, 'message': message, 'code': code, 'errors': errors, 'request_id': 'req-test'}, headers: headers);
}

/// Dio adapter that answers from a handler and records every request.
class FakeAdapter implements HttpClientAdapter {
  FakeAdapter(this.handler);

  FutureOr<FakeReply> Function(RequestOptions request) handler;
  final List<RequestOptions> requests = [];

  /// Throw a transport error instead of answering (simulates no connection).
  bool offline = false;

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    requests.add(options);
    if (offline) {
      throw DioException.connectionError(requestOptions: options, reason: 'offline');
    }
    final reply = await handler(options);
    return ResponseBody.fromString(
      jsonEncode(reply.body),
      reply.status,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
        for (final h in reply.headers.entries) h.key: [h.value],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}


/// In-memory replacement for the keystore-backed token store.
class MemoryTokenStore implements TokenStore {
  String? access;
  String? refresh;
  Map<String, dynamic>? session;
  String device = '0192f0a1-0000-7000-8000-000000000001';

  @override
  Future<String?> accessToken() async => access;

  @override
  Future<String?> refreshToken() async => refresh;

  @override
  Future<void> saveTokens({required String access, required String refresh}) async {
    this.access = access;
    this.refresh = refresh;
  }

  @override
  Future<Map<String, dynamic>?> cachedSession() async => session;

  @override
  Future<void> saveCachedSession(Map<String, dynamic> json) async => session = jsonDecode(jsonEncode(json)) as Map<String, dynamic>;

  @override
  Future<String> deviceId() async => device;

  @override
  Future<void> clearSession() async {
    access = null;
    refresh = null;
    session = null;
  }
}

/// Sample API payloads.
Map<String, dynamic> userJson({String role = 'owner', String name = 'Marcus Owner'}) => {
      'id': 1,
      'full_name': name,
      'email': 'owner@nutofe.test',
      'phone': null,
      'role': role,
      'permissions': role == 'admin' ? ['business', 'admin.users', 'admin.audit', 'admin.system'] : ['business'],
    };

const businessJson = {
  'name': 'Nutɔfe',
  'timezone': 'Africa/Accra',
  'currency': 'GHS',
  'currency_symbol': 'GH₵',
  'phone_region': 'GH',
  'default_measurement_unit': 'in',
};

Map<String, dynamic> loginJson({String role = 'owner', String access = 'nat_1', String refresh = 'nrt_1'}) => {
      'token_type': 'Bearer',
      'access_token': access,
      'access_token_expires_at': '2026-10-08T10:00:00.000Z',
      'refresh_token': refresh,
      'refresh_token_expires_at': '2026-11-07T10:00:00.000Z',
      'user': userJson(role: role),
      'business': businessJson,
    };
