import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../core/widgets/feedback.dart';
import '../../../core/widgets/filter_pills.dart';
import '../../../core/widgets/gap.dart';
import '../../../core/widgets/state_views.dart';
import '../../jobs/application/job_providers.dart';
import '../../jobs/domain/job.dart';
import '../../sync/domain/config_bundle.dart';
import '../application/inventory_providers.dart';
import '../domain/inventory.dart';
import 'inventory_widgets.dart';

/// Records one stock change for a material. Returns true when saved.
Future<bool?> showStockSheet(
  BuildContext context, {
  required String itemId,
  TransactionType type = TransactionType.purchase,
  String? jobId,
  double? quantity,
}) =>
    showModalBottomSheet<bool>(
      context: context,
      useRootNavigator: true, // above the bottom navigation and timer bar
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _StockSheet(itemId: itemId, initialType: type, initialJobId: jobId, initialQuantity: quantity),
    );

/// The actions offered in the sheet (an opening balance is entered with a new material).
const _types = [TransactionType.purchase, TransactionType.usage, TransactionType.returned, TransactionType.writeOff, TransactionType.adjustment];

/// Quantity input: digits and one decimal point.
final quantityFormatters = [FilteringTextInputFormatter.allow(RegExp(r'^\d*[.,]?\d{0,3}'))];

double? parseQuantity(String text) => double.tryParse(text.trim().replaceAll(',', '.'));

class _StockSheet extends ConsumerStatefulWidget {
  const _StockSheet({required this.itemId, required this.initialType, this.initialJobId, this.initialQuantity});

  final String itemId;
  final TransactionType initialType;
  final String? initialJobId;
  final double? initialQuantity;

  @override
  ConsumerState<_StockSheet> createState() => _StockSheetState();
}

class _StockSheetState extends ConsumerState<_StockSheet> {
  late TransactionType _type = widget.initialType;
  late String? _jobId = widget.initialJobId;
  late final _quantity = TextEditingController(text: widget.initialQuantity == null ? '' : StockRules.number(widget.initialQuantity!));
  final _cost = TextEditingController();
  final _reference = TextEditingController();
  final _note = TextEditingController();
  Map<String, String> _errors = const {};
  bool _saving = false;
  bool _costFilled = false;

  @override
  void dispose() {
    _quantity.dispose();
    _cost.dispose();
    _reference.dispose();
    _note.dispose();
    super.dispose();
  }

  void _setType(TransactionType type, InventoryItem item) {
    setState(() {
      _type = type;
      _errors = const {};
      if (type == TransactionType.adjustment) _quantity.text = StockRules.number(item.quantityOnHand < 0 ? 0 : item.quantityOnHand);
    });
  }

