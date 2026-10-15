import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../app/routes.dart';
import '../../../app/section_scaffold.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/widgets/filter_pills.dart';
import '../../../core/widgets/gap.dart';
import '../../../core/widgets/menu_row.dart';
import '../../../core/widgets/section_header.dart';
import '../../../core/widgets/state_views.dart';
import '../../auth/application/session_controller.dart';
import '../application/report_providers.dart';
import '../domain/reports.dart';
import 'report_views.dart';
import 'report_widgets.dart';

/// More → Reports: the list of reports (not designed in Stitch; built from the design system).
class ReportsScreen extends StatelessWidget {
  const ReportsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DetailScaffold(
      title: 'Reports',
      body: ListView(padding: belowHeader(context), children: [
        Text('Atelier Reports', style: AppText.headlineLg),
        Gap.xs,
        Text('Calculated on the server from your jobs, hours, stock and tools. Each report keeps its last figures on this phone.',
            style: AppText.bodyMd.copyWith(color: AppColors.onSurfaceVariant)),
        Gap.lg,
        const Kicker('Production'),
        MenuGroup(children: [
          for (final k in const [ReportKind.jobs, ReportKind.hours, ReportKind.workload]) MenuRow(icon: k.icon, title: k.title, subtitle: k.description, onTap: () => context.push(Routes.report(k.key))),
        ]),
        Gap.xl,
        const Kicker('Business'),
        MenuGroup(children: [
          for (final k in const [ReportKind.customers, ReportKind.inventory, ReportKind.tools]) MenuRow(icon: k.icon, title: k.title, subtitle: k.description, onTap: () => context.push(Routes.report(k.key))),
        ]),
      ]),
    );
  }
}

/// One report with the range chips; pull down to refresh.
class ReportScreen extends ConsumerWidget {
  const ReportScreen({super.key, required this.kind});

  final ReportKind kind;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final preset = ref.watch(reportPresetProvider);
    final range = preset.range(DateTime.now());
    final report = ref.watch(reportProvider((kind, range)));
    final currency = ref.watch(sessionControllerProvider).value?.business.currency ?? '';
    final dates = '${DateFormat('d MMM').format(range.from)} – ${DateFormat('d MMM yyyy').format(range.to)}';

    return DetailScaffold(
      title: kind.title,
      body: RefreshIndicator(
        edgeOffset: MediaQuery.paddingOf(context).top + 64,
        onRefresh: () => ref.refresh(reportProvider((kind, range)).future),
        child: ListView(padding: belowHeader(context).copyWith(left: 0, right: 0), children: [
          FilterPills(
            labels: [for (final p in ReportPreset.values) p.label],
            selected: ReportPreset.values.indexOf(preset),
            onChanged: (i) => ref.read(reportPresetProvider.notifier).select(ReportPreset.values[i]),
          ),
          Gap.sm,
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(children: [
              const Icon(Symbols.date_range, size: 16, color: AppColors.onSurfaceVariant),
              const SizedBox(width: 6),
              Text(dates, style: AppText.labelMd.copyWith(color: AppColors.onSurfaceVariant)),
            ]),
          ),
          Gap.md,
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: switch (report) {
              AsyncData(:final value) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  if (value.stale) ...[StaleBanner(fetchedAt: value.fetchedAt), Gap.md],
                  ...reportBody(context, value, currency: currency),
                ]),
              AsyncError(:final error) => SizedBox(height: 420, child: ErrorView(error: error, onRetry: () => ref.invalidate(reportProvider((kind, range))))),
              _ => const SizedBox(height: 420, child: LoadingView(label: 'Calculating…')),
            },
          ),
        ]),
      ),
    );
  }
}
