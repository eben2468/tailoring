import 'package:flutter/material.dart';

import 'app_colors.dart';

/// Spacing scale from the Stitch config (4/8 px rhythm).
abstract final class AppSpace {
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 24.0;

  /// Outer screen margin (`margin`) and column gutter (`gutter`).
  static const margin = 16.0;
  static const gutter = 12.0;
  static const marginTablet = 24.0;

  static const screen = EdgeInsets.symmetric(horizontal: margin);
}

/// Corner radii as rendered in the Stitch screens (Tailwind config in code.html):
/// rounded = 4, rounded-lg = 8 (buttons, inputs, inner tiles), rounded-xl = 12 (cards).
abstract final class AppRadius {
  static const sm = 4.0;
  static const lg = 8.0;
  static const xl = 12.0;
  static const pill = 999.0;

  static final card = BorderRadius.circular(xl);
  static final control = BorderRadius.circular(lg);
  static final small = BorderRadius.circular(sm);
  static final full = BorderRadius.circular(pill);
}

/// Elevation recipes from DESIGN.md / the Stitch HTML.
abstract final class AppShadows {
  /// Tailwind `shadow-sm` on cards.
  static const card = [BoxShadow(color: Color(0x0D000000), offset: Offset(0, 1), blurRadius: 2)];

  /// Raised, actionable surfaces (dark AI card, primary call-to-action).
  static const raised = [
    BoxShadow(color: Color(0x14000000), offset: Offset(0, 4), blurRadius: 6, spreadRadius: -1),
    BoxShadow(color: Color(0x0F000000), offset: Offset(0, 2), blurRadius: 4, spreadRadius: -2),
  ];

  /// Header: 0 1px 8px rgba(0,0,0,0.04)
  static const header = [BoxShadow(color: Color(0x0A000000), offset: Offset(0, 1), blurRadius: 8)];

  /// Bottom bar and sheets: 0 -4px 20px rgba(15,27,46,0.06)
  static final bottomBar = [BoxShadow(color: AppColors.shadowNavy.withValues(alpha: 0.06), offset: const Offset(0, -4), blurRadius: 20)];
}

/// Durations/curves used for consistent motion.
abstract final class AppMotion {
  static const fast = Duration(milliseconds: 150);
  static const medium = Duration(milliseconds: 250);
  static const curve = Curves.easeOutCubic;
}