  Future<void> _save(InventoryItem item) async {
    final quantity = parseQuantity(_quantity.text);
    final field = _type == TransactionType.adjustment ? 'counted_quantity' : 'quantity';
    if (quantity == null) {
      setState(() => _errors = {field: _type == TransactionType.adjustment ? 'Enter the quantity you counted.' : 'Enter the quantity.'});
      return;
    }
    setState(() {
      _saving = true;
      _errors = const {};
    });
    try {
      await ref.read(inventoryApiProvider).record(
            item,
            _type,
            quantity,
            jobId: _type.takesJob ? _jobId : null,
            unitCost: _type == TransactionType.purchase ? parseQuantity(_cost.text) : null,
            reference: _reference.text,
            note: _note.text,
          );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on ValidationException catch (e) {
      if (!mounted) return;
      final errors = {for (final entry in e.fieldErrors.entries) entry.key: entry.value.first};
      setState(() => _errors = errors.isEmpty ? {field: e.message} : errors);
    } on ApiException catch (e) {
      if (mounted) showAppSnack(context, e.message, isError: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final item = ref.watch(inventoryItemProvider(widget.itemId)).value;
    if (item == null) return const SizedBox(height: 240, child: LoadingView());
    if (!_costFilled && item.unitCost != null) {
      _cost.text = item.unitCost!.toStringAsFixed(2);
      _costFilled = true;
    }
    final counting = _type == TransactionType.adjustment;
    final quantity = parseQuantity(_quantity.text);
    final after = quantity == null
        ? null
        : counting
            ? quantity
            : StockRules.round(item.quantityOnHand + (StockRules.reductions.contains(_type.api) ? -quantity : quantity));
    final job = _jobId == null ? null : ref.watch(jobProvider(_jobId!)).value;

    return Padding(
      padding: EdgeInsets.fromLTRB(AppSpace.margin, 0, AppSpace.margin, AppSpace.lg + MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(_type.action, style: AppText.headlineMd),
          Text(item.name, style: AppText.bodyMd.copyWith(color: AppColors.onSurfaceVariant), maxLines: 1, overflow: TextOverflow.ellipsis),
          Gap.md,
          FilterPills(labels: [for (final t in _types) t.action], selected: _types.indexOf(_type), onChanged: (i) => _setType(_types[i], item)),
          Gap.lg,
          InsetTile(
            child: Row(children: [
              Expanded(child: Text('In stock now', style: AppText.bodySm.copyWith(color: AppColors.onSurfaceVariant))),
              Text(item.onHandLabel, style: AppText.labelMd.copyWith(color: item.quantityOnHand < 0 ? AppColors.error : AppColors.onSurface)),
              if (after != null) ...[
                const Padding(padding: EdgeInsets.symmetric(horizontal: 6), child: Icon(Symbols.arrow_forward, size: 14, color: AppColors.outline)),
                Text(item.format(after), style: AppText.labelMd.copyWith(color: after < 0 ? AppColors.error : AppColors.secondary)),
              ],
            ]),
          ),
          Gap.md,
          AppTextField(
            label: counting ? 'Counted on the shelf (${StockUnits.labels[item.unit] ?? item.unit})' : 'Quantity (${StockUnits.labels[item.unit] ?? item.unit})',
            controller: _quantity,
            autofocus: true,
            keyboardType: TextInputType.numberWithOptions(decimal: !item.isCounted),
            inputFormatters: quantityFormatters,
            errorText: _errors['quantity'] ?? _errors['counted_quantity'],
            helperText: counting ? 'The difference is recorded as a stock-count correction.' : null,
            onChanged: (_) => setState(() {}),
          ),
          if (_type.takesJob) ...[
            Gap.md,
            Text('For job', style: AppText.labelMd),
            Gap.xs,
            _JobTile(job: job, onTap: () async {
              final picked = await pickJob(context, selected: _jobId);
              if (picked != null && mounted) setState(() => _jobId = picked.isEmpty ? null : picked);
            }),
            if (_errors['job_id'] != null) Padding(padding: const EdgeInsets.only(top: 4), child: Text(_errors['job_id']!, style: AppText.bodySm.copyWith(color: AppColors.error))),
          ],
          if (_type == TransactionType.purchase) ...[
            Gap.md,
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: AppTextField(
                  label: 'Unit cost (optional)',
                  controller: _cost,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*[.,]?\d{0,2}'))],
                  errorText: _errors['unit_cost'],
                ),
              ),
              Gap.md,
              Expanded(child: AppTextField(label: 'Invoice / ref.', controller: _reference, maxLength: 80, errorText: _errors['reference'])),
            ]),
          ],
          Gap.md,
          AppTextField(
            label: _type == TransactionType.writeOff ? 'Reason' : 'Note (optional)',
            hint: _type == TransactionType.writeOff ? 'e.g. Moth damage' : null,
            controller: _note,
            maxLength: 255,
            textCapitalization: TextCapitalization.sentences,
            errorText: _errors['note'],
          ),
          Gap.lg,
          AppButton(
            label: _type == TransactionType.adjustment ? 'Save count' : 'Save',
            expand: true,
            loading: _saving,
            variant: _type == TransactionType.writeOff ? AppButtonVariant.danger : AppButtonVariant.primary,
            onPressed: () => _save(item),
          ),
        ]),
      ),
    );
  }
}

class _JobTile extends StatelessWidget {
  const _JobTile({required this.job, required this.onTap});

  final Job? job;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surfaceContainerLow,
      borderRadius: AppRadius.control,
      child: InkWell(
        borderRadius: AppRadius.control,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Row(children: [
            const Icon(Symbols.content_cut, size: 18, color: AppColors.onSurfaceVariant),
            Gap.sm,
            Expanded(
              child: Text(
                job == null ? 'Not for a particular job' : '#${job!.jobNumber ?? 'New'} · ${job!.customerName} · ${job!.title}',
                style: AppText.bodyMd.copyWith(color: job == null ? AppColors.onSurfaceVariant : AppColors.onSurface),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const Icon(Symbols.expand_more, size: 20, color: AppColors.outline),
          ]),
        ),
      ),
    );
  }
}

/// Picks one of the open jobs. Returns its id, '' for "no job", or null when dismissed.
Future<String?> pickJob(BuildContext context, {String? selected}) => showModalBottomSheet<String>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _JobPicker(selected: selected),
    );

