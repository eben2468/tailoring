import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../app/routes.dart';
import '../../../app/section_scaffold.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../core/widgets/bottom_action_bar.dart';
import '../../../core/widgets/feedback.dart';
import '../../../core/widgets/filter_pills.dart';
import '../../../core/widgets/gap.dart';
import '../../../core/widgets/section_header.dart';
import '../../../core/widgets/state_views.dart';
import '../../settings/domain/config_category.dart';
import '../../sync/application/sync_providers.dart';
import '../application/tool_providers.dart';
import '../data/tools_api.dart';
import '../domain/tools.dart';
import 'tool_widgets.dart';

/// Register a tool or edit its details. Service dates follow from the cycle and the maintenance log.
class ToolFormScreen extends ConsumerWidget {
  const ToolFormScreen({super.key, this.toolId});

  final String? toolId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (toolId == null) return const _ToolForm();
    return switch (ref.watch(toolProvider(toolId!))) {
      AsyncData(:final value) => _ToolForm(existing: value),
      AsyncError(:final error) => DetailScaffold(title: 'Edit tool', body: ErrorView(error: error, onRetry: () => ref.invalidate(bootstrapProvider))),
      _ => const DetailScaffold(title: 'Edit tool', body: LoadingView()),
    };
  }
}

class _ToolForm extends ConsumerStatefulWidget {
  const _ToolForm({this.existing});

  final Tool? existing;

  @override
  ConsumerState<_ToolForm> createState() => _ToolFormState();
}

class _ToolFormState extends ConsumerState<_ToolForm> {
  Tool? get _tool => widget.existing;
  bool get _editing => _tool != null;

  late int? _categoryId = _tool?.categoryId;
  late ToolCondition _condition = _tool?.condition ?? ToolCondition.good;
  late ToolStatus _status = _tool?.status ?? ToolStatus.operational;
  late DateTime? _purchased = _tool?.purchaseDate;
  late final _name = TextEditingController(text: _tool?.name);
  late final _brand = TextEditingController(text: _tool?.brandModel);
  late final _serial = TextEditingController(text: _tool?.serialNumber);
  late final _location = TextEditingController(text: _tool?.storageLocation);
  late final _interval = TextEditingController(text: _tool?.intervalDays?.toString());
  late final _notes = TextEditingController(text: _tool?.notes);
  Map<String, String> _errors = const {};
  bool _saving = false;

