import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../app/routes.dart';
import '../../../app/section_scaffold.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/feedback.dart';
import '../../../core/widgets/gap.dart';
import '../../../core/widgets/header_icon_button.dart';
import '../../../core/widgets/section_header.dart';
import '../../../core/widgets/state_views.dart';
import '../../../core/widgets/status_pill.dart';
import '../../auth/application/session_controller.dart';
import '../../jobs/presentation/job_sheets.dart';
import '../../sync/application/sync_providers.dart';
import '../application/inventory_providers.dart';
import '../domain/inventory.dart';
import 'inventory_widgets.dart';
import 'stock_sheet.dart';

/// One material: stock with its minimum, stock actions, details and the stock ledger (void mistakes).
class InventoryItemScreen extends ConsumerWidget {
  const InventoryItemScreen({super.key, required this.itemId});

  final String itemId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final item = ref.watch(inventoryItemProvider(itemId));
    return switch (item) {
      AsyncData(:final value) => _ItemView(item: value),
      AsyncError(:final error) => DetailScaffold(title: 'Material', body: ErrorView(error: error, onRetry: () => ref.invalidate(bootstrapProvider))),
      _ => const DetailScaffold(title: 'Material', body: LoadingView()),
    };
  }
}

class _ItemView extends ConsumerWidget {
  const _ItemView({required this.item});

  final InventoryItem item;

  Future<void> _stock(BuildContext context, TransactionType type, {double? quantity}) async {
    final saved = await showStockSheet(context, itemId: item.id, type: type, quantity: quantity);
    if (saved == true && context.mounted) showAppSnack(context, '${type.label}: ${item.name}.');
  }

  Future<void> _archive(BuildContext context, WidgetRef ref) async {
    final archiving = !item.isArchived;
    if (archiving &&
        !await confirmAction(
          context,
          title: 'Archive ${item.name}?',
          message: 'It leaves the inventory list and alerts, and takes no new stock changes. Its history is kept, and you can restore it at any time.',
          confirmLabel: 'Archive',
        )) {
      return;
    }
    try {
      await ref.read(inventoryApiProvider).setArchived(item, archived: archiving);
      if (context.mounted) showAppSnack(context, archiving ? 'Material archived.' : 'Material restored.');
    } on ApiException catch (e) {
      if (context.mounted) showAppSnack(context, e.message, isError: true);
    }
  }

