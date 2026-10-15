import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/gap.dart';
import '../../../core/widgets/status_pill.dart';
import '../domain/inventory.dart';

StatusTone stockTone(StockStatus status) => switch (status) {
      StockStatus.ok => StatusTone.success,
      StockStatus.low => StatusTone.info,
      StockStatus.out || StockStatus.negative => StatusTone.danger,
    };

/// "GHS 145.00 / m".
String unitCostLabel(InventoryItem item, String currency) => '$currency ${item.unitCost!.toStringAsFixed(2)} / ${item.unit}';

/// 56px material tile (Stitch shows a swatch photo; there are no photos yet, so the unit badge and an icon).
class MaterialThumb extends StatelessWidget {
  const MaterialThumb({super.key, required this.item, this.size = 56});

  final InventoryItem item;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: AppColors.surfaceContainerLow, borderRadius: AppRadius.control),
      child: Stack(children: [
        Center(child: Icon(item.isCounted ? Symbols.category : Symbols.straighten, size: 24, color: AppColors.onPrimaryFixedVariant)),
        Positioned(
          right: 4,
          bottom: 4,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
            decoration: BoxDecoration(color: AppColors.surfaceContainerHighest.withValues(alpha: 0.9), borderRadius: AppRadius.small),
            child: Text(item.unit.toUpperCase(), style: AppText.labelSm.copyWith(fontSize: 9, letterSpacing: 9 * 0.08)),
          ),
        ),
      ]),
    );
  }
}

/// The 6px stock bar: on hand against the restocked level (minimum + reorder quantity).
class StockBar extends StatelessWidget {
  const StockBar({super.key, required this.item});

  final InventoryItem item;

  @override
  Widget build(BuildContext context) {
    final color = switch (item.status) {
      StockStatus.ok => AppColors.secondary,
      StockStatus.low => AppColors.secondaryContainer,
      _ => AppColors.error,
    };
    return ClipRRect(
      borderRadius: AppRadius.full,
      child: SizedBox(
        height: 6,
        child: Stack(children: [
          const Positioned.fill(child: ColoredBox(color: AppColors.surfaceContainerHighest)),
          FractionallySizedBox(alignment: Alignment.centerLeft, widthFactor: item.fillRatio, heightFactor: 1, child: ColoredBox(color: color)),
        ]),
      ),
    );
  }
}

/// Stitch inventory card: thumb, category · code, name, location · cost, status, stock tile, actions.
class InventoryItemCard extends StatelessWidget {
  const InventoryItemCard({
    super.key,
    required this.item,
    required this.currency,
    this.onTap,
    this.onUse,
    this.onReceive,
    this.onCount,
  });

  final InventoryItem item;
  final String currency;
  final VoidCallback? onTap;
  final VoidCallback? onUse;
  final VoidCallback? onReceive;
  final VoidCallback? onCount;

