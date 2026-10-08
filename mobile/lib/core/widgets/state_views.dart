import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../network/api_exception.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_text.dart';
import 'app_button.dart';

/// Centered progress for a whole-screen load.
class LoadingView extends StatelessWidget {
  const LoadingView({super.key, this.label});

  final String? label;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 3, strokeCap: StrokeCap.round)),
          if (label != null) ...[
            const SizedBox(height: AppSpace.md),
            Text(label!, style: AppText.bodyMd.copyWith(color: AppColors.onSurfaceVariant)),
          ],
        ],
      ),
    );
  }
}

/// Icon in a soft circle, title, explanation and an optional action — for empty lists and errors.
class MessageView extends StatelessWidget {
  const MessageView({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
    this.tone = AppColors.surfaceContainerHigh,
    this.iconColor = AppColors.primaryContainer,
    this.footnote,
  });

  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final Color tone;
  final Color iconColor;
  final String? footnote;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: AppSpace.xl, vertical: AppSpace.xl),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(color: tone, shape: BoxShape.circle),
                child: Icon(icon, size: 30, color: iconColor),
              ),
              const SizedBox(height: AppSpace.lg),
              Text(title, style: AppText.headlineMd, textAlign: TextAlign.center),
              const SizedBox(height: AppSpace.xs + 2),
              Text(message, style: AppText.bodyMd.copyWith(color: AppColors.onSurfaceVariant), textAlign: TextAlign.center),
              if (actionLabel != null && onAction != null) ...[
                const SizedBox(height: AppSpace.lg),
                AppButton(label: actionLabel!, onPressed: onAction, variant: AppButtonVariant.tonal, size: AppButtonSize.medium),
              ],
              if (footnote != null) ...[
                const SizedBox(height: AppSpace.md),
                Text(footnote!, style: AppText.bodySm.copyWith(color: AppColors.outline), textAlign: TextAlign.center),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Error view chosen by exception type, with Retry. Shows the server request id for support.
class ErrorView extends StatelessWidget {
  const ErrorView({super.key, required this.error, this.onRetry});

  final Object error;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final api = error is ApiException ? error as ApiException : null;
    final (icon, title) = switch (api) {
      NetworkException() => (Symbols.wifi_off, 'You are offline'),
      TimeoutApiException() => (Symbols.hourglass_empty, 'Taking too long'),
      ForbiddenException() => (Symbols.lock, 'No access'),
      NotFoundException() => (Symbols.search_off, 'Not found'),
      UnauthorizedException() => (Symbols.lock_person, 'Please sign in again'),
      _ => (Symbols.error, 'Something went wrong'),
    };
    return MessageView(
      icon: icon,
      title: title,
      message: api?.message ?? 'An unexpected error occurred. Please try again.',
      tone: AppColors.errorContainer,
      iconColor: AppColors.onErrorContainer,
      actionLabel: onRetry == null ? null : 'Try again',
      onAction: onRetry,
      footnote: api?.requestId == null ? null : 'Reference: ${api!.requestId}',
    );
  }
}

/// Friendly sentence for an error in a snackbar.
String errorMessage(Object error) => error is ApiException ? error.message : 'Something went wrong. Please try again.';
