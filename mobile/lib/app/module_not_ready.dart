import 'package:flutter/material.dart';

import '../core/widgets/state_views.dart';
import 'modules.dart';
import 'section_scaffold.dart';

/// Shown for a module whose API is not built yet. States it plainly instead of faking data.
class ModuleNotReadyView extends StatelessWidget {
  const ModuleNotReadyView({super.key, required this.module});

  final AppModule module;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(top: MediaQuery.paddingOf(context).top + 64),
      child: MessageView(
        icon: module.icon,
        title: '${module.title} is on its way',
        message: '${module.description}\nThis section is built in delivery group ${module.group}.',
      ),
    );
  }
}

/// Bottom-nav tab for a module that is not built yet.
class ModuleNotReadySection extends StatelessWidget {
  const ModuleNotReadySection({super.key, required this.module});

  final AppModule module;

  @override
  Widget build(BuildContext context) => SectionScaffold(title: module.title, body: ModuleNotReadyView(module: module));
}

/// Pushed screen for a module that is not built yet (from the More menu or the bell).
class ModuleNotReadyScreen extends StatelessWidget {
  const ModuleNotReadyScreen({super.key, required this.module});

  final AppModule module;

  @override
  Widget build(BuildContext context) => DetailScaffold(title: module.title, body: ModuleNotReadyView(module: module));
}
