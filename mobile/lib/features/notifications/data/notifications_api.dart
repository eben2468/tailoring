import '../../sync/data/sync_engine.dart';
import '../domain/app_notification.dart';

/// Marking notifications read (docs/API_REFERENCE.md §15). Works offline; the list comes from the
/// local copy (notifications arrive with the normal sync).
class NotificationsApi {
  const NotificationsApi(this._sync);

  final SyncEngine _sync;

  Future<void> markRead(AppNotification n) async {
    if (!n.isUnread) return;
    await _sync.perform(label: 'Read: ${n.title}', method: 'POST', path: '/notifications/${n.id}/read');
  }

  Future<void> markAllRead() => _sync.perform(label: 'Mark notifications read', method: 'POST', path: '/notifications/read-all');
}
