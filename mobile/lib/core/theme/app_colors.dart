import 'package:flutter/material.dart';

/// Colour tokens copied 1:1 from the Stitch Tailwind config (design/stitch/*/code.html),
/// which is what produced the approved screenshots. Status colours not covered by those
/// tokens (amber warning) come from design/stitch/atelier_bespoke_system/DESIGN.md.
abstract final class AppColors {
  // Surfaces
  static const surface = Color(0xFFF9F9FF);
  static const surfaceDim = Color(0xFFCFDAF2);
  static const surfaceContainerLowest = Color(0xFFFFFFFF);
  static const surfaceContainerLow = Color(0xFFF0F3FF);
  static const surfaceContainer = Color(0xFFE7EEFF);
  static const surfaceContainerHigh = Color(0xFFDEE8FF);
  static const surfaceContainerHighest = Color(0xFFD8E3FB);
  static const inverseSurface = Color(0xFF263143);
  static const inverseOnSurface = Color(0xFFECF1FF);

  // Content
  static const onSurface = Color(0xFF111C2D);
  static const onSurfaceVariant = Color(0xFF45474C);
  static const outline = Color(0xFF75777D);
  static const outlineVariant = Color(0xFFC5C6CD);

  // Primary — midnight navy anchors and primary actions
  static const primary = Color(0xFF000000);
  static const onPrimary = Color(0xFFFFFFFF);
  static const primaryContainer = Color(0xFF101C2F);
  static const onPrimaryContainer = Color(0xFF78849C);
  static const primaryFixed = Color(0xFFD7E3FD);
  static const primaryFixedDim = Color(0xFFBBC7E0);
  static const onPrimaryFixedVariant = Color(0xFF3C475C);

  // Secondary — tailor blue (in progress, links, focus)
  static const secondary = Color(0xFF0051D5);
  static const onSecondary = Color(0xFFFFFFFF);
  static const secondaryContainer = Color(0xFF316BF3);
  static const secondaryFixed = Color(0xFFDBE1FF);
  static const secondaryFixedDim = Color(0xFFB4C5FF);
  static const onSecondaryFixed = Color(0xFF00174B);
  static const onSecondaryFixedVariant = Color(0xFF003EA8);

  // Tertiary — atelier green (completed, healthy, on schedule)
  static const tertiaryContainer = Color(0xFF002113);
  static const onTertiaryContainer = Color(0xFF009668);
  static const tertiaryFixed = Color(0xFF6FFBBE);
  static const tertiaryFixedDim = Color(0xFF4EDEA3);

  // Error — critical / overdue
  static const error = Color(0xFFBA1A1A);
  static const onError = Color(0xFFFFFFFF);
  static const errorContainer = Color(0xFFFFDAD6);
  static const onErrorContainer = Color(0xFF93000A);

  // Warning — approaching deadline (DESIGN.md "Amber Warning" / "Soft Sand")
  static const warning = Color(0xFFB45309);
  static const warningContainer = Color(0xFFFFFBEB);
  static const warningAccent = Color(0xFFF59E0B);

  /// Shadow tint used by the design (rgba(15, 27, 46, …)).
  static const shadowNavy = Color(0xFF0F1B2E);
}
