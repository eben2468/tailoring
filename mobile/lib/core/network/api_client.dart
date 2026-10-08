import 'dart:async';

import 'package:dio/dio.dart';

import 'api_exception.dart';
import 'token_store.dart';

/// Result of a list endpoint: items + pagination meta.
class Paged<T> {
  const Paged({required this.items, required this.page, required this.perPage, required this.total, required this.totalPages});

  final List<T> items;
  final int page;
  final int perPage;
  final int total;
  final int totalPages;

  bool get hasMore => page < totalPages;
}

/// Thin wrapper around Dio for the Nutɔfe API envelope:
///   success: {"success": true, "message", "data", "meta"?}
///   error:   {"success": false, "message", "code", "errors", "request_id"}
///
/// - Attaches the bearer access token.
/// - On 401 TOKEN_EXPIRED: refreshes once (serialised — the server rotates refresh tokens and
///   treats parallel reuse as a race) and retries the original request.
/// - Converts every failure into a typed [ApiException].
class ApiClient {
  ApiClient({required String baseUrl, required this._tokens, Dio? dio, HttpClientAdapter? adapter})
      : _dio = dio ?? Dio(_options(baseUrl)),
        _refreshDio = Dio(_options(baseUrl)) {
    if (adapter != null) {
      _dio.httpClientAdapter = adapter;
      _refreshDio.httpClientAdapter = adapter;
    }
    _dio.interceptors.add(QueuedInterceptorsWrapper(onRequest: _attachToken, onError: _refreshOnExpiry));
  }

  final Dio _dio;
  final Dio _refreshDio;
  final TokenStore _tokens;
  Future<bool>? _refreshing;

  /// Called when the session can no longer be renewed (refresh failed) — the app signs out.
  void Function()? onSessionExpired;

  static BaseOptions _options(String baseUrl) => BaseOptions(
        baseUrl: baseUrl,
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 20),
        sendTimeout: const Duration(seconds: 20),
        headers: {'Accept': 'application/json'},
        contentType: Headers.jsonContentType,
        responseType: ResponseType.json,
      );

  Future<dynamic> get(String path, {Map<String, dynamic>? query}) => _send(() => _dio.get<dynamic>(path, queryParameters: _clean(query)));

  Future<dynamic> post(String path, {Object? body}) => _send(() => _dio.post<dynamic>(path, data: body ?? const <String, dynamic>{}));

  Future<dynamic> patch(String path, {Object? body}) => _send(() => _dio.patch<dynamic>(path, data: body ?? const <String, dynamic>{}));

  Future<dynamic> put(String path, {Object? body}) => _send(() => _dio.put<dynamic>(path, data: body ?? const <String, dynamic>{}));

  Future<dynamic> delete(String path) => _send(() => _dio.delete<dynamic>(path));

  /// GET a paginated list and map each item.
  Future<Paged<T>> getPaged<T>(String path, T Function(Map<String, dynamic>) fromJson, {Map<String, dynamic>? query}) async {
    final envelope = await _sendEnvelope(() => _dio.get<dynamic>(path, queryParameters: _clean(query)));
    final items = (envelope['data'] as List<dynamic>? ?? const []).cast<Map<String, dynamic>>().map(fromJson).toList();
    final pagination = ((envelope['meta'] as Map<String, dynamic>?)?['pagination'] as Map<String, dynamic>?) ?? const {};
    return Paged(
      items: items,
      page: (pagination['page'] as num?)?.toInt() ?? 1,
      perPage: (pagination['per_page'] as num?)?.toInt() ?? items.length,
      total: (pagination['total'] as num?)?.toInt() ?? items.length,
      totalPages: (pagination['total_pages'] as num?)?.toInt() ?? 1,
    );
  }

  /// Unauthenticated call used by sign-in/refresh (never triggers the refresh flow).
  Future<dynamic> postPublic(String path, {required Object body}) => _send(() => _refreshDio.post<dynamic>(path, data: body));

  Future<dynamic> _send(Future<Response<dynamic>> Function() request) async => (await _sendEnvelope(request))['data'];

  Future<Map<String, dynamic>> _sendEnvelope(Future<Response<dynamic>> Function() request) async {
    try {
      final response = await request();
      final body = response.data;
      if (body is Map<String, dynamic> && body['success'] == true) {
        return body;
      }
      throw const ServerException('The server sent an unexpected response.');
    } on DioException catch (e) {
      throw mapDioException(e);
    }
  }

  static Map<String, dynamic>? _clean(Map<String, dynamic>? query) => query == null ? null : (Map.of(query)..removeWhere((_, v) => v == null || v == ''));

  // ---------------------------------------------------------------------------
  // Token handling

  Future<void> _attachToken(RequestOptions options, RequestInterceptorHandler handler) async {
    final access = await _tokens.accessToken();
    if (access != null) {
      options.headers['Authorization'] = 'Bearer $access';
    }
    handler.next(options);
  }

  Future<void> _refreshOnExpiry(DioException error, ErrorInterceptorHandler handler) async {
    final response = error.response;
    final code = response?.data is Map ? (response!.data as Map)['code'] : null;
    final alreadyRetried = error.requestOptions.extra['retried'] == true;

    if (response?.statusCode != 401 || code != 'TOKEN_EXPIRED' || alreadyRetried) {
      handler.next(error);
      return;
    }

    // Another queued request may already have refreshed while this one waited.
    final usedToken = (error.requestOptions.headers['Authorization'] as String?)?.replaceFirst('Bearer ', '');
    final current = await _tokens.accessToken();
    final refreshed = (current != null && current != usedToken) || await _refreshOnce();

    if (!refreshed) {
      onSessionExpired?.call();
      handler.next(error);
      return;
    }

    try {
      final retry = error.requestOptions
        ..extra['retried'] = true
        ..headers['Authorization'] = 'Bearer ${await _tokens.accessToken()}';
      handler.resolve(await _dio.fetch<dynamic>(retry));
    } on DioException catch (e) {
      handler.next(e);
    }
  }

  /// Exchanges the refresh token; concurrent callers share one in-flight refresh.
  Future<bool> _refreshOnce() => _refreshing ??= _doRefresh().whenComplete(() => _refreshing = null);

  Future<bool> _doRefresh() async {
    final refresh = await _tokens.refreshToken();
    if (refresh == null) return false;
    try {
      final response = await _refreshDio.post<dynamic>('/auth/refresh', data: {'refresh_token': refresh});
      final data = (response.data as Map<String, dynamic>)['data'] as Map<String, dynamic>;
      await _tokens.saveTokens(access: data['access_token'] as String, refresh: data['refresh_token'] as String);
      return true;
    } on DioException {
      return false;
    }
  }
}

