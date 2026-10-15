import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';

/// Square header action (Stitch job sheet: rounded-lg tinted buttons for edit / share / print).
/// Pass [onPressed] for a button, or leave it null to use the box as a menu trigger's child.
class HeaderIconButton extends StatelessWidget {
  const HeaderIconButton({super.key, required this.icon, this.onPressed, this.tooltip});

  final IconData icon;
  final VoidCallback? onPressed;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final box = Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLow,
        borderRadius: AppRadius.control,
        border: Border.all(color: AppColors.surfaceContainerHigh),
      ),
      child: Icon(icon, size: 20, color: AppColors.onSurface),
    );
    if (onPressed == null) return box;
    return Tooltip(
      message: tooltip ?? '',
      child: Material(
        type: MaterialType.transparency,
        borderRadius: AppRadius.control,
        clipBehavior: Clip.antiAlias,
        child: InkWell(onTap: onPressed, child: box),
      ),
    );
  }
}
