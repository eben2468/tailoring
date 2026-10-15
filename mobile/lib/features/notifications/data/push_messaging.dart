import 'package:firebase_messaging/firebase_messaging.dart';

/// A push message as the app needs it: where tapping it should go (data.route from the server).
class PushMessage {
  const PushMessage({this.route, this.notificationId});

  factory PushMessage.fromData(Map<String, dynamic> data) => PushMessage(
        route: (data['route'] as String?)?.isEmpty ?? true ? null : data['route'] as String,
        notificationId: data['notification_id'] as String?,
      );

  final String? route;
  final String? notificationId;
}

/// The phone's push channel (Firebase Cloud Messaging), behind an interface so tests can use a fake
/// and the app runs without Firebase (push off).
abstract class PushMessaging {
  /// Asks the user (Android 13+, iOS). Returns whether notifications may be shown.
  Future<bool> requestPermission();

  /// This phone's token, or null when it cannot be had (no Google Play services, no network yet).
  Future<String?> token();

  Stream<String> get tokenRefreshes;

  /// Messages that arrive while the app is open (the system shows nothing then).
  Stream<PushMessage> get foreground;

  /// Notifications the user tapped while the app was in the background.
  Stream<PushMessage> get opened;

  /// The notification that started the app from closed, if any.
  Future<PushMessage?> initial();
}

class FirebasePushMessaging implements PushMessaging {
  FirebasePushMessaging([FirebaseMessaging? messaging]) : _fm = messaging ?? FirebaseMessaging.instance;

  final FirebaseMessaging _fm;

  @override
  Future<bool> requestPermission() async {
    final settings = await _fm.requestPermission();
    return settings.authorizationStatus == AuthorizationStatus.authorized || settings.authorizationStatus == AuthorizationStatus.provisional;
  }

  @override
  Future<String?> token() => _fm.getToken();

  @override
  Stream<String> get tokenRefreshes => _fm.onTokenRefresh;

  @override
  Stream<PushMessage> get foreground => FirebaseMessaging.onMessage.map((m) => PushMessage.fromData(m.data));

  @override
  Stream<PushMessage> get opened => FirebaseMessaging.onMessageOpenedApp.map((m) => PushMessage.fromData(m.data));

  @override
  Future<PushMessage?> initial() async {
    final m = await _fm.getInitialMessage();
    return m == null ? null : PushMessage.fromData(m.data);
  }
}
