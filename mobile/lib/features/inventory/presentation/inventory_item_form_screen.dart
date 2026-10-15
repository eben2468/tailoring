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
import '../../auth/application/session_controller.dart';
import '../../sync/application/sync_providers.dart';
import '../../sync/domain/config_bundle.dart';
import '../application/inventory_providers.dart';
import '../data/inventory_api.dart';
import '../domain/inventory.dart';
import 'stock_sheet.dart';

/// Add a material (with its opening stock) or edit its details. Stock itself only changes through the ledger.
class InventoryItemFormScreen extends ConsumerWidget {
  const InventoryItemFormScreen({super.key, this.itemId});

  final String? itemId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (itemId == null) return const _ItemForm();
    return switch (ref.watch(inventoryItemProvider(itemId!))) {
      AsyncData(:final value) => _ItemForm(existing: value),
      AsyncError(:final error) => DetailScaffold(title: 'Edit material', body: ErrorView(error: error, onRetry: () => ref.invalidate(bootstrapProvider))),
      _ => const DetailScaffold(title: 'Edit material', body: LoadingView()),
    };
  }
}

class _ItemForm extends ConsumerStatefulWidget {
  const _ItemForm({this.existing});

  final InventoryItem? existing;

  @override
  ConsumerState<_ItemForm> createState() => _ItemFormState();
}

class _ItemFormState extends ConsumerState<_ItemForm> {
  InventoryItem? get _item => widget.existing;
  bool get _editing => _item != null;

  late int? _categoryId = _item?.categoryId;
  late String _unit = _item?.unit ?? 'm';
  late final _name = TextEditingController(text: _item?.name);
  late final _sku = TextEditingController(text: _item?.sku);
  late final _description = TextEditingController(text: _item?.description);
  final _opening = TextEditingController();
  late final _min = TextEditingController(text: _item == null ? '' : StockRules.number(_item!.minStockLevel));
  late final _reorder = TextEditingController(text: _item?.reorderQuantity == null ? '' : StockRules.number(_item!.reorderQuantity!));
  late final _cost = TextEditingController(text: _item?.unitCost?.toStringAsFixed(2));
  late final _location = TextEditingController(text: _item?.storageLocation);
  late final _supplier = TextEditingController(text: _item?.supplierName);
  late final _contact = TextEditingController(text: _item?.supplierContact);
  late final _notes = TextEditingController(text: _item?.notes);
  Map<String, String> _errors = const {};
  bool _saving = false;

