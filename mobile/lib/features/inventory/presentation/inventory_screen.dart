import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../app/routes.dart';
import '../../../app/section_scaffold.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/feedback.dart';
import '../../../core/widgets/filter_pills.dart';
import '../../../core/widgets/gap.dart';
import '../../../core/widgets/header_icon_button.dart';
import '../../../core/widgets/state_views.dart';
import '../../auth/application/session_controller.dart';
import '../../sync/application/sync_providers.dart';
import '../application/inventory_providers.dart';
import '../domain/inventory.dart';
import 'inventory_widgets.dart';
import 'stock_sheet.dart';

/// More → Inventory — Stitch "Inventory & Materials": search, summary tiles, replenishment alerts,
/// category chips and material cards. Everything comes from the local copy (works offline).
class InventoryScreen extends ConsumerStatefulWidget {
  const InventoryScreen({super.key});

  @override
  ConsumerState<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends ConsumerState<InventoryScreen> {
  String _text = '';
  int? _categoryId;
  bool _archived = false;

  Future<void> _refresh() => ref.read(syncControllerProvider.notifier).syncNow();

  Future<void> _stock(InventoryItem item, TransactionType type, {double? quantity}) async {
    final saved = await showStockSheet(context, itemId: item.id, type: type, quantity: quantity);
    if (saved == true && mounted) showAppSnack(context, '${type.label}: ${item.name}.');
  }

  @override
  Widget build(BuildContext context) {
    final items = ref.watch(inventoryItemsProvider(_archived));
    final summary = ref.watch(inventorySummaryProvider).value;
    final categories = ref.watch(inventoryCategoriesProvider).value ?? const <InventoryCategory>[];
    final currency = ref.watch(sessionControllerProvider).value?.business.currency ?? '';
    final q = _text.toLowerCase();

    // Chips: every category that holds active materials (and the selected one).
    final counts = summary?.itemsByCategory ?? const <int, int>{};
    final chips = categories.where((c) => (counts[c.id] ?? 0) > 0 || c.id == _categoryId).toList();

    return DetailScaffold(
      title: 'Inventory & Materials',
      actions: [
        PopupMenuButton<String>(
          tooltip: 'More',
          padding: EdgeInsets.zero,
          shape: RoundedRectangleBorder(borderRadius: AppRadius.card),
          child: const HeaderIconButton(icon: Symbols.more_vert),
          onSelected: (v) => switch (v) {
            'archived' => setState(() => _archived = !_archived),
            _ => context.push(Routes.inventoryCategories),
          },
          itemBuilder: (_) => [
            PopupMenuItem(value: 'archived', child: Text(_archived ? 'Show active materials' : 'Show archived materials')),
            const PopupMenuItem(value: 'categories', child: Text('Material categories')),
          ],
        ),
      ],
      body: RefreshIndicator(
        edgeOffset: MediaQuery.paddingOf(context).top + 64,
        onRefresh: _refresh,
        child: CustomScrollView(slivers: [
          SliverPadding(
            padding: headerOnly(context).copyWith(left: 0, right: 0),
            sliver: SliverList.list(children: [
              Padding(
                padding: AppSpace.screen,
                child: Row(children: [
                  Expanded(child: AppSearchField(hint: 'Search material, code or shelf…', onChanged: (t) => setState(() => _text = t.trim()))),
                  Gap.sm,
                  AppButton(label: 'Material', icon: Symbols.add, size: AppButtonSize.medium, onPressed: () => context.push(Routes.inventoryNew)),
                ]),
              ),
              if (summary != null && !_archived) ...[
                Gap.md,
                SizedBox(
                  height: 104,
                  child: ListView(scrollDirection: Axis.horizontal, padding: AppSpace.screen, children: [
                    InventoryMetricTile(
                      label: 'Materials',
                      value: '${summary.totalItems}',
                      caption: 'Across ${summary.categoryCount} categor${summary.categoryCount == 1 ? 'y' : 'ies'}',
                      trailing: const Icon(Symbols.inventory_2, size: 18, color: AppColors.secondary),
                    ),
                    Gap.sm,
                    InventoryMetricTile(
                      label: 'Low stock',
                      value: '${summary.lowStock}',
                      caption: summary.lowStock == 0 ? 'All above minimum' : 'Needs review',
                      badge: const MetricBadge('Threshold'),
                      trailing: _dot(AppColors.secondaryContainer),
                      width: 156,
                    ),
                    Gap.sm,
                    InventoryMetricTile(
                      label: 'Depleted',
                      value: '${summary.outOfStock + summary.negative}',
                      caption: _depletedCaption(summary),
                      badge: summary.outOfStock + summary.negative > 0 ? const MetricBadge('Critical', critical: true) : null,
                      critical: summary.outOfStock + summary.negative > 0,
                      trailing: _dot(AppColors.error),
                      width: 156,
                    ),
                    if (summary.valuedItems > 0) ...[
                      Gap.sm,
                      InventoryMetricTile(
                        label: 'Stock value',
                        value: '$currency ${_money(summary.stockValue)}',
                        caption: 'At unit cost · ${summary.valuedItems} material${summary.valuedItems == 1 ? '' : 's'}',
                        trailing: const Icon(Symbols.verified, size: 18, color: AppColors.onTertiaryContainer),
                        width: 185,
                      ),
                    ],
                  ]),
                ),
                if (summary.alerts.isNotEmpty) ...[
                  Gap.md,
                  Padding(
                    padding: AppSpace.screen,
                    child: ReplenishmentCard(
                      alerts: summary.alerts,
                      onOpen: (item) => context.push(Routes.inventoryItem(item.id)),
                      onRestock: (item) => _stock(item, TransactionType.purchase, quantity: item.reorderQuantity),
                    ),
                  ),
                ],
              ],
              Gap.md,
              FilterPills(
                padding: AppSpace.screen,
                labels: ['All ${summary?.totalItems ?? ''}'.trim(), for (final c in chips) '${c.name} ${counts[c.id] ?? 0}'],
                selected: _categoryId == null ? 0 : chips.indexWhere((c) => c.id == _categoryId) + 1,
                onChanged: (i) => setState(() => _categoryId = i == 0 ? null : chips[i - 1].id),
              ),
              Gap.md,
            ]),
          ),
          ...switch (items) {
            AsyncData(:final value) => () {
                final shown = value
                    .where((i) =>
                        (_categoryId == null || i.categoryId == _categoryId) &&
                        (q.isEmpty ||
                            i.name.toLowerCase().contains(q) ||
                            (i.sku?.toLowerCase().contains(q) ?? false) ||
                            (i.description?.toLowerCase().contains(q) ?? false) ||
                            (i.storageLocation?.toLowerCase().contains(q) ?? false)))
                    .toList();
                if (shown.isEmpty) return [SliverFillRemaining(hasScrollBody: false, child: _empty(value.isEmpty))];
                return [
                  SliverPadding(
                    padding: EdgeInsets.fromLTRB(AppSpace.margin, 0, AppSpace.margin, belowHeader(context).bottom),
                    sliver: SliverList.separated(
                      itemCount: shown.length,
                      separatorBuilder: (_, _) => Gap.md,
                      itemBuilder: (context, i) {
                        final item = shown[i];
                        return InventoryItemCard(
                          item: item,
                          currency: currency,
                          onTap: () => context.push(Routes.inventoryItem(item.id)),
                          onUse: () => _stock(item, TransactionType.usage),
                          onReceive: () => _stock(item, TransactionType.purchase, quantity: item.status.needsAttention ? item.reorderQuantity : null),
                          onCount: () => _stock(item, TransactionType.adjustment),
                        );
                      },
                    ),
                  ),
                ];
              }(),
            AsyncError(:final error) => [SliverFillRemaining(hasScrollBody: false, child: ErrorView(error: error, onRetry: () => ref.invalidate(bootstrapProvider)))],
            _ => [const SliverFillRemaining(hasScrollBody: false, child: LoadingView())],
          },
        ]),
      ),
    );
  }

  Widget _empty(bool none) {
    if (_archived) return const MessageView(icon: Symbols.archive, title: 'No archived materials', message: 'Materials you stop using can be archived from their page.');
    if (!none) return MessageView(icon: Symbols.search_off, title: 'No matches', message: _text.isEmpty ? 'No material in this category.' : 'No material matches "$_text".');
    return MessageView(
      icon: Symbols.inventory_2,
      title: 'No materials yet',
      message: 'Add the fabrics, threads, buttons and linings you keep, with their minimum stock, to get low-stock alerts.',
      actionLabel: 'Add material',
      onAction: () => context.push(Routes.inventoryNew),
    );
  }

  static Widget _dot(Color color) => Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle));

  static String _depletedCaption(InventorySummary s) {
    final depleted = s.alerts.where((i) => i.quantityOnHand <= 0).toList();
    if (depleted.isEmpty) return 'Nothing run out';
    return depleted.length == 1 ? depleted.first.name : '${depleted.first.name} +${depleted.length - 1}';
  }

  /// "24,850" / "2,682.50".
  static String _money(double v) {
    final whole = v.truncate();
    final cents = ((v - whole) * 100).round();
    final digits = whole.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');
    return cents == 0 ? digits : '$digits.${cents.toString().padLeft(2, '0')}';
  }
}
