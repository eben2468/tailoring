import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/router.dart';
import '../../../app/routes.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/providers.dart';
import '../../auth/application/session_controller.dart';
import '../../sync/application/sync_providers.dart';
import '../data/push_messaging.dart';

/// The phone's push channel; null when Firebase is not configured (tests, or a build without
/// google-services.json). main() overrides it once Firebase has started.
final pushMessagingProvider = Provider<PushMessaging?>((ref) => null);

/// Push on this phone (watched by the app root):
///  - signed in → ask for permission, send the token (PUT /devices/current/push-token) and again when it changes;
///    sign-out clears it on the server;
///  - a message while the app is open → sync, so the bell and the list update;
///  - a tapped notification → sync, then open its screen (data.route), or the notification centre.
final pushControllerProvider = Provider<void>((ref) {
  final push = ref.watch(pushMessagingProvider);
  if (push == null) return;
  final subscriptions = <StreamSubscription<Object?>>[];
  ref.onDispose(() {
    for (final s in subscriptions) {
      s.cancel();
    }
  });

  Future<void> sendToken([String? known]) async {
    if (ref.read(sessionControllerProvider).value == null) return;
    try {
      final token = known ?? await push.token();
      if (token == null) return;
      await ref.read(apiClientProvider).put('/devices/current/push-token', body: {'fcm_token': token});
    } on ApiException catch (e) {
      debugPrint('Push token not registered: ${e.message}'); // offline or no device: tried again at the next start
    } catch (e) {
      debugPrint('Push token unavailable: $e');
    }
  }

  Future<void> open(PushMessage message) async {
    unawaited(ref.read(syncControllerProvider.notifier).syncNow());
    final route = message.route;
    unawaited(ref.read(routerProvider).push(route != null && route.startsWith('/') ? route : Routes.notifications));
  }

  ref.listen(sessionControllerProvider.select((s) => s.value?.user.id), (previous, userId) async {
    if (userId == null || userId == previous) return;
    await push.requestPermission();
    await sendToken();
  }, fireImmediately: true);

  subscriptions
    ..add(push.tokenRefreshes.listen(sendToken))
    ..add(push.foreground.listen((_) => ref.read(syncControllerProvider.notifier).syncNow()))
    ..add(push.opened.listen(open));
  unawaited(push.initial().then((m) {
    if (m != null) open(m);
  }));
});