/// Maps transport + HTTP failures to [ApiException]s (public for tests).
ApiException mapDioException(DioException e) {
  switch (e.type) {
    case DioExceptionType.connectionTimeout:
    case DioExceptionType.sendTimeout:
    case DioExceptionType.receiveTimeout:
      return const TimeoutApiException();
    case DioExceptionType.connectionError:
      return const NetworkException();
    case DioExceptionType.unknown when e.response == null:
      return const NetworkException();
    default:
      break;
  }

  final response = e.response;
  if (response == null) return const ServerException();

  final body = response.data is Map<String, dynamic> ? response.data as Map<String, dynamic> : const <String, dynamic>{};
  final status = response.statusCode ?? 0;
  final message = body['message'] is String ? body['message'] as String : _fallbackMessage(status);
  final code = body['code'] as String?;
  final requestId = body['request_id'] as String?;

  return switch (status) {
    401 => UnauthorizedException(message, code: code, requestId: requestId),
    403 => ForbiddenException(message, code: code, requestId: requestId),
    404 => NotFoundException(message, code: code, requestId: requestId),
    409 => ConflictException(message, code: code, requestId: requestId),
    422 => ValidationException(message, _fieldErrors(body['errors']), code: code, requestId: requestId),
    429 => RateLimitedException(message, retryAfter: _retryAfter(response.headers.value('retry-after')), code: code, requestId: requestId),
    >= 500 => ServerException(status == 503 ? message : 'Something went wrong on our side. Please try again.', code, requestId),
    _ => ServerException(message, code, requestId),
  };
}

Map<String, List<String>> _fieldErrors(Object? errors) {
  if (errors is! Map) return const {};
  return {
    for (final entry in errors.entries)
      entry.key.toString(): entry.value is List ? (entry.value as List).map((m) => m.toString()).toList() : [entry.value.toString()],
  };
}

Duration? _retryAfter(String? header) {
  final seconds = int.tryParse(header ?? '');
  return seconds == null ? null : Duration(seconds: seconds);
}

String _fallbackMessage(int status) => switch (status) {
      401 => 'Please sign in again.',
      403 => 'You do not have permission to do that.',
      404 => 'This item could not be found.',
      _ => 'The request could not be completed.',
    };
