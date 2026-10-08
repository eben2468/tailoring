import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_text.dart';
import 'app_button.dart';

/// Floating snackbar in the inverse-surface style; [isError] adds an error icon.
void showAppSnack(BuildContext context, String message, {bool isError = false}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(isError ? Symbols.error : Symbols.check_circle, size: 18, color: isError ? AppColors.errorContainer : AppColors.tertiaryFixedDim),
            const SizedBox(width: AppSpace.sm),
            Expanded(child: Text(message)),
          ],
        ),
      ),
    );
}

/// Bottom-sheet confirmation (thumb-zone friendly). Returns true when confirmed.
Future<bool> confirmAction(BuildContext context, {required String title, required String message, required String confirmLabel, bool destructive = false}) async {
  final result = await showModalBottomSheet<bool>(
    context: context,
    useRootNavigator: true, // above the bottom navigation and timer bar
    useSafeArea: true,
    builder: (context) => Padding(
      padding: const EdgeInsets.fromLTRB(AppSpace.margin, 0, AppSpace.margin, AppSpace.lg),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: AppText.headlineMd),
          const SizedBox(height: AppSpace.sm),
          Text(message, style: AppText.bodyLg.copyWith(color: AppColors.onSurfaceVariant)),
          const SizedBox(height: AppSpace.xl),
          AppButton(label: confirmLabel, expand: true, variant: destructive ? AppButtonVariant.danger : AppButtonVariant.primary, onPressed: () => Navigator.of(context).pop(true)),
          const SizedBox(height: AppSpace.sm),
          AppButton(label: 'Cancel', expand: true, variant: AppButtonVariant.outline, onPressed: () => Navigator.of(context).pop(false)),
        ],
      ),
    ),
  );
  return result ?? false;
}
