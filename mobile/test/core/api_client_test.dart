import 'package:flutter_test/flutter_test.dart';
import 'package:nutofe/core/network/api_client.dart';
import 'package:nutofe/core/network/api_exception.dart';

import '../support/fakes.dart';

void main() {
  late MemoryTokenStore tokens;
  late FakeAdapter adapter;
  late ApiClient client;

  setUp(() {
    tokens = MemoryTokenStore()
      ..access = 'nat_old'
      ..refresh = 'nrt_old';
    adapter = FakeAdapter((_) => FakeReply.ok(null));
    client = ApiClient(baseUrl: 'http://api.test/api/v1', tokens: tokens, adapter: adapter);
  });

  test('unwraps data and sends the bearer token', () async {
    adapter.handler = (_) => FakeReply.ok({'value': 42});
    final data = await client.get('/thing') as Map<String, dynamic>;

    expect(data['value'], 42);
    expect(adapter.requests.single.headers['Authorization'], 'Bearer nat_old');
  });

  test('maps paginated lists', () async {
    adapter.handler = (_) => FakeReply.ok(
          [{'n': 1}, {'n': 2}],
          meta: {'pagination': {'page': 1, 'per_page': 2, 'total': 5, 'total_pages': 3}},
        );
    final page = await client.getPaged('/things', (j) => j['n'] as int);

    expect(page.items, [1, 2]);
    expect(page.total, 5);
    expect(page.hasMore, isTrue);
  });

  test('maps every error status to a typed exception', () async {
    final cases = <int, Matcher>{
      401: isA<UnauthorizedException>(),
      403: isA<ForbiddenException>(),
      404: isA<NotFoundException>(),
      409: isA<ConflictException>(),
      422: isA<ValidationException>(),
      429: isA<RateLimitedException>(),
      500: isA<ServerException>(),
    };
    for (final entry in cases.entries) {
      adapter.handler = (_) => FakeReply.error(entry.key, 'CODE_${entry.key}', 'Message ${entry.key}');
      await expectLater(client.get('/x'), throwsA(entry.value), reason: 'status ${entry.key}');
    }
  });

  test('validation errors keep field messages, request id and code', () async {
    adapter.handler = (_) => FakeReply.error(422, 'VALIDATION_FAILED', 'Some fields are invalid.', errors: {
          'email': ['The email field must be a valid email address.'],
        });

    final error = await client.post('/x').then<Object>((_) => fail('should throw'), onError: (Object e) => e);
    final validation = error as ValidationException;
    expect(validation.forField('email'), 'The email field must be a valid email address.');
    expect(validation.code, 'VALIDATION_FAILED');
    expect(validation.requestId, 'req-test');
  });

  test('server errors never surface internal messages', () async {
    adapter.handler = (_) => const FakeReply(500, {'success': false, 'message': 'SQLSTATE[42S02] leaked?', 'code': 'INTERNAL_ERROR'});
    final error = await client.get('/x').then<Object>((_) => fail('should throw'), onError: (Object e) => e);
    expect((error as ServerException).message, isNot(contains('SQLSTATE')));
  });

  test('rate limiting exposes Retry-After', () async {
    adapter.handler = (_) => FakeReply.error(429, 'ACCOUNT_LOCKED', 'Locked', headers: {'retry-after': '900'});
    final error = await client.get('/x').then<Object>((_) => fail('should throw'), onError: (Object e) => e);
    expect((error as RateLimitedException).retryAfter, const Duration(seconds: 900));
  });

  test('no connection becomes NetworkException', () async {
    adapter.offline = true;
    await expectLater(client.get('/x'), throwsA(isA<NetworkException>()));
  });

  test('expired access token is refreshed once and the request retried', () async {
    adapter.handler = (request) {
      if (request.path.endsWith('/auth/refresh')) {
        return FakeReply.ok({'access_token': 'nat_new', 'refresh_token': 'nrt_new'});
      }
      final auth = request.headers['Authorization'];
      return auth == 'Bearer nat_new' ? FakeReply.ok({'ok': true}) : FakeReply.error(401, 'TOKEN_EXPIRED', 'Expired');
    };

    final data = await client.get('/thing') as Map<String, dynamic>;

    expect(data['ok'], isTrue);
    expect(tokens.access, 'nat_new');
    expect(tokens.refresh, 'nrt_new');
    expect(adapter.requests.where((r) => r.path.endsWith('/auth/refresh')), hasLength(1));
  });

  test('parallel requests share a single refresh (server rotates refresh tokens)', () async {
    adapter.handler = (request) async {
      if (request.path.endsWith('/auth/refresh')) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
        return FakeReply.ok({'access_token': 'nat_new', 'refresh_token': 'nrt_new'});
      }
      return request.headers['Authorization'] == 'Bearer nat_new' ? FakeReply.ok({'ok': true}) : FakeReply.error(401, 'TOKEN_EXPIRED', 'Expired');
    };

    await Future.wait([client.get('/a'), client.get('/b'), client.get('/c')]);

    expect(adapter.requests.where((r) => r.path.endsWith('/auth/refresh')), hasLength(1));
  });

  test('failed refresh signals session expiry', () async {
    var expired = false;
    client.onSessionExpired = () => expired = true;
    adapter.handler = (request) => request.path.endsWith('/auth/refresh')
        ? FakeReply.error(401, 'INVALID_REFRESH_TOKEN', 'Invalid')
        : FakeReply.error(401, 'TOKEN_EXPIRED', 'Expired');

    await expectLater(client.get('/thing'), throwsA(isA<UnauthorizedException>()));
    expect(expired, isTrue);
  });

  test('other 401s do not trigger a refresh', () async {
    adapter.handler = (_) => FakeReply.error(401, 'UNAUTHENTICATED', 'No');
    await expectLater(client.get('/thing'), throwsA(isA<UnauthorizedException>()));
    expect(adapter.requests.where((r) => r.path.endsWith('/auth/refresh')), isEmpty);
  });
}
