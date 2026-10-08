import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_text.dart';

/// Circle with initials — used for the signed-in user and for customers (the jobs list "KM" avatars).
class InitialsAvatar extends StatelessWidget {
  const InitialsAvatar({super.key, required this.name, this.size = 40, this.ring = false, this.dark = false});

  final String name;
  final double size;
  final bool ring;

  /// Navy variant (white initials), used for emphasis.
  final bool dark;

  static String initialsOf(String name) {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    final first = parts.first.characters.first;
    final last = parts.length > 1 ? parts.last.characters.first : '';
    return (first + last).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: dark ? AppColors.primaryContainer : AppColors.surfaceContainerHigh,
        shape: BoxShape.circle,
        border: ring ? Border.all(color: AppColors.surfaceContainerHigh, width: 1) : null,
      ),
      child: Text(
        initialsOf(name),
        style: AppText.titleSm.copyWith(
          fontSize: size * 0.36,
          height: 1,
          color: dark ? AppColors.onPrimary : AppColors.onSurface,
        ),
      ),
    );
  }
}
