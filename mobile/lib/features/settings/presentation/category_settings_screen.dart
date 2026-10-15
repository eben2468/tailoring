import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../app/section_scaffold.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/feedback.dart';
import '../../../core/widgets/gap.dart';
import '../../../core/widgets/menu_row.dart';
import '../../../core/widgets/state_views.dart';
import '../../inventory/application/inventory_providers.dart';
import '../../jobs/presentation/job_sheets.dart';
import '../../tools/application/tool_providers.dart';
import '../domain/config_category.dart';

/// Which configurable category list a settings screen edits.
enum CategoryKind {
  materials('Material categories', 'Group materials so the inventory list and its filters stay tidy.', 'material', 'e.g. Shoulder pads'),
  tools('Tool categories', 'Group tools and machines so the equipment roster stays tidy.', 'tool', 'e.g. Embroidery');

  const CategoryKind(this.title, this.intro, this.itemWord, this.hint);

  final String title;
  final String intro;
  final String itemWord;
  final String hint;
}

CategorySettings _api(WidgetRef ref, CategoryKind kind) => switch (kind) {
      CategoryKind.materials => ref.read(inventoryApiProvider),
      CategoryKind.tools => ref.read(toolsApiProvider),
    };

/// Categories with their counts, from the server (online only).
final categorySettingsProvider = FutureProvider.autoDispose.family<List<ConfigCategory>, CategoryKind>((ref, kind) => switch (kind) {
      CategoryKind.materials => ref.watch(inventoryApiProvider).categories(),
      CategoryKind.tools => ref.watch(toolsApiProvider).categories(),
    });

/// Material or tool categories (configuration): add, rename, hide. Changed online; devices download them
/// with the configuration. A hidden category keeps its items but is not offered for new ones.
class CategorySettingsScreen extends ConsumerWidget {
  const CategorySettingsScreen({super.key, required this.kind});

  final CategoryKind kind;

  Future<void> _run(BuildContext context, WidgetRef ref, Future<void> Function() action, String done) async {
    try {
      await action();
      ref.invalidate(categorySettingsProvider(kind));
      if (context.mounted) showAppSnack(context, done);
    } on ValidationException catch (e) {
      if (context.mounted) showAppSnack(context, e.fieldErrors.values.firstOrNull?.first ?? e.message, isError: true);
    } on ApiException catch (e) {
      if (context.mounted) showAppSnack(context, e.message, isError: true);
    }
  }

  Future<void> _add(BuildContext context, WidgetRef ref) async {
    final name = await askText(context, title: 'New category', label: 'Name', hint: kind.hint, confirmLabel: 'Add category', maxLength: 80);
    if (name == null || !context.mounted) return;
    await _run(context, ref, () => _api(ref, kind).createCategory(name), 'Category added.');
  }

  Future<void> _edit(BuildContext context, WidgetRef ref, ConfigCategory c) async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      useRootNavigator: true,
      useSafeArea: true,
      builder: (context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(c.name, style: AppText.headlineMd),
          Gap.lg,
          AppButton(label: 'Rename', icon: Symbols.edit, variant: AppButtonVariant.outline, expand: true, onPressed: () => Navigator.of(context).pop('rename')),
          Gap.sm,
          AppButton(
            label: c.isActive ? 'Hide from new ${kind.itemWord}s' : 'Show again',
            icon: c.isActive ? Symbols.visibility_off : Symbols.visibility,
            variant: AppButtonVariant.outline,
            expand: true,
            onPressed: () => Navigator.of(context).pop('toggle'),
          ),
        ]),
      ),
    );
    if (choice == null || !context.mounted) return;
    final api = _api(ref, kind);
    if (choice == 'toggle') {
      await _run(context, ref, () => api.updateCategory(c.id, isActive: !c.isActive), c.isActive ? 'Category hidden.' : 'Category shown.');
      return;
    }
    final name = await askText(context, title: 'Rename category', label: 'Name', initial: c.name, confirmLabel: 'Save', maxLength: 80);
    if (name == null || name == c.name || !context.mounted) return;
    await _run(context, ref, () => api.updateCategory(c.id, name: name), 'Category renamed.');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = ref.watch(categorySettingsProvider(kind));
    return DetailScaffold(
      title: kind.title,
      body: switch (list) {
        AsyncData(:final value) => ListView(padding: belowHeader(context), children: [
            Row(children: [
              Expanded(child: Text(kind.intro, style: AppText.bodyMd.copyWith(color: AppColors.onSurfaceVariant))),
              Gap.sm,
              AppButton(label: 'Category', icon: Symbols.add, size: AppButtonSize.medium, onPressed: () => _add(context, ref)),
            ]),
            Gap.lg,
            MenuGroup(children: [
              for (final c in value)
                MenuRow(
                  icon: c.isActive ? Symbols.category : Symbols.visibility_off,
                  title: c.name,
                  subtitle: [
                    '${c.itemCount ?? 0} ${kind.itemWord}${c.itemCount == 1 ? '' : 's'}',
                    if (!c.isActive) 'hidden',
                  ].join(' · '),
                  onTap: () => _edit(context, ref, c),
                ),
            ]),
          ]),
        AsyncError(:final error) => ErrorView(error: error, onRetry: () => ref.invalidate(categorySettingsProvider(kind))),
        _ => const LoadingView(),
      },
    );
  }
}