  @override
  Widget build(BuildContext context) {
    final low = item.status.needsAttention;
    final restock = item.reorderQuantity;
    return AppCard(
      padding: const EdgeInsets.all(AppSpace.lg),
      onTap: onTap,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          MaterialThumb(item: item),
          Gap.md,
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Flexible(child: Text((item.categoryName ?? '').toUpperCase(), style: AppText.overline, maxLines: 1, overflow: TextOverflow.ellipsis)),
                if (item.sku != null) ...[
                  Text('  •  ', style: AppText.labelSm.copyWith(color: AppColors.outlineVariant)),
                  Flexible(child: Text(item.sku!, style: AppText.labelSm.copyWith(color: AppColors.secondary), maxLines: 1, overflow: TextOverflow.ellipsis)),
                ],
              ]),
              const SizedBox(height: 2),
              Text(item.name, style: AppText.titleSm, maxLines: 1, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 4),
              Wrap(spacing: 8, runSpacing: 2, crossAxisAlignment: WrapCrossAlignment.center, children: [
                if (item.storageLocation != null)
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Symbols.shelves, size: 14, color: AppColors.onSurfaceVariant),
                    const SizedBox(width: 4),
                    Text(item.storageLocation!, style: AppText.bodySm.copyWith(color: AppColors.onSurfaceVariant)),
                  ]),
                if (item.unitCost != null) Text(unitCostLabel(item, currency), style: AppText.bodySm.copyWith(color: AppColors.onSurfaceVariant, fontFeatures: const [FontFeature.tabularFigures()])),
              ]),
            ]),
          ),
          Gap.sm,
          StatusPill(label: item.status.label, tone: stockTone(item.status)),
        ]),
        Gap.md,
        InsetTile(
          padding: const EdgeInsets.all(10),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
              Expanded(
                child: Wrap(spacing: 6, crossAxisAlignment: WrapCrossAlignment.end, children: [
                  Text(item.onHandLabel, style: AppText.metricNum.copyWith(color: item.quantityOnHand < 0 ? AppColors.error : AppColors.onSurface)),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 3),
                    child: low
                        ? Text('(Min: ${item.format(item.minStockLevel)})', style: AppText.bodySm.copyWith(color: AppColors.error, fontWeight: FontWeight.w500))
                        : Text('On hand', style: AppText.bodySm.copyWith(color: AppColors.onSurfaceVariant)),
                  ),
                ]),
              ),
              if (item.jobsUsedThisMonth > 0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(color: AppColors.surfaceContainerHighest.withValues(alpha: 0.6), borderRadius: AppRadius.small),
                  child: Text('Used in ${item.jobsUsedThisMonth} job${item.jobsUsedThisMonth == 1 ? '' : 's'} this month', style: AppText.labelSm.copyWith(color: AppColors.onSurfaceVariant)),
                ),
            ]),
            Gap.sm,
            StockBar(item: item),
            Gap.sm,
            Row(children: [
              Expanded(
                child: Text(
                  item.description ?? (item.status == StockStatus.negative ? 'Usage recorded offline went past the stock. Count the shelf.' : ''),
                  style: AppText.labelSm.copyWith(color: AppColors.onSurfaceVariant, fontWeight: FontWeight.w500),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (!low && item.minStockLevel > 0) Text('Min: ${item.format(item.minStockLevel)}', style: AppText.labelSm.copyWith(color: AppColors.onSurfaceVariant, fontWeight: FontWeight.w500)),
            ]),
          ]),
        ),
        if (!item.isArchived) ...[
          Gap.md,
          Row(children: [
            Expanded(
              child: low
                  ? AppButton(
                      label: restock == null ? 'Receive stock' : 'Restock (${item.format(restock)})',
                      icon: Symbols.local_shipping,
                      size: AppButtonSize.small,
                      expand: true,
                      onPressed: onReceive,
                    )
                  : AppButton(label: 'Use for Job', icon: Symbols.content_cut, size: AppButtonSize.small, variant: AppButtonVariant.tonal, expand: true, onPressed: onUse),
            ),
            Gap.sm,
            AppButton(
              label: low ? 'Count' : 'Stock',
              icon: Symbols.add,
              size: AppButtonSize.small,
              variant: AppButtonVariant.outline,
              onPressed: low ? onCount : onReceive,
            ),
          ]),
        ],
      ]),
    );
  }
}

/// Stitch "Atelier Supply Replenishment": materials at or below their minimum, with a restock action.
class ReplenishmentCard extends StatelessWidget {
  const ReplenishmentCard({super.key, required this.alerts, required this.onRestock, required this.onOpen});

  final List<InventoryItem> alerts;
  final ValueChanged<InventoryItem> onRestock;
  final ValueChanged<InventoryItem> onOpen;

  @override
  Widget build(BuildContext context) {
    final shown = alerts.take(4).toList();
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: AppColors.surfaceContainerHigh.withValues(alpha: 0.6), borderRadius: AppRadius.card, boxShadow: AppShadows.card),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(color: AppColors.surfaceContainerLowest, borderRadius: AppRadius.control),
            child: const Icon(Symbols.emergency_heat, size: 17, color: AppColors.secondary),
          ),
          Gap.sm,
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Supply Replenishment', style: AppText.titleSm),
              Text(
                '${alerts.length} material${alerts.length == 1 ? '' : 's'} at or below the minimum',
                style: AppText.bodySm.copyWith(color: AppColors.onSurfaceVariant),
              ),
            ]),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(color: AppColors.surfaceContainerLowest, borderRadius: AppRadius.full),
            child: Text('Priority', style: AppText.labelSm),
          ),
        ]),
        for (final item in shown) ...[
          Gap.sm,
          Material(
            color: AppColors.surfaceContainerLowest.withValues(alpha: 0.9),
            borderRadius: AppRadius.control,
            child: InkWell(
              borderRadius: AppRadius.control,
              onTap: () => onOpen(item),
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Row(children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(item.name, style: AppText.labelMd, maxLines: 1, overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 2),
                      Text.rich(
                        TextSpan(children: [
                          TextSpan(
                            text: item.quantityOnHand <= 0 ? (item.quantityOnHand < 0 ? '${item.onHandLabel} (recount)' : 'None left') : '${item.onHandLabel} left',
                            style: const TextStyle(color: AppColors.error, fontWeight: FontWeight.w500),
                          ),
                          const TextSpan(text: '  •  ', style: TextStyle(color: AppColors.outlineVariant)),
                          TextSpan(text: 'Min: ${item.format(item.minStockLevel)}'),
                        ]),
                        style: AppText.bodySm.copyWith(color: AppColors.onSurfaceVariant),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ]),
                  ),
                  Gap.sm,
                  AppButton(label: 'Restock', size: AppButtonSize.small, onPressed: () => onRestock(item)),
                ]),
              ),
            ),
          ),
        ],
        if (alerts.length > shown.length) ...[
          Gap.sm,
          Text('+ ${alerts.length - shown.length} more below', style: AppText.labelSm.copyWith(color: AppColors.onSurfaceVariant)),
        ],
      ]),
    );
  }
}

