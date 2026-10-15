import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../app/routes.dart';
import '../../../app/section_scaffold.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/feedback.dart';
import '../../../core/widgets/filter_pills.dart';
import '../../../core/widgets/gap.dart';
import '../../../core/widgets/header_icon_button.dart';
import '../../../core/widgets/state_views.dart';
import '../../settings/domain/config_category.dart';
import '../../sync/application/sync_providers.dart';
import '../application/tool_providers.dart';
import '../domain/tools.dart';
import 'maintenance_sheet.dart';
import 'tool_widgets.dart';

/// More → Tools & Equipment — Stitch "Tools & Equipment": fleet banner, category chips, the most urgent
/// tool, and the equipment roster. Everything comes from the local copy (works offline).
class ToolsScreen extends ConsumerStatefulWidget {
  const ToolsScreen({super.key});

  @override
  ConsumerState<ToolsScreen> createState() => _ToolsScreenState();
}

class _ToolsScreenState extends ConsumerState<ToolsScreen> {
  int? _categoryId;
  bool _archived = false;

  Future<void> _log(Tool tool) async {
    final saved = await showMaintenanceSheet(context, toolId: tool.id);
    if (saved == true && mounted) showAppSnack(context, 'Maintenance logged for ${tool.name}.');
  }

  @override
  Widget build(BuildContext context) {
    final tools = ref.watch(toolsProvider(_archived));
    final summary = ref.watch(toolSummaryProvider).value;
    final categories = ref.watch(toolCategoriesProvider).value ?? const <ConfigCategory>[];
    final counts = summary?.byCategory ?? const <int, int>{};
    final chips = categories.where((c) => (counts[c.id] ?? 0) > 0 || c.id == _categoryId).toList();
    final urgent = _archived ? null : summary?.alerts.firstOrNull;

    return DetailScaffold(
      title: 'Tools & Equipment',
      actions: [
        PopupMenuButton<String>(
          tooltip: 'More',
          padding: EdgeInsets.zero,
          shape: RoundedRectangleBorder(borderRadius: AppRadius.card),
          child: const HeaderIconButton(icon: Symbols.more_vert),
          onSelected: (v) => switch (v) {
            'archived' => setState(() => _archived = !_archived),
            _ => context.push(Routes.toolCategories),
          },
          itemBuilder: (_) => [
            PopupMenuItem(value: 'archived', child: Text(_archived ? 'Show active tools' : 'Show archived tools')),
            const PopupMenuItem(value: 'categories', child: Text('Tool categories')),
          ],
        ),
      ],
      body: RefreshIndicator(
        edgeOffset: MediaQuery.paddingOf(context).top + 64,
        onRefresh: () => ref.read(syncControllerProvider.notifier).syncNow(),
        child: CustomScrollView(slivers: [
          SliverPadding(
            padding: headerOnly(context).copyWith(left: 0, right: 0),
            sliver: SliverList.list(children: [
              if (summary != null && !_archived) Padding(padding: AppSpace.screen, child: FleetBanner(summary: summary)),
              Gap.md,
              FilterPills(
                padding: AppSpace.screen,
                labels: ['All Equipment (${summary?.total ?? 0})', for (final c in chips) '${c.name} (${counts[c.id] ?? 0})'],
                selected: _categoryId == null ? 0 : chips.indexWhere((c) => c.id == _categoryId) + 1,
                onChanged: (i) => setState(() => _categoryId = i == 0 ? null : chips[i - 1].id),
              ),
              if (urgent != null && (_categoryId == null || urgent.categoryId == _categoryId)) ...[
                Gap.md,
                Padding(
                  padding: AppSpace.screen,
                  child: ImminentActionCard(
                    tool: urgent,
                    onOpen: () => context.push(Routes.tool(urgent.id)),
                    onLog: () => _log(urgent),
                    onChangeDate: () => changeNextServiceDate(context, ref, urgent),
                  ),
                ),
              ],
              Gap.lg,
              Padding(
                padding: AppSpace.screen,
                child: Row(children: [
                  const Icon(Symbols.inventory_2, size: 20, color: AppColors.secondary),
                  Gap.sm,
                  Expanded(child: Text(_archived ? 'Archived Equipment' : 'Atelier Equipment Roster', style: AppText.titleSm)),
                  if (summary != null && !_archived) Text('${summary.operational} active on floor', style: AppText.labelSm.copyWith(color: AppColors.onSurfaceVariant)),
                ]),
              ),
              Gap.md,
            ]),
          ),
          ...switch (tools) {
            AsyncData(:final value) => () {
                final shown = value.where((t) => _categoryId == null || t.categoryId == _categoryId).toList();
                if (shown.isEmpty) return [SliverFillRemaining(hasScrollBody: false, child: _empty(value.isEmpty))];
                return [
                  SliverPadding(
                    padding: AppSpace.screen,
                    sliver: SliverList.separated(
                      itemCount: shown.length,
                      separatorBuilder: (_, _) => Gap.md,
                      itemBuilder: (context, i) => ToolCard(tool: shown[i], onTap: () => context.push(Routes.tool(shown[i].id)), onLog: () => _log(shown[i])),
                    ),
                  ),
                  SliverPadding(
                    padding: EdgeInsets.fromLTRB(AppSpace.margin, AppSpace.xl, AppSpace.margin, belowHeader(context).bottom),
                    sliver: SliverToBoxAdapter(
                      child: AppButton(label: 'Register New Tool', icon: Symbols.add_circle, expand: true, onPressed: () => context.push(Routes.toolNew)),
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
    if (_archived) return const MessageView(icon: Symbols.archive, title: 'No archived tools', message: 'Tools you stop using can be archived from their page.');
    if (!none) return const MessageView(icon: Symbols.search_off, title: 'No tools here', message: 'No tool in this category.');
    return MessageView(
      icon: Symbols.precision_manufacturing,
      title: 'No tools yet',
      message: 'Register your machines, irons and shears with a service cycle to be reminded when maintenance is due.',
      actionLabel: 'Register tool',
      onAction: () => context.push(Routes.toolNew),
    );
  }
}