class _JobPicker extends ConsumerStatefulWidget {
  const _JobPicker({this.selected});

  final String? selected;

  @override
  ConsumerState<_JobPicker> createState() => _JobPickerState();
}

class _JobPickerState extends ConsumerState<_JobPicker> {
  String _text = '';

  @override
  Widget build(BuildContext context) {
    final jobs = ref.watch(jobListProvider(JobQuery(filter: 'open', text: _text))).value?.items ?? const <Job>[];
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.7,
      child: Padding(
        padding: EdgeInsets.fromLTRB(AppSpace.margin, 0, AppSpace.margin, MediaQuery.viewInsetsOf(context).bottom),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Which job is it for?', style: AppText.headlineMd),
          Gap.md,
          AppSearchField(hint: 'Search customer, garment or job…', onChanged: (t) => setState(() => _text = t.trim())),
          Gap.sm,
          Expanded(
            child: ListView(children: [
              _PickRow(icon: Symbols.block, title: 'Not for a particular job', selected: widget.selected == null, onTap: () => Navigator.of(context).pop('')),
              for (final job in jobs)
                _PickRow(
                  icon: Symbols.content_cut,
                  title: '#${job.jobNumber ?? 'New'} · ${job.customerName}',
                  subtitle: job.title,
                  selected: job.id == widget.selected,
                  onTap: () => Navigator.of(context).pop(job.id),
                ),
            ]),
          ),
        ]),
      ),
    );
  }
}

/// Picks an active material. Returns its id, or null when dismissed.
Future<String?> pickMaterial(BuildContext context) => showModalBottomSheet<String>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => const _MaterialPicker(),
    );

class _MaterialPicker extends ConsumerStatefulWidget {
  const _MaterialPicker();

  @override
  ConsumerState<_MaterialPicker> createState() => _MaterialPickerState();
}

class _MaterialPickerState extends ConsumerState<_MaterialPicker> {
  String _text = '';

  @override
  Widget build(BuildContext context) {
    final q = _text.toLowerCase();
    final items = (ref.watch(inventoryItemsProvider(false)).value ?? const <InventoryItem>[])
        .where((i) => q.isEmpty || i.name.toLowerCase().contains(q) || (i.sku?.toLowerCase().contains(q) ?? false) || (i.categoryName?.toLowerCase().contains(q) ?? false))
        .toList();
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.7,
      child: Padding(
        padding: EdgeInsets.fromLTRB(AppSpace.margin, 0, AppSpace.margin, MediaQuery.viewInsetsOf(context).bottom),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Which material?', style: AppText.headlineMd),
          Gap.md,
          AppSearchField(hint: 'Search material, code or category…', onChanged: (t) => setState(() => _text = t.trim())),
          Gap.sm,
          Expanded(
            child: items.isEmpty
                ? const MessageView(icon: Symbols.inventory_2, title: 'No materials', message: 'Add materials in Inventory first.')
                : ListView(children: [
                    for (final item in items)
                      _PickRow(
                        icon: Symbols.inventory_2,
                        title: item.name,
                        subtitle: '${item.categoryName ?? ''} · ${item.onHandLabel} in stock',
                        trailing: item.status.needsAttention ? Icon(Symbols.warning, size: 18, color: stockTone(item.status).dot) : null,
                        onTap: () => Navigator.of(context).pop(item.id),
                      ),
                  ]),
          ),
        ]),
      ),
    );
  }
}

class _PickRow extends StatelessWidget {
  const _PickRow({required this.icon, required this.title, required this.onTap, this.subtitle, this.selected = false, this.trailing});

  final IconData icon;
  final String title;
  final String? subtitle;
  final bool selected;
  final Widget? trailing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: AppRadius.control,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
        child: Row(children: [
          Icon(icon, size: 20, color: selected ? AppColors.secondary : AppColors.onSurfaceVariant),
          Gap.md,
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: AppText.labelMd.copyWith(color: selected ? AppColors.secondary : AppColors.onSurface), maxLines: 1, overflow: TextOverflow.ellipsis),
              if (subtitle != null) Text(subtitle!, style: AppText.bodySm.copyWith(color: AppColors.onSurfaceVariant), maxLines: 1, overflow: TextOverflow.ellipsis),
            ]),
          ),
          ?trailing,
          if (selected) const Icon(Symbols.check, size: 18, color: AppColors.secondary),
        ]),
      ),
    );
  }
}
