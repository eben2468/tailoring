import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../sync/application/sync_providers.dart';
import '../data/notifications_api.dart';
import '../domain/app_notification.dart';

final notificationsApiProvider = Provider<NotificationsApi>((ref) => NotificationsApi(ref.watch(syncEngineProvider)));

final notificationsProvider = Provider<AsyncValue<List<AppNotification>>>(
  (ref) => fromStore(ref, (p) => [for (final n in p.notifications()) AppNotification.fromJson(n)]),
);

/// For the bell badge (0 until the first sync).
final unreadNotificationsProvider = Provider<int>((ref) => ref.watch(presenterProvider).value?.unreadNotifications() ?? 0);
