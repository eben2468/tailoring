import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_text.dart';

enum AppButtonVariant {
  /// Midnight navy, white text — the main action ("Start Timer", "+ Add Job").
  primary,

  /// Light blue tonal — secondary actions ("View Sheet", "Reschedule").
  tonal,

  /// White with hairline outline ("Schedule Tech").
  outline,

  /// Soft rose with red text — destructive or urgent.
  danger,

  /// Text-only link in tailor blue ("View All 14").
  text,
}

enum AppButtonSize {
  /// 48px — full-width form and screen actions.
  large,

  /// 40px — in-card actions.
  medium,

  /// 32px — compact chips/links inside rows ("Reorder", "Log").
  small,
}

/// The one button component; variants mirror the button styles used across the Stitch screens.
class AppButton extends StatelessWidget {
  const AppButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.variant = AppButtonVariant.primary,
    this.size = AppButtonSize.large,
    this.loading = false,
    this.expand = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final AppButtonVariant variant;
  final AppButtonSize size;
  final bool loading;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final (background, foreground, border) = switch (variant) {
      AppButtonVariant.primary => (AppColors.primaryContainer, AppColors.onPrimary, null),
      AppButtonVariant.tonal => (AppColors.surfaceContainerHigh, AppColors.primaryContainer, null),
      AppButtonVariant.outline => (AppColors.surfaceContainerLowest, AppColors.onSurface, const BorderSide(color: AppColors.outlineVariant)),
      AppButtonVariant.danger => (AppColors.errorContainer, AppColors.onErrorContainer, null),
      AppButtonVariant.text => (Colors.transparent, AppColors.secondary, null),
    };
    final height = switch (size) {
      AppButtonSize.large => 48.0,
      AppButtonSize.medium => 40.0,
      AppButtonSize.small => 32.0,
    };
    final textStyle = (size == AppButtonSize.large ? AppText.titleSm : AppText.labelMd).copyWith(color: foreground, fontWeight: FontWeight.w600);
    final iconSize = size == AppButtonSize.small ? 16.0 : 18.0;
    final enabled = onPressed != null && !loading;

    final child = Row(
      mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (loading)
          SizedBox(
            width: iconSize,
            height: iconSize,
            child: CircularProgressIndicator(strokeWidth: 2, color: foreground),
          )
        else if (icon != null)
          Icon(icon, size: iconSize, color: foreground),
        if (loading || icon != null) const SizedBox(width: 6),
        Flexible(
          child: Text(label, style: textStyle, overflow: TextOverflow.ellipsis, maxLines: 1),
        ),
      ],
    );

    return AnimatedOpacity(
      opacity: enabled || loading ? 1 : 0.45,
      duration: AppMotion.fast,
      child: SizedBox(
        height: height,
        width: expand ? double.infinity : null,
        child: TextButton(
          onPressed: enabled ? onPressed : null,
          style: TextButton.styleFrom(
            backgroundColor: background,
            foregroundColor: foreground,
            disabledForegroundColor: foreground,
            padding: EdgeInsets.symmetric(horizontal: variant == AppButtonVariant.text ? AppSpace.xs : AppSpace.md + 2),
            minimumSize: Size(0, height),
            shape: RoundedRectangleBorder(borderRadius: AppRadius.control, side: border ?? BorderSide.none),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            visualDensity: VisualDensity.standard,
          ),
          child: child,
        ),
      ),
    );
  }
}
