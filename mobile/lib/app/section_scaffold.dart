import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/widgets/app_top_bar.dart';
import '../features/auth/application/session_controller.dart';
import 'routes.dart';

/// Scaffold for a bottom-nav section: the frosted section header (logo, name, bell, avatar)
/// wired to notifications and the profile.
class SectionScaffold extends ConsumerWidget {
  const SectionScaffold({super.key, required this.title, required this.body, this.floatingActionButton});

  final String title;
  final Widget body;
  final Widget? floatingActionButton;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(sessionControllerProvider).value?.user;
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppTopBar.section(
        title: title,
        userName: user?.fullName,
        onNotifications: () => context.push(Routes.notifications),
        onAvatar: () => context.push(Routes.profile),
      ),
      body: body,
      floatingActionButton: floatingActionButton,
    );
  }
}

/// Scaffold for a pushed detail screen: back · "NUTƆFE" · title · bell · avatar.
class DetailScaffold extends ConsumerWidget {
  const DetailScaffold({super.key, required this.title, required this.body, this.bottomBar, this.actions = const []});

  final String title;
  final Widget body;
  final Widget? bottomBar;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(sessionControllerProvider).value?.user;
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppTopBar.detail(
        title: title,
        userName: user?.fullName,
        actions: actions,
        onNotifications: () => context.push(Routes.notifications),
        onAvatar: () => context.push(Routes.profile),
      ),
      body: body,
      bottomNavigationBar: bottomBar,
    );
  }
}

/// Padding that clears the frosted header (status bar + 64px) so content scrolls beneath it.
EdgeInsets belowHeader(BuildContext context, {double bottom = 24}) =>
    EdgeInsets.fromLTRB(16, MediaQuery.paddingOf(context).top + 64 + 12, 16, MediaQuery.paddingOf(context).bottom + bottom);

/// Same, for bottom-nav sections. The shell Scaffold (extendBody) already adds the dock height to
/// MediaQuery.padding.bottom, so this only adds breathing room above it.
EdgeInsets belowHeaderAboveNav(BuildContext context) => belowHeader(context);

/// Top padding only (first sliver of a scroll view whose list continues below).
EdgeInsets headerOnly(BuildContext context) => EdgeInsets.fromLTRB(16, MediaQuery.paddingOf(context).top + 64 + 12, 16, 0);
