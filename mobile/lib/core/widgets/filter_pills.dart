import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_text.dart';

/// Horizontally scrolling filter pills ("All (14) · Active (9) · Pending (3)") — selected in navy.
class FilterPills extends StatelessWidget {
  const FilterPills({super.key, required this.labels, required this.selected, required this.onChanged});

  final List<String> labels;
  final int selected;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 36,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        clipBehavior: Clip.none,
        itemCount: labels.length,
        separatorBuilder: (_, _) => const SizedBox(width: AppSpace.sm),
        itemBuilder: (context, i) {
          final active = i == selected;
          return Semantics(
            selected: active,
            button: true,
            child: GestureDetector(
              onTap: () => onChanged(i),
              child: AnimatedContainer(
                duration: AppMotion.fast,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: active ? AppColors.primaryContainer : AppColors.surfaceContainerLowest,
                  borderRadius: AppRadius.full,
                  boxShadow: AppShadows.card,
                ),
                child: Text(labels[i], style: AppText.labelMd.copyWith(color: active ? AppColors.onPrimary : AppColors.onSurfaceVariant)),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// White search bar with leading search icon (jobs list design) and a clear button.
class AppSearchField extends StatefulWidget {
  const AppSearchField({super.key, required this.hint, required this.onChanged, this.initialValue = ''});

  final String hint;
  final ValueChanged<String> onChanged;
  final String initialValue;

  @override
  State<AppSearchField> createState() => _AppSearchFieldState();
}

class _AppSearchFieldState extends State<AppSearchField> {
  late final _controller = TextEditingController(text: widget.initialValue);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(color: AppColors.surfaceContainerLowest, borderRadius: AppRadius.control, boxShadow: AppShadows.card),
      child: TextField(
        controller: _controller,
        onChanged: (v) {
          setState(() {});
          widget.onChanged(v);
        },
        textInputAction: TextInputAction.search,
        style: AppText.bodyLg,
        decoration: InputDecoration(
          filled: true,
          fillColor: AppColors.surfaceContainerLowest,
          hintText: widget.hint,
          hintStyle: AppText.bodyMd.copyWith(color: AppColors.onSurfaceVariant),
          prefixIcon: const Icon(Symbols.search, size: 20, color: AppColors.onSurfaceVariant),
          suffixIcon: _controller.text.isEmpty
              ? null
              : IconButton(
                  tooltip: 'Clear',
                  icon: const Icon(Symbols.close, size: 18, color: AppColors.onSurfaceVariant),
                  onPressed: () {
                    _controller.clear();
                    setState(() {});
                    widget.onChanged('');
                  },
                ),
          contentPadding: const EdgeInsets.symmetric(vertical: 12),
        ),
      ),
    );
  }
}
