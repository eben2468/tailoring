import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_colors.dart';
import 'app_spacing.dart';
import 'app_text.dart';

/// Material theme configured from the design tokens so that any stock widget we use
/// (dialogs, sheets, snackbars, inputs, progress indicators) already matches Stitch.
abstract final class AppTheme {
  static ThemeData light() {
    const scheme = ColorScheme(
      brightness: Brightness.light,
      primary: AppColors.primaryContainer,
      onPrimary: AppColors.onPrimary,
      primaryContainer: AppColors.primaryFixed,
      onPrimaryContainer: AppColors.primaryContainer,
      secondary: AppColors.secondary,
      onSecondary: AppColors.onSecondary,
      secondaryContainer: AppColors.secondaryFixed,
      onSecondaryContainer: AppColors.onSecondaryFixedVariant,
      tertiary: AppColors.onTertiaryContainer,
      onTertiary: AppColors.onPrimary,
      error: AppColors.error,
      onError: AppColors.onError,
      errorContainer: AppColors.errorContainer,
      onErrorContainer: AppColors.onErrorContainer,
      surface: AppColors.surface,
      onSurface: AppColors.onSurface,
      onSurfaceVariant: AppColors.onSurfaceVariant,
      surfaceContainerLowest: AppColors.surfaceContainerLowest,
      surfaceContainerLow: AppColors.surfaceContainerLow,
      surfaceContainer: AppColors.surfaceContainer,
      surfaceContainerHigh: AppColors.surfaceContainerHigh,
      surfaceContainerHighest: AppColors.surfaceContainerHighest,
      outline: AppColors.outline,
      outlineVariant: AppColors.outlineVariant,
      inverseSurface: AppColors.inverseSurface,
      onInverseSurface: AppColors.inverseOnSurface,
    );

    final textTheme = TextTheme(
      displayLarge: AppText.displayLg,
      displayMedium: AppText.displayLgMobile,
      headlineLarge: AppText.headlineLg,
      headlineMedium: AppText.headlineMd,
      titleMedium: AppText.titleSm,
      titleSmall: AppText.titleSm,
      bodyLarge: AppText.bodyLg,
      bodyMedium: AppText.bodyMd,
      bodySmall: AppText.bodySm,
      labelLarge: AppText.labelMd,
      labelMedium: AppText.labelMd,
      labelSmall: AppText.labelSm,
    );

    final inputBorder = OutlineInputBorder(borderRadius: AppRadius.control, borderSide: BorderSide.none);

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      fontFamily: AppText.fontFamily,
      fontFamilyFallback: AppText.fontFallback,
      textTheme: textTheme,
      scaffoldBackgroundColor: AppColors.surface,
      splashFactory: InkSparkle.splashFactory,
      visualDensity: VisualDensity.standard,
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        systemOverlayStyle: SystemUiOverlayStyle.dark,
      ),
      dividerTheme: const DividerThemeData(color: AppColors.surfaceContainer, thickness: 1, space: 1),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surfaceContainerLow,
        contentPadding: const EdgeInsets.symmetric(horizontal: AppSpace.md, vertical: 14),
        hintStyle: AppText.bodyLg.copyWith(color: AppColors.outline),
        labelStyle: AppText.bodyMd.copyWith(color: AppColors.onSurfaceVariant),
        errorStyle: AppText.bodySm.copyWith(color: AppColors.error),
        border: inputBorder,
        enabledBorder: inputBorder,
        focusedBorder: inputBorder.copyWith(borderSide: const BorderSide(color: AppColors.secondary, width: 1.5)),
        errorBorder: inputBorder.copyWith(borderSide: const BorderSide(color: AppColors.error, width: 1)),
        focusedErrorBorder: inputBorder.copyWith(borderSide: const BorderSide(color: AppColors.error, width: 1.5)),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AppColors.secondary,
        linearTrackColor: AppColors.surfaceContainer,
        circularTrackColor: AppColors.surfaceContainer,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.inverseSurface,
        contentTextStyle: AppText.bodyMd.copyWith(color: AppColors.inverseOnSurface),
        shape: RoundedRectangleBorder(borderRadius: AppRadius.control),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: AppColors.surfaceContainerLowest,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        dragHandleColor: AppColors.outlineVariant,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl + 4))),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.surfaceContainerLowest,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: AppRadius.card),
        titleTextStyle: AppText.headlineMd,
        contentTextStyle: AppText.bodyLg.copyWith(color: AppColors.onSurfaceVariant),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? AppColors.onPrimary : AppColors.outline),
        trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? AppColors.secondary : AppColors.surfaceContainerHigh),
        trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
      ),
      pageTransitionsTheme: const PageTransitionsTheme(builders: {
        TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
        TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
      }),
    );
  }
}
