import 'dart:async';

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
import '../../../core/widgets/filter_pills.dart';
import '../../../core/widgets/gap.dart';
import '../../../core/widgets/state_views.dart';
import '../../sync/application/sync_providers.dart';
import '../application/job_providers.dart';
import 'job_widgets.dart';

/// Jobs tab — Stitch "Production Jobs": search, filter chips with counts, job cards.
class JobsScreen extends ConsumerStatefulWidget {
  const JobsScreen({super.key});

  @override
  ConsumerState<JobsScreen> createState() => _JobsScreenState();
}

class _JobsScreenState extends ConsumerState<JobsScreen> {
  JobQuery _query = const JobQuery();
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  void _search(String text) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () => setState(() => _query = JobQuery(filter: _query.filter, text: text.trim())));
  }

  Future<void> _refresh() => ref.read(syncControllerProvider.notifier).syncNow();

  @override
  Widget build(BuildContext context) {
    final list = ref.watch(jobListProvider(_query));
    final counts = ref.watch(jobCountsProvider(null)).value;
    final selected = jobFilters.indexWhere((f) => f.$1 == _query.filter);
    final open = counts?['open'];
    final inProduction = counts?['active'];

    return SectionScaffold(
      title: 'Jobs',
      body: RefreshIndicator(
        edgeOffset: MediaQuery.paddingOf(context).top + 64,
        onRefresh: _refresh,
        child: CustomScrollView(slivers: [
          SliverPadding(
            padding: headerOnly(context),
            sliver: SliverList.list(children: [
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Production Jobs', style: AppText.headlineLg),
                    Gap.xs,
                    Row(children: [
                      Container(width: 6, height: 6, decoration: const BoxDecoration(color: AppColors.secondary, shape: BoxShape.circle)),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          open == null ? 'Loading…' : '$inProduction in production · $open open',
                          style: AppText.bodyMd.copyWith(color: AppColors.onSurfaceVariant),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ]),
                  ]),
                ),
                AppButton(label: 'Add Job', icon: Symbols.content_cut, size: AppButtonSize.medium, onPressed: () => context.push(Routes.jobNew())),
              ]),
              Gap.lg,
              AppSearchField(hint: 'Search customer, garment or job (#024)…', onChanged: _search, initialValue: _query.text),
              Gap.md,
              FilterPills(
                labels: [for (final (key, label) in jobFilters) counts == null ? label : '$label (${counts[key]})'],
                selected: selected < 0 ? 0 : selected,
                onChanged: (i) => setState(() => _query = JobQuery(filter: jobFilters[i].$1, text: _query.text)),
              ),
              Gap.lg,
            ]),
          ),
          ...switch (list) {
            AsyncData(:final value) when value.items.isEmpty => [
                SliverFillRemaining(hasScrollBody: false, child: _EmptyJobs(query: _query)),
              ],
            AsyncData(:final value) => [
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(AppSpace.margin, 0, AppSpace.margin, belowHeaderAboveNav(context).bottom),
                  sliver: SliverList.separated(
                    itemCount: value.items.length,
                    separatorBuilder: (_, _) => Gap.md,
                    itemBuilder: (context, i) {
                      final job = value.items[i];
                      return JobCard(job: job, onTap: () => context.push(Routes.job(job.id)));
                    },
                  ),
                ),
              ],
            AsyncError(:final error) => [
                SliverFillRemaining(hasScrollBody: false, child: ErrorView(error: error, onRetry: () => ref.invalidate(bootstrapProvider))),
              ],
            _ => [const SliverFillRemaining(hasScrollBody: false, child: LoadingView())],
          },
        ]),
      ),
    );
  }
}

class _EmptyJobs extends StatelessWidget {
  const _EmptyJobs({required this.query});

  final JobQuery query;

  @override
  Widget build(BuildContext context) {
    if (query.text.isNotEmpty) {
      return MessageView(icon: Symbols.search_off, title: 'No matches', message: 'No job matches "${query.text}" in this list.');
    }
    return switch (query.filter) {
      'open' => MessageView(
          icon: Symbols.content_cut,
          title: 'No jobs in the atelier',
          message: 'Create a job to plan its production stages and track hours.',
          actionLabel: 'Add job',
          onAction: () => context.push(Routes.jobNew()),
        ),
      'overdue' => const MessageView(icon: Symbols.verified, title: 'Nothing overdue', message: 'Every job in production is on schedule.'),
      'due_soon' => const MessageView(icon: Symbols.event_available, title: 'Nothing due soon', message: 'No job in production is due in the next few days.'),
      _ => const MessageView(icon: Symbols.inbox, title: 'No jobs here', message: 'Jobs with this status will appear here.'),
    };
  }
}
