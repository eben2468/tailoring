import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../app/routes.dart';
import '../../../app/section_scaffold.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/gap.dart';
import '../../../core/widgets/segmented_tabs.dart';
import '../../../core/widgets/state_views.dart';
import '../../sync/application/sync_providers.dart';
import '../application/calendar_providers.dart';
import '../domain/calendar.dart';
import 'calendar_widgets.dart';

/// Calendar tab — Stitch "Atelier Schedule": week strip, capacity & deadlines, and the day's
/// production blocks, appointments and job dates. Day and Month views use the same items.
class CalendarScreen extends ConsumerStatefulWidget {
  const CalendarScreen({super.key});

  @override
  ConsumerState<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends ConsumerState<CalendarScreen> {
  int _view = 1; // 0 day · 1 week · 2 month
  DateTime _selected = dayOf(DateTime.now());
  late DateTime _month = DateTime(_selected.year, _selected.month);

  void _select(DateTime day) => setState(() {
        _selected = dayOf(day);
        _month = DateTime(_selected.year, _selected.month);
      });

  @override
  Widget build(BuildContext context) {
    final monday = weekStart(_selected);
    final week = isoWeek(_selected);

    return SectionScaffold(
      title: 'Calendar',
      body: RefreshIndicator(
        edgeOffset: MediaQuery.paddingOf(context).top + 64,
        onRefresh: () => ref.read(syncControllerProvider.notifier).syncNow(),
        child: ListView(
          padding: belowHeaderAboveNav(context),
          children: [
            Row(children: [
              Expanded(
                child: Wrap(spacing: AppSpace.sm, runSpacing: AppSpace.xs, crossAxisAlignment: WrapCrossAlignment.center, children: [
                  Text('Atelier Schedule', style: AppText.headlineLg),
                  GestureDetector(
                onTap: () => _select(DateTime.now()),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                  decoration: BoxDecoration(color: AppColors.secondaryFixed, borderRadius: AppRadius.full),
                  child: Text('Week $week', style: AppText.labelMd.copyWith(color: AppColors.onSecondaryFixedVariant)),
                ),
              ),
                ]),
              ),
              Gap.sm,
              AppButton(
                label: 'Schedule',
                icon: Symbols.add,
                size: AppButtonSize.medium,
                onPressed: () => context.push(Routes.appointmentNew(date: _selected)),
              ),
            ]),
            Gap.lg,
            SegmentedTabs(labels: const ['Day', 'Week', 'Month'], selected: _view, onChanged: (i) => setState(() => _view = i)),
            Gap.lg,
            ...switch (_view) {
              0 => _dayView(),
              2 => _monthView(),
              _ => _weekView(monday),
            },
          ],
        ),
      ),
    );
  }

  List<Widget> _weekView(DateTime monday) {
    final items = ref.watch(calendarItemsProvider((monday, monday.add(const Duration(days: 7)))));
    final summary = ref.watch(weekSummaryProvider(monday)).value;
    return switch (items) {
      AsyncData(:final value) => [
          WeekStrip(monday: monday, selected: _selected, items: value, onSelect: _select),
          Gap.md,
          DaySummaryBar(
            day: _selected,
            items: value.where((i) => i.day == _selected).toList(),
            range: '${DateFormat('MMM d').format(monday)} – ${DateFormat(monday.month == monday.add(const Duration(days: 6)).month ? 'd' : 'MMM d').format(monday.add(const Duration(days: 6)))}',
            onPrevious: () => _select(_selected.subtract(const Duration(days: 7))),
            onNext: () => _select(_selected.add(const Duration(days: 7))),
          ),
          if (summary != null) ...[Gap.lg, CapacityCard(summary: summary)],
          Gap.lg,
          DayAgenda(day: _selected, items: value.where((i) => i.day == _selected).toList()),
        ],
      AsyncError(:final error) => [ErrorView(error: error, onRetry: () => ref.invalidate(bootstrapProvider))],
      _ => [const SizedBox(height: 240, child: LoadingView())],
    };
  }

  List<Widget> _dayView() {
    final items = ref.watch(calendarItemsProvider((_selected, _selected.add(const Duration(days: 1)))));
    return [
      Row(children: [
        IconButton(tooltip: 'Previous day', onPressed: () => _select(_selected.subtract(const Duration(days: 1))), icon: const Icon(Symbols.chevron_left)),
        Expanded(
          child: Text(
            dayOf(DateTime.now()) == _selected ? 'Today · ${DateFormat('d MMMM').format(_selected)}' : DateFormat('EEEE, d MMMM').format(_selected),
            style: AppText.titleSm,
            textAlign: TextAlign.center,
          ),
        ),
        IconButton(tooltip: 'Next day', onPressed: () => _select(_selected.add(const Duration(days: 1))), icon: const Icon(Symbols.chevron_right)),
      ]),
      Gap.sm,
      ...switch (items) {
        AsyncData(:final value) => [
            DaySummaryBar(day: _selected, items: value),
            Gap.lg,
            DayAgenda(day: _selected, items: value),
          ],
        AsyncError(:final error) => [ErrorView(error: error, onRetry: () => ref.invalidate(bootstrapProvider))],
        _ => [const SizedBox(height: 240, child: LoadingView())],
      },
    ];
  }

  List<Widget> _monthView() {
    final first = DateTime(_month.year, _month.month);
    final gridStart = weekStart(first);
    final items = ref.watch(calendarItemsProvider((gridStart, gridStart.add(const Duration(days: 42)))));
    return [
      Row(children: [
        IconButton(tooltip: 'Previous month', onPressed: () => setState(() => _month = DateTime(_month.year, _month.month - 1)), icon: const Icon(Symbols.chevron_left)),
        Expanded(child: Text(Fmt.monthYear(_month), style: AppText.titleSm, textAlign: TextAlign.center)),
        IconButton(tooltip: 'Next month', onPressed: () => setState(() => _month = DateTime(_month.year, _month.month + 1)), icon: const Icon(Symbols.chevron_right)),
      ]),
      Gap.sm,
      switch (items) {
        AsyncData(:final value) => AppCard(
            padding: const EdgeInsets.all(AppSpace.sm),
            child: MonthGrid(
              month: _month,
              selected: _selected,
              items: value,
              onSelect: (day) => setState(() {
                _select(day);
                _view = 0;
              }),
            ),
          ),
        AsyncError(:final error) => ErrorView(error: error, onRetry: () => ref.invalidate(bootstrapProvider)),
        _ => const SizedBox(height: 240, child: LoadingView()),
      },
      Gap.md,
      Text('Tap a day to see its schedule.', style: AppText.bodySm.copyWith(color: AppColors.onSurfaceVariant), textAlign: TextAlign.center),
    ];
  }
}
