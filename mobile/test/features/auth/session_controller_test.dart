import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nutofe/core/network/api_client.dart';
import 'package:nutofe/core/network/api_exception.dart';
import 'package:nutofe/core/providers.dart';
import 'package:nutofe/features/auth/application/session_controller.dart';

import '../../support/fakes.dart';

void main() {
  late MemoryTokenStore tokens;
  late FakeAdapter adapter;

  ProviderContainer makeContainer() {
    final container = ProviderContainer(
      retry: (_, _) => null,
      overrides: [
        tokenStoreProvider.overrideWithValue(tokens),
        apiClientProvider.overrideWith((ref) => ApiClient(baseUrl: 'http://api.test/api/v1', tokens: tokens, adapter: adapter)),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  setUp(() {
    tokens = MemoryTokenStore();
    adapter = FakeAdapter((_) => FakeReply.ok(null));
  });

  test('starts signed out without stored tokens', () async {
    final container = makeContainer();
    expect(await container.read(sessionControllerProvider.future), isNull);
  });

  test('sign-in stores tokens, cached session and device id', () async {
    adapter.handler = (_) => FakeReply.ok(loginJson(), message: 'Signed in.');
    final container = makeContainer();
    await container.read(sessionControllerProvider.future);

    await container.read(sessionControllerProvider.notifier).signIn(' Owner@Nutofe.test ', 'Correct-Horse-42');

    final session = container.read(sessionControllerProvider).value!;
    expect(session.user.fullName, 'Marcus Owner');
    expect(session.business.currency, 'GHS');
    expect(tokens.access, 'nat_1');
    expect(tokens.session, isNotNull);

    final body = adapter.requests.single.data as Map<String, dynamic>;
    expect(body['email'], 'owner@nutofe.test');
    expect(body['device_id'], tokens.device);
  });

  test('wrong credentials surface the server message and stay signed out', () async {
    adapter.handler = (_) => FakeReply.error(401, 'INVALID_CREDENTIALS', 'Incorrect email or password.');
    final container = makeContainer();
    await container.read(sessionControllerProvider.future);

    await expectLater(
      container.read(sessionControllerProvider.notifier).signIn('owner@nutofe.test', 'nope'),
      throwsA(isA<UnauthorizedException>().having((e) => e.message, 'message', 'Incorrect email or password.')),
    );
    expect(container.read(sessionControllerProvider).value, isNull);
  });

  test('opens offline from the cached session', () async {
    tokens
      ..access = 'nat_1'
      ..refresh = 'nrt_1'
      ..session = {'user': userJson(), 'business': businessJson};
    adapter.offline = true;
    final container = makeContainer();

    final session = await container.read(sessionControllerProvider.future);
    await Future<void>.delayed(Duration.zero); // background revalidation fails offline

    expect(session?.user.email, 'owner@nutofe.test');
    expect(container.read(sessionControllerProvider).value, isNotNull, reason: 'offline must not sign the user out');
  });

  test('revoked session on revalidation signs out with a notice', () async {
    tokens
      ..access = 'nat_1'
      ..refresh = 'nrt_1'
      ..session = {'user': userJson(), 'business': businessJson};
    adapter.handler = (request) => request.path.endsWith('/auth/refresh')
        ? FakeReply.error(401, 'INVALID_REFRESH_TOKEN', 'Invalid')
        : FakeReply.error(401, 'TOKEN_EXPIRED', 'Expired');
    final container = makeContainer();

    await container.read(sessionControllerProvider.future);
    await pumpEventQueue();

    expect(container.read(sessionControllerProvider).value, isNull);
    expect(container.read(signInNoticeProvider), contains('session has ended'));
    expect(tokens.refresh, isNull);
  });

  test('sign-out clears local secrets even when offline', () async {
    tokens
      ..access = 'nat_1'
      ..refresh = 'nrt_1'
      ..session = {'user': userJson(), 'business': businessJson};
    adapter.offline = true;
    final container = makeContainer();
    await container.read(sessionControllerProvider.future);

    await container.read(sessionControllerProvider.notifier).signOut();

    expect(container.read(sessionControllerProvider).value, isNull);
    expect(tokens.access, isNull);
    expect(tokens.session, isNull);
  });
}
