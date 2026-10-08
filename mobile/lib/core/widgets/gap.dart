import 'package:flutter/widgets.dart';

import '../theme/app_spacing.dart';

/// Fixed spacing that reads like the Tailwind gap utilities used in the Stitch HTML.
class Gap extends StatelessWidget {
  const Gap(this.size, {super.key});

  final double size;

  static const xs = Gap(AppSpace.xs);
  static const sm = Gap(AppSpace.sm);
  static const md = Gap(AppSpace.md);
  static const lg = Gap(AppSpace.lg);
  static const xl = Gap(AppSpace.xl);

  @override
  Widget build(BuildContext context) => SizedBox(width: size, height: size);
}
