import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_text.dart';

/// Label-above filled field (tinted surface, 8px radius, 1.5px tailor-blue focus border).
/// [errorText] shows a server-side field error inline.
class AppTextField extends StatefulWidget {
  const AppTextField({
    super.key,
    required this.label,
    this.controller,
    this.hint,
    this.errorText,
    this.helperText,
    this.keyboardType,
    this.textInputAction,
    this.obscure = false,
    this.autofillHints,
    this.validator,
    this.onSubmitted,
    this.onChanged,
    this.enabled = true,
    this.autofocus = false,
    this.inputFormatters,
    this.prefixIcon,
    this.textCapitalization = TextCapitalization.none,
    this.maxLength,
    this.maxLines = 1,
    this.minLines,
    this.suffixText,
    this.focusNode,
  });

  final String label;
  final TextEditingController? controller;
  final String? hint;
  final String? errorText;
  final String? helperText;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final bool obscure;
  final Iterable<String>? autofillHints;
  final FormFieldValidator<String>? validator;
  final ValueChanged<String>? onSubmitted;
  final ValueChanged<String>? onChanged;
  final bool enabled;
  final bool autofocus;
  final List<TextInputFormatter>? inputFormatters;
  final IconData? prefixIcon;
  final TextCapitalization textCapitalization;
  final int? maxLength;

  /// >1 for notes fields (grows with content up to this many lines).
  final int maxLines;
  final int? minLines;

  /// Unit adornment, e.g. "in" / "cm" on measurement inputs.
  final String? suffixText;
  final FocusNode? focusNode;

  @override
  State<AppTextField> createState() => _AppTextFieldState();
}

class _AppTextFieldState extends State<AppTextField> {
  late bool _hidden = widget.obscure;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 2, bottom: 6),
          child: Text(widget.label, style: AppText.labelMd.copyWith(color: AppColors.onSurfaceVariant)),
        ),
        TextFormField(
          controller: widget.controller,
          enabled: widget.enabled,
          autofocus: widget.autofocus,
          obscureText: _hidden,
          keyboardType: widget.keyboardType,
          textInputAction: widget.textInputAction,
          autofillHints: widget.autofillHints,
          validator: widget.validator,
          onFieldSubmitted: widget.onSubmitted,
          onChanged: widget.onChanged,
          inputFormatters: widget.inputFormatters,
          textCapitalization: widget.textCapitalization,
          maxLength: widget.maxLength,
          maxLines: widget.obscure ? 1 : widget.maxLines,
          minLines: widget.minLines,
          focusNode: widget.focusNode,
          style: AppText.bodyLg,
          cursorColor: AppColors.secondary,
          decoration: InputDecoration(
            hintText: widget.hint,
            errorText: widget.errorText,
            helperText: widget.helperText,
            helperStyle: AppText.bodySm.copyWith(color: AppColors.onSurfaceVariant),
            helperMaxLines: 3,
            counterText: '',
            suffixText: widget.suffixText,
            suffixStyle: AppText.labelSm.copyWith(color: AppColors.onSurfaceVariant),
            errorMaxLines: 3,
            prefixIcon: widget.prefixIcon == null ? null : Icon(widget.prefixIcon, size: 20, color: AppColors.onSurfaceVariant),
            suffixIcon: widget.obscure
                ? IconButton(
                    tooltip: _hidden ? 'Show password' : 'Hide password',
                    onPressed: () => setState(() => _hidden = !_hidden),
                    icon: Icon(_hidden ? Symbols.visibility : Symbols.visibility_off, size: 20, color: AppColors.onSurfaceVariant),
                  )
                : null,
          ),
        ),
      ],
    );
  }
}

/// Inline banner for form-level errors (soft rose) or notices (soft blue).
class FormBanner extends StatelessWidget {
  const FormBanner({super.key, required this.message, this.isError = true});

  final String message;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final fg = isError ? AppColors.onErrorContainer : AppColors.onSecondaryFixedVariant;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.md, vertical: AppSpace.sm + 2),
      decoration: BoxDecoration(color: isError ? AppColors.errorContainer : AppColors.secondaryFixed, borderRadius: AppRadius.control),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(isError ? Symbols.error : Symbols.info, size: 18, color: fg),
          const SizedBox(width: AppSpace.sm),
          Expanded(child: Text(message, style: AppText.bodyMd.copyWith(color: fg))),
        ],
      ),
    );
  }
}