  @override
  void dispose() {
    for (final c in [_name, _sku, _description, _opening, _min, _reorder, _cost, _location, _supplier, _contact, _notes]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final errors = <String, String>{
      if (_name.text.trim().length < 2) 'item_name': 'Give the material a name.',
      if (_categoryId == null) 'category_id': 'Choose a category.',
    };
    if (errors.isNotEmpty) {
      setState(() => _errors = errors);
      return;
    }
    final draft = InventoryItemDraft(
      categoryId: _categoryId!,
      name: _name.text,
      unit: _unit,
      sku: _sku.text,
      description: _description.text,
      minStockLevel: parseQuantity(_min.text),
      reorderQuantity: parseQuantity(_reorder.text),
      unitCost: parseQuantity(_cost.text),
      storageLocation: _location.text,
      supplierName: _supplier.text,
      supplierContact: _contact.text,
      notes: _notes.text,
    );
    setState(() {
      _saving = true;
      _errors = const {};
    });
    try {
      final api = ref.read(inventoryApiProvider);
      if (_editing) {
        await api.update(_item!, draft);
        if (!mounted) return;
        showAppSnack(context, 'Material updated.');
        context.pop();
      } else {
        final created = await api.create(draft, openingQuantity: parseQuantity(_opening.text) ?? 0);
        if (!mounted) return;
        showAppSnack(context, '${created.name} added.');
        context.pushReplacement(Routes.inventoryItem(created.id));
      }
    } on ValidationException catch (e) {
      if (mounted) setState(() => _errors = {for (final entry in e.fieldErrors.entries) entry.key: entry.value.first});
    } on ApiException catch (e) {
      if (mounted) showAppSnack(context, e.message, isError: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final categories = (ref.watch(inventoryCategoriesProvider).value ?? const <InventoryCategory>[]).where((c) => c.isActive || c.id == _categoryId).toList();
    final currency = ref.watch(sessionControllerProvider).value?.business.currency ?? '';
    final unitLocked = _editing && _item!.lastTransactionAt != null;
    final counted = StockRules.isCounted(_unit);
    final unitWord = StockRules.isCounted(_unit) ? StockRules.unitName(_unit, 2) : _unit;
    final numberKeyboard = TextInputType.numberWithOptions(decimal: !counted);

    return DetailScaffold(
      title: _editing ? 'Edit material' : 'New material',
      bottomBar: BottomActionBar(
        child: AppButton(label: _editing ? 'Save changes' : 'Add material', icon: Symbols.inventory_2, expand: true, loading: _saving, onPressed: _save),
      ),
      body: ListView(padding: belowHeader(context), children: [
        Text(_editing ? _item!.name : 'Add to the atelier', style: AppText.headlineLg),
        Gap.lg,
        AppCard(
          padding: const EdgeInsets.all(AppSpace.lg),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            AppTextField(label: 'Name', hint: 'e.g. Super 150s Wool — Navy', controller: _name, maxLength: 150, textCapitalization: TextCapitalization.words, errorText: _errors['item_name']),
            Gap.md,
            Kicker('Category', trailing: AppButton(label: 'Manage', variant: AppButtonVariant.text, size: AppButtonSize.small, onPressed: () => context.push(Routes.inventoryCategories))),
            Gap.sm,
            if (categories.isEmpty)
              Text('No categories yet. Add one under Manage.', style: AppText.bodySm.copyWith(color: AppColors.onSurfaceVariant))
            else
              FilterPills(
                labels: [for (final c in categories) c.name],
                selected: categories.indexWhere((c) => c.id == _categoryId),
                onChanged: (i) => setState(() => _categoryId = categories[i].id),
              ),
            if (_errors['category_id'] != null) Padding(padding: const EdgeInsets.only(top: 4), child: Text(_errors['category_id']!, style: AppText.bodySm.copyWith(color: AppColors.error))),
            Gap.md,
            const Kicker('Counted in'),
            Gap.sm,
            if (unitLocked)
              Text('${StockUnits.labels[_unit]} — fixed once stock has been recorded.', style: AppText.bodyMd.copyWith(color: AppColors.onSurfaceVariant))
            else
              FilterPills(
                labels: [for (final u in StockUnits.all) StockUnits.labels[u]!],
                selected: StockUnits.all.indexOf(_unit),
                onChanged: (i) => setState(() => _unit = StockUnits.all[i]),
              ),
            if (_errors['unit'] != null) Padding(padding: const EdgeInsets.only(top: 4), child: Text(_errors['unit']!, style: AppText.bodySm.copyWith(color: AppColors.error))),
            Gap.md,
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(child: AppTextField(label: 'Code (optional)', hint: 'FAB-0001', controller: _sku, maxLength: 60, textCapitalization: TextCapitalization.characters, errorText: _errors['sku'])),
              Gap.md,
              Expanded(child: AppTextField(label: 'Shelf / location', hint: 'Rack B-04', controller: _location, maxLength: 80, errorText: _errors['storage_location'])),
            ]),
            Gap.md,
            AppTextField(label: 'Description (optional)', hint: 'e.g. Midnight navy herringbone', controller: _description, maxLength: 255, textCapitalization: TextCapitalization.sentences, errorText: _errors['description']),
          ]),
        ),
        Gap.md,
        AppCard(
          padding: const EdgeInsets.all(AppSpace.lg),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Kicker('Stock levels'),
            Gap.sm,
            if (!_editing) ...[
              AppTextField(
                label: 'In stock now ($unitWord)',
                hint: '0',
                controller: _opening,
                keyboardType: numberKeyboard,
                inputFormatters: quantityFormatters,
                errorText: _errors['opening_quantity'],
                helperText: 'Recorded as the opening balance. Leave empty if you have none yet.',
              ),
              Gap.md,
            ],
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: AppTextField(
                  label: 'Minimum ($unitWord)',
                  controller: _min,
                  keyboardType: numberKeyboard,
                  inputFormatters: quantityFormatters,
                  errorText: _errors['min_stock_level'],
                  helperText: 'Alert at or below',
                ),
              ),
              Gap.md,
              Expanded(
                child: AppTextField(
                  label: 'Usual reorder ($unitWord)',
                  controller: _reorder,
                  keyboardType: numberKeyboard,
                  inputFormatters: quantityFormatters,
                  errorText: _errors['reorder_quantity'],
                  helperText: 'Pre-fills Restock',
                ),
              ),
            ]),
          ]),
        ),
        Gap.md,
        AppCard(
          padding: const EdgeInsets.all(AppSpace.lg),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Kicker('Supplier and cost (optional)'),
            Gap.sm,
            AppTextField(label: 'Supplier', controller: _supplier, maxLength: 150, textCapitalization: TextCapitalization.words, errorText: _errors['supplier_name']),
            Gap.md,
            AppTextField(label: 'Supplier phone or email', controller: _contact, maxLength: 150, keyboardType: TextInputType.emailAddress, errorText: _errors['supplier_contact']),
            Gap.md,
            AppTextField(
              label: 'Unit cost ($currency per $_unit)',
              controller: _cost,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*[.,]?\d{0,2}'))],
              errorText: _errors['unit_cost'],
            ),
            Gap.md,
            AppTextField(label: 'Notes', controller: _notes, maxLines: 3, minLines: 2, maxLength: 5000, textCapitalization: TextCapitalization.sentences, errorText: _errors['notes']),
          ]),
        ),
      ]),
    );
  }
}
