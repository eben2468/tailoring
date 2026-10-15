import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/config/env.dart';
import '../core/theme/app_theme.dart';
import '../features/notifications/application/push_controller.dart';
import 'router.dart';

class NutofeApp extends ConsumerWidget {
  const NutofeApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(pushControllerProvider); // push token, foreground messages, tapped notifications
    return MaterialApp.router(
      title: Env.appName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      themeMode: ThemeMode.light,
      routerConfig: ref.watch(routerProvider),
    );
  }
}
