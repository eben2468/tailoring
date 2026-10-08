import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';

/// Fixed white bar at the bottom of a detail screen holding its main action(s) — the thumb zone
/// used by the Stitch designs ("Mark Stage Complete", "Queue Production").
class BottomActionBar extends StatelessWidget {
  const BottomActionBar({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(color: AppColors.surfaceContainerLowest, boxShadow: AppShadows.bottomBar),
      padding: EdgeInsets.fromLTRB(AppSpace.margin, AppSpace.md, AppSpace.margin, AppSpace.md + MediaQuery.paddingOf(context).bottom),
      child: child,
    );
  }
}
