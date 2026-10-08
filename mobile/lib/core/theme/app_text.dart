import 'package:flutter/material.dart';

import 'app_colors.dart';

/// Type scale from the Stitch config (all Plus Jakarta Sans). Letter spacing is converted
/// from em to logical pixels. Numeric styles use tabular figures, as DESIGN.md requires
/// for measurements, hours and deadlines.
abstract final class AppText {
  static const fontFamily = 'PlusJakartaSans';

  /// Plus Jakarta Sans has no ɔ/ɛ/ŋ (needed for "Nutɔfe" and Ghanaian names); Noto Sans fills them in.
  static const fontFallback = ['NotoSansFallback'];
  static const _tabular = [FontFeature.tabularFigures()];

  static TextStyle _style(double size, double height, FontWeight weight, {double em = 0, bool tabular = false}) => TextStyle(
        fontFamily: fontFamily,
        fontFamilyFallback: fontFallback,
        fontSize: size,
        height: height / size,
        fontWeight: weight,
        letterSpacing: size * em,
        color: AppColors.onSurface,
        fontFeatures: tabular ? _tabular : null,
        leadingDistribution: TextLeadingDistribution.even,
      );

  static final displayLg = _style(32, 40, FontWeight.w700, em: -0.02);
  static final displayLgMobile = _style(26, 34, FontWeight.w700, em: -0.02, tabular: true);
  static final headlineLg = _style(22, 28, FontWeight.w600, em: -0.015);
  static final headlineMd = _style(18, 24, FontWeight.w600, em: -0.01);
  static final titleSm = _style(15, 20, FontWeight.w600);
  static final bodyLg = _style(15, 22, FontWeight.w400);
  static final bodyMd = _style(13, 18, FontWeight.w400);
  static final bodySm = _style(12, 16, FontWeight.w400);
  static final labelMd = _style(12, 16, FontWeight.w600, em: 0.02);
  static final labelSm = _style(11, 14, FontWeight.w600, em: 0.04);
  static final metricNum = _style(20, 24, FontWeight.w700, em: -0.01, tabular: true);

  /// Uppercase micro label used for section kickers and tile captions ("ACTIVE JOBS").
  static final overline = labelSm.copyWith(color: AppColors.onSurfaceVariant, letterSpacing: 11 * 0.08);
}