  Future<void> _ledgerTap(BuildContext context, WidgetRef ref, InventoryTransaction tx) async {
    if (tx.isVoided) return;
    final reason = await askText(
      context,
      title: 'Void this ${tx.type.label.toLowerCase()} entry?',
      label: 'Why is it wrong?',
      hint: 'e.g. Typed 20 instead of 2',
      confirmLabel: 'Void entry',
      destructive: true,
    );
    if (reason == null || !context.mounted) return;
    try {
      await ref.read(inventoryApiProvider).voidTransaction(tx, item.name, reason);
      if (context.mounted) showAppSnack(context, 'Entry voided. It no longer counts towards the stock.');
    } on ApiException catch (e) {
      if (context.mounted) showAppSnack(context, e.message, isError: true);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ledger = ref.watch(inventoryLedgerProvider(item.id)).value ?? const <InventoryTransaction>[];
    final currency = ref.watch(sessionControllerProvider).value?.business.currency ?? '';
    final low = item.status.needsAttention;

    return DetailScaffold(
      title: item.name,
      actions: [
        PopupMenuButton<String>(
          tooltip: 'More',
          padding: EdgeInsets.zero,
          shape: RoundedRectangleBorder(borderRadius: AppRadius.card),
          child: const HeaderIconButton(icon: Symbols.more_vert),
          onSelected: (v) => v == 'edit' ? context.push(Routes.inventoryEdit(item.id)) : _archive(context, ref),
          itemBuilder: (_) => [
            if (!item.isArchived) const PopupMenuItem(value: 'edit', child: Text('Edit details')),
            PopupMenuItem(value: 'archive', child: Text(item.isArchived ? 'Restore material' : 'Archive material')),
          ],
        ),
      ],
      body: ListView(padding: belowHeader(context), children: [
        if (item.isArchived) ...[
          AppCard(
            color: AppColors.surfaceContainerHigh,
            child: Row(children: [
              const Icon(Symbols.archive, size: 20, color: AppColors.onSurfaceVariant),
              Gap.sm,
              Expanded(child: Text('Archived. Restore it to record stock again.', style: AppText.bodyMd)),
              AppButton(label: 'Restore', size: AppButtonSize.small, variant: AppButtonVariant.outline, onPressed: () => _archive(context, ref)),
            ]),
          ),
          Gap.md,
        ],
        AppCard(
          padding: const EdgeInsets.all(AppSpace.lg),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              MaterialThumb(item: item),
              Gap.md,
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text([item.categoryName?.toUpperCase(), item.sku].whereType<String>().join('  •  '), style: AppText.overline, maxLines: 1, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 2),
                  Text(item.name, style: AppText.headlineMd),
                  if (item.description != null) Text(item.description!, style: AppText.bodySm.copyWith(color: AppColors.onSurfaceVariant)),
                ]),
              ),
              Gap.sm,
              StatusPill(label: item.status.label, tone: stockTone(item.status)),
            ]),
            Gap.lg,
            Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Expanded(
                child: Wrap(spacing: AppSpace.sm, crossAxisAlignment: WrapCrossAlignment.end, children: [
                  Text(item.onHandLabel, style: AppText.displayLgMobile.copyWith(color: item.quantityOnHand < 0 ? AppColors.error : AppColors.onSurface)),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 5),
                    child: Text('on hand', style: AppText.bodyMd.copyWith(color: AppColors.onSurfaceVariant)),
                  ),
                ]),
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 5),
                child: Text('Min: ${item.format(item.minStockLevel)}', style: AppText.labelMd.copyWith(color: low ? AppColors.error : AppColors.onSurfaceVariant)),
              ),
            ]),
            Gap.sm,
            StockBar(item: item),
            Gap.sm,
            Text(
              item.status == StockStatus.negative
                  ? 'Usage recorded offline went past the recorded stock. Count the shelf to correct it.'
                  : [
                      if (item.lastTransactionAt != null) 'Last change ${Fmt.relative(item.lastTransactionAt!).replaceFirstMapped(RegExp('^[A-Z]'), (m) => m[0]!.toLowerCase())}',
                      if (item.jobsUsedThisMonth > 0) 'used in ${item.jobsUsedThisMonth} job${item.jobsUsedThisMonth == 1 ? '' : 's'} this month',
                    ].join(' · '),
              style: AppText.bodySm.copyWith(color: item.status == StockStatus.negative ? AppColors.error : AppColors.onSurfaceVariant),
            ),
            if (!item.isArchived) ...[
              Gap.lg,
              Row(children: [
                Expanded(
                  child: AppButton(
                    label: 'Use for Job',
                    icon: Symbols.content_cut,
                    size: AppButtonSize.medium,
                    variant: low ? AppButtonVariant.tonal : AppButtonVariant.primary,
                    expand: true,
                    onPressed: () => _stock(context, TransactionType.usage),
                  ),
                ),
                Gap.sm,
                Expanded(
                  child: AppButton(
                    label: low && item.reorderQuantity != null ? 'Restock (${item.format(item.reorderQuantity!)})' : 'Receive',
                    icon: Symbols.local_shipping,
                    size: AppButtonSize.medium,
                    variant: low ? AppButtonVariant.primary : AppButtonVariant.tonal,
                    expand: true,
                    onPressed: () => _stock(context, TransactionType.purchase, quantity: low ? item.reorderQuantity : null),
                  ),
                ),
              ]),
              Gap.sm,
              Row(children: [
                for (final (i, type) in const [TransactionType.returned, TransactionType.writeOff, TransactionType.adjustment].indexed) ...[
                  if (i > 0) Gap.sm,
                  Expanded(
                    child: AppButton(
                      label: switch (type) {
                        TransactionType.returned => 'Return',
                        TransactionType.writeOff => 'Write off',
                        _ => 'Count',
                      },
                      icon: type.icon,
                      size: AppButtonSize.small,
                      variant: AppButtonVariant.outline,
                      expand: true,
                      onPressed: () => _stock(context, type),
                    ),
                  ),
                ],
              ]),
            ],
          ]),
        ),
        Gap.md,
        AppCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Kicker('Details'),
            Gap.sm,
            _Detail(icon: Symbols.shelves, label: 'Storage', value: item.storageLocation),
            _Detail(icon: Symbols.storefront, label: 'Supplier', value: [item.supplierName, item.supplierContact].whereType<String>().join(' · ').ifEmpty),
            _Detail(icon: Symbols.sell, label: 'Unit cost', value: item.unitCost == null ? null : unitCostLabel(item, currency)),
            _Detail(icon: Symbols.low_priority, label: 'Minimum stock', value: item.format(item.minStockLevel)),
            _Detail(icon: Symbols.local_shipping, label: 'Usual reorder', value: item.reorderQuantity == null ? null : item.format(item.reorderQuantity!)),
            _Detail(icon: Symbols.straighten, label: 'Counted in', value: StockUnits.labels[item.unit] ?? item.unit),
            if (item.notes != null) ...[Gap.sm, Text(item.notes!, style: AppText.bodyMd)],
          ]),
        ),
        Gap.md,
        AppCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            SectionHeader(title: 'Stock history', count: '${ledger.where((t) => !t.isVoided).length}'),
            if (ledger.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpace.md),
                child: Text('No stock recorded yet. Receive stock or count the shelf to start.', style: AppText.bodyMd.copyWith(color: AppColors.onSurfaceVariant)),
              )
            else ...[
              Text('Tap an entry made by mistake to void it.', style: AppText.bodySm.copyWith(color: AppColors.onSurfaceVariant)),
              for (final (i, tx) in ledger.indexed) ...[
                if (i > 0) const Divider(height: 1, color: AppColors.surfaceContainer),
                LedgerRow(tx: tx, unit: item.unit, when: Fmt.dateTime(tx.occurredAt), onTap: tx.isVoided ? null : () => _ledgerTap(context, ref, tx)),
              ],
            ],
          ]),
        ),
      ]),
    );
  }
}

class _Detail extends StatelessWidget {
  const _Detail({required this.icon, required this.label, required this.value});

  final IconData icon;
  final String label;
  final String? value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(children: [
        Icon(icon, size: 18, color: AppColors.onSurfaceVariant),
        Gap.sm,
        SizedBox(width: 112, child: Text(label, style: AppText.bodySm.copyWith(color: AppColors.onSurfaceVariant))),
        Expanded(child: Text(value ?? '—', style: AppText.labelMd.copyWith(color: value == null ? AppColors.outline : AppColors.onSurface))),
      ]),
    );
  }
}

extension on String {
  String? get ifEmpty => isEmpty ? null : this;
}
