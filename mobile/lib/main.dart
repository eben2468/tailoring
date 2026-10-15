import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'app/app.dart';
import 'core/local/local_store.dart';
import 'features/notifications/application/push_controller.dart';
import 'features/notifications/data/push_messaging.dart';
import 'features/sync/application/sync_providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,
    systemNavigationBarColor: Colors.transparent,
    systemNavigationBarIconBrightness: Brightness.dark,
  ));
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

  // The offline copy of the business data lives in app-private storage (not backed up: allowBackup=false).
  final store = LocalStore.open(p.join((await getApplicationSupportDirectory()).path, 'nutofe.db'));

  // Push (Firebase Cloud Messaging) needs android/app/google-services.json; without it the app runs with push off.
  PushMessaging? push;
  try {
    await Firebase.initializeApp();
    push = FirebasePushMessaging();
  } catch (e) {
    debugPrint('Push is off: $e');
  }

  // Riverpod 3 retries failed providers automatically; API errors are shown to the user instead.
  runApp(ProviderScope(
    retry: (_, _) => null,
    overrides: [localStoreProvider.overrideWithValue(store), pushMessagingProvider.overrideWithValue(push)],
    child: const NutofeApp(),
  ));
}