/// One summary tile of the swipeable strip ("ATELIER ITEMS 148 · Across 6 categories").
class InventoryMetricTile extends StatelessWidget {
  const InventoryMetricTile({super.key, required this.label, required this.value, required this.caption, this.trailing, this.badge, this.critical = false, this.width = 150});

  final String label;
  final String value;
  final String caption;
  final Widget? trailing;
  final Widget? badge;
  final bool critical;
  final double width;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: AppColors.surfaceContainerLowest, borderRadius: AppRadius.card, boxShadow: AppShadows.card),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(label.toUpperCase(), style: AppText.overline, maxLines: 1, overflow: TextOverflow.ellipsis)),
          ?trailing,
        ]),
        const SizedBox(height: 10),
        Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
          Text(value, style: AppText.metricNum.copyWith(color: critical ? AppColors.error : AppColors.onSurface), maxLines: 1),
          if (badge != null) ...[const SizedBox(width: 6), Flexible(child: badge!)],
        ]),
        const SizedBox(height: 2),
        Text(caption, style: AppText.labelSm.copyWith(color: AppColors.onSurfaceVariant.withValues(alpha: 0.8)), maxLines: 1, overflow: TextOverflow.ellipsis),
      ]),
    );
  }
}

/// Small square badge next to a metric ("Threshold", "Critical").
class MetricBadge extends StatelessWidget {
  const MetricBadge(this.text, {super.key, this.critical = false});

  final String text;
  final bool critical;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        decoration: BoxDecoration(color: critical ? AppColors.errorContainer : AppColors.surfaceContainerHigh, borderRadius: AppRadius.small),
        child: Text(text, style: AppText.labelSm.copyWith(fontSize: 10, letterSpacing: 0.2, color: critical ? AppColors.onErrorContainer : AppColors.onSurface), maxLines: 1, overflow: TextOverflow.ellipsis),
      );
}

/// One ledger line: icon, what happened, job, note, who and when; signed quantity on the right.
class LedgerRow extends StatelessWidget {
  const LedgerRow({super.key, required this.tx, required this.unit, required this.when, this.onTap});

  final InventoryTransaction tx;
  final String unit;
  final String when;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final voided = tx.isVoided;
    final strike = voided ? const TextStyle(decoration: TextDecoration.lineThrough) : const TextStyle();
    final details = [
      if (tx.jobNumber != null) 'Job #${tx.jobNumber}',
      ?tx.reference,
      if (tx.note != null && tx.note != tx.type.label) tx.note!,
    ].join(' · ');
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(color: voided ? AppColors.surfaceContainer : AppColors.surfaceContainerLow, borderRadius: AppRadius.control),
            child: Icon(tx.type.icon, size: 18, color: voided ? AppColors.outline : AppColors.onPrimaryFixedVariant),
          ),
          Gap.md,
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(tx.type.label, style: AppText.labelMd.merge(strike).copyWith(color: voided ? AppColors.outline : AppColors.onSurface)),
              if (details.isNotEmpty) Text(details, style: AppText.bodySm.copyWith(color: AppColors.onSurfaceVariant), maxLines: 2, overflow: TextOverflow.ellipsis),
              Text(
                voided ? 'Voided: ${tx.voidReason ?? ''}' : [when, ?tx.recordedBy].join(' · '),
                style: AppText.labelSm.copyWith(color: voided ? AppColors.error : AppColors.outline, fontWeight: FontWeight.w500),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ]),
          ),
          Gap.sm,
          Text(
            tx.signedLabel(unit),
            style: AppText.titleSm.merge(strike).copyWith(
                  color: voided ? AppColors.outline : (tx.quantityChange > 0 ? AppColors.onTertiaryContainer : AppColors.onSurface),
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
          ),
        ]),
      ),
    );
  }
}