  @override
  void dispose() {
    for (final c in [_name, _brand, _serial, _location, _interval, _notes]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final errors = <String, String>{
      if (_name.text.trim().length < 2) 'tool_name': 'Give the tool a name.',
      if (_categoryId == null) 'category_id': 'Choose a category.',
    };
    if (errors.isNotEmpty) {
      setState(() => _errors = errors);
      return;
    }
    final draft = ToolDraft(
      categoryId: _categoryId!,
      name: _name.text,
      brandModel: _brand.text,
      serialNumber: _serial.text,
      purchaseDate: _purchased,
      condition: _condition,
      status: _status,
      storageLocation: _location.text,
      intervalDays: int.tryParse(_interval.text.trim()),
      notes: _notes.text,
    );
    setState(() {
      _saving = true;
      _errors = const {};
    });
    try {
      final api = ref.read(toolsApiProvider);
      if (_editing) {
        await api.update(_tool!, draft);
        if (!mounted) return;
        showAppSnack(context, 'Tool updated.');
        context.pop();
      } else {
        final created = await api.create(draft);
        if (!mounted) return;
        showAppSnack(context, '${created.name} registered.');
        context.pushReplacement(Routes.tool(created.id));
      }
    } on ValidationException catch (e) {
      if (mounted) setState(() => _errors = {for (final entry in e.fieldErrors.entries) entry.key: entry.value.first});
    } on ApiException catch (e) {
      if (mounted) showAppSnack(context, e.message, isError: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _error(String key) =>
      _errors[key] == null ? const SizedBox.shrink() : Padding(padding: const EdgeInsets.only(top: 4), child: Text(_errors[key]!, style: AppText.bodySm.copyWith(color: AppColors.error)));

  @override
  Widget build(BuildContext context) {
    final categories = (ref.watch(toolCategoriesProvider).value ?? const <ConfigCategory>[]).where((c) => c.isActive || c.id == _categoryId).toList();
    final today = DateTime.now();

    return DetailScaffold(
      title: _editing ? 'Edit tool' : 'Register tool',
      bottomBar: BottomActionBar(
        child: AppButton(label: _editing ? 'Save changes' : 'Register tool', icon: Symbols.precision_manufacturing, expand: true, loading: _saving, onPressed: _save),
      ),
      body: ListView(padding: belowHeader(context), children: [
        Text(_editing ? _tool!.name : 'New equipment', style: AppText.headlineLg),
        Gap.lg,
        AppCard(
          padding: const EdgeInsets.all(AppSpace.lg),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            AppTextField(label: 'Name', hint: 'e.g. Lockstitch Machine #01', controller: _name, maxLength: 150, textCapitalization: TextCapitalization.words, errorText: _errors['tool_name']),
            Gap.md,
            Kicker('Category', trailing: AppButton(label: 'Manage', variant: AppButtonVariant.text, size: AppButtonSize.small, onPressed: () => context.push(Routes.toolCategories))),
            Gap.sm,
            if (categories.isEmpty)
              Text('No categories yet. Add one under Manage.', style: AppText.bodySm.copyWith(color: AppColors.onSurfaceVariant))
            else
              FilterPills(labels: [for (final c in categories) c.name], selected: categories.indexWhere((c) => c.id == _categoryId), onChanged: (i) => setState(() => _categoryId = categories[i].id)),
            _error('category_id'),
            Gap.md,
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(child: AppTextField(label: 'Brand / model', hint: 'Juki DDL-9000C', controller: _brand, maxLength: 120, errorText: _errors['brand_model'])),
              Gap.md,
              Expanded(child: AppTextField(label: 'Serial no.', controller: _serial, maxLength: 80, textCapitalization: TextCapitalization.characters, errorText: _errors['serial_number'])),
            ]),
            Gap.md,
            AppTextField(label: 'Location', hint: 'e.g. Bench 01', controller: _location, maxLength: 80, errorText: _errors['storage_location']),
            Gap.md,
            Text('Purchase date (optional)', style: AppText.labelMd),
            Gap.xs,
            Material(
              color: AppColors.surfaceContainerLow,
              borderRadius: AppRadius.control,
              child: InkWell(
                borderRadius: AppRadius.control,
                onTap: () async {
                  final picked = await showDatePicker(context: context, initialDate: _purchased ?? today, firstDate: DateTime(1970), lastDate: today, helpText: 'Purchase date');
                  if (picked != null) setState(() => _purchased = picked);
                },
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(children: [
                    const Icon(Symbols.event, size: 18, color: AppColors.onSurfaceVariant),
                    Gap.sm,
                    Expanded(child: Text(_purchased == null ? 'Not set' : toolDate(_purchased!), style: AppText.bodyMd.copyWith(color: _purchased == null ? AppColors.onSurfaceVariant : AppColors.onSurface))),
                    if (_purchased != null) GestureDetector(onTap: () => setState(() => _purchased = null), child: const Icon(Symbols.close, size: 18, color: AppColors.outline)),
                  ]),
                ),
              ),
            ),
            _error('purchase_date'),
          ]),
        ),
        Gap.md,
        AppCard(
          padding: const EdgeInsets.all(AppSpace.lg),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Kicker('Service cycle'),
            Gap.sm,
            AppTextField(
              label: 'Service every (days)',
              hint: 'e.g. 60',
              controller: _interval,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(4)],
              errorText: _errors['maintenance_interval_days'],
              helperText: 'Leave empty if it needs no regular service. The next date counts from the last service (or the purchase date).',
            ),
            Gap.md,
            const Kicker('Condition'),
            Gap.sm,
            FilterPills(labels: [for (final c in ToolCondition.values) c.label], selected: ToolCondition.values.indexOf(_condition), onChanged: (i) => setState(() => _condition = ToolCondition.values[i])),
            Gap.md,
            const Kicker('Status'),
            Gap.sm,
            FilterPills(labels: [for (final s in ToolStatus.values) s.choiceLabel], selected: ToolStatus.values.indexOf(_status), onChanged: (i) => setState(() => _status = ToolStatus.values[i])),
            Gap.md,
            AppTextField(label: 'Notes', controller: _notes, maxLines: 3, minLines: 2, maxLength: 5000, textCapitalization: TextCapitalization.sentences, errorText: _errors['notes']),
          ]),
        ),
      ]),
    );
  }
}
