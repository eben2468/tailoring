import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../app/routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/gap.dart';
import '../../../core/widgets/initials_avatar.dart';
import '../../../core/widgets/state_views.dart';
import '../../../core/widgets/status_pill.dart';
import '../domain/calendar.dart';

/// Dot colour per kind (week strip, month grid, section headers).
Color calendarColor(CalendarItem item) => switch (item.kind) {
      CalendarKind.production => AppColors.secondary,
      CalendarKind.appointment => AppColors.onTertiaryContainer,
      CalendarKind.due => item.isOverdue ? AppColors.error : AppColors.warningAccent,
      CalendarKind.collection => AppColors.warningAccent,
      CalendarKind.maintenance => item.isOverdue ? AppColors.error : AppColors.onPrimaryFixedVariant,
    };

String hm(DateTime t) => DateFormat('HH:mm').format(t);

StatusTone appointmentTone(AppointmentStatus s) => switch (s) {
      AppointmentStatus.confirmed => StatusTone.success,
      AppointmentStatus.completed => StatusTone.neutral,
      AppointmentStatus.cancelled || AppointmentStatus.noShow => StatusTone.danger,
      AppointmentStatus.scheduled => StatusTone.info,
    };

/// Mon–Sun chips: weekday, date, up to three dots for what is planned; today is navy.
class WeekStrip extends StatelessWidget {
  const WeekStrip({super.key, required this.monday, required this.selected, required this.items, required this.onSelect});

  final DateTime monday;
  final DateTime selected;
  final List<CalendarItem> items;
  final ValueChanged<DateTime> onSelect;

  @override
  Widget build(BuildContext context) {
    final today = dayOf(DateTime.now());
    return Row(children: [
      for (var i = 0; i < 7; i++) ...[
        if (i > 0) const SizedBox(width: 6),
        Expanded(child: _dayChip(monday.add(Duration(days: i)), today)),
      ],
    ]);
  }

  Widget _dayChip(DateTime day, DateTime today) {
    final isSelected = day == selected;
    final isToday = day == today;
    final dots = items.where((it) => it.day == day).take(3).toList();
    final fg = isSelected ? AppColors.onPrimary : (day.weekday == DateTime.sunday ? AppColors.outline : AppColors.onSurface);
    return Semantics(
      button: true,
      selected: isSelected,
      label: DateFormat('EEEE d MMMM').format(day),
      child: GestureDetector(
        onTap: () => onSelect(day),
        child: Stack(clipBehavior: Clip.none, alignment: Alignment.topCenter, children: [
          AnimatedContainer(
            duration: AppMotion.fast,
            padding: const EdgeInsets.symmetric(vertical: AppSpace.sm + 2),
            decoration: BoxDecoration(
              color: isSelected ? AppColors.primaryContainer : AppColors.surfaceContainerLow,
              borderRadius: AppRadius.control,
              boxShadow: isSelected ? AppShadows.raised : null,
            ),
            child: Column(children: [
              Text(DateFormat('E').format(day).toUpperCase(), style: AppText.labelSm.copyWith(color: isSelected ? AppColors.inverseOnSurface : AppColors.onSurfaceVariant)),
              const SizedBox(height: 2),
              Text('${day.day}', style: AppText.headlineMd.copyWith(color: fg, fontFeatures: const [FontFeature.tabularFigures()])),
              const SizedBox(height: 4),
              SizedBox(
                height: 6,
                child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  for (final it in dots)
                    Container(
                      width: 5,
                      height: 5,
                      margin: const EdgeInsets.symmetric(horizontal: 1.5),
                      decoration: BoxDecoration(color: isSelected ? AppColors.onPrimary : calendarColor(it), shape: BoxShape.circle),
                    ),
                ]),
              ),
            ]),
          ),
          if (isToday)
            Positioned(
              top: -8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(color: AppColors.tertiaryFixedDim, borderRadius: AppRadius.full),
                child: Text('TODAY', style: AppText.labelSm.copyWith(fontSize: 8, color: AppColors.tertiaryContainer)),
              ),
            ),
        ]),
      ),
    );
  }
}

/// "4 Fittings • 8.5h Production Today" with the week range and arrows.
class DaySummaryBar extends StatelessWidget {
  const DaySummaryBar({super.key, required this.day, required this.items, this.range, this.onPrevious, this.onNext});

  final DateTime day;
  final List<CalendarItem> items;
  final String? range;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    final fittings = items.where((i) => i.appointment?.type == AppointmentType.fitting && i.appointment!.status.isOpen).length;
    final appointments = items.where((i) => i.kind == CalendarKind.appointment && i.appointment!.status.isOpen).length;
    final production = items.where((i) => i.kind == CalendarKind.production).fold(0, (s, i) => s + i.duration.inSeconds);
    final when = day == dayOf(DateTime.now()) ? 'Today' : DateFormat('EEEE').format(day);
    final first = fittings > 0 ? '$fittings Fitting${fittings == 1 ? '' : 's'}' : '$appointments Appointment${appointments == 1 ? '' : 's'}';

    return Container(
      padding: const EdgeInsets.fromLTRB(AppSpace.md, AppSpace.xs, AppSpace.xs, AppSpace.xs),
      decoration: BoxDecoration(color: AppColors.secondaryFixed, borderRadius: AppRadius.control),
      child: Row(children: [
        const Icon(Symbols.timer, size: 18, color: AppColors.onSecondaryFixedVariant),
        Gap.sm,
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpace.sm),
            // One line as in the design; shrinks a little next to the week arrows rather than wrapping.
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text('$first • ${Fmt.hours(production)}h Production $when', style: AppText.labelMd.copyWith(color: AppColors.onSecondaryFixed), maxLines: 1),
            ),
          ),
        ),
        if (range != null) ...[
          _Arrow(icon: Symbols.chevron_left, tooltip: 'Previous week', onTap: onPrevious),
          Text(range!, style: AppText.labelMd.copyWith(color: AppColors.onSecondaryFixedVariant)),
          _Arrow(icon: Symbols.chevron_right, tooltip: 'Next week', onTap: onNext),
        ],
      ]),
    );
  }
}

class _Arrow extends StatelessWidget {
  const _Arrow({required this.icon, required this.tooltip, required this.onTap});

  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => IconButton(
        tooltip: tooltip,
        onPressed: onTap,
        visualDensity: VisualDensity.compact,
        constraints: const BoxConstraints.tightFor(width: 32, height: 32),
        padding: EdgeInsets.zero,
        icon: Icon(icon, size: 18, color: AppColors.onSecondaryFixedVariant),
      );
}

/// "Atelier Capacity & Deadlines": bench load ring and collections due this week.
class CapacityCard extends StatelessWidget {
  const CapacityCard({super.key, required this.summary});

  final WeekSummary summary;

  @override
  Widget build(BuildContext context) {
    final load = summary.load;
    final percent = (load * 100).round();
    final color = load > 1 ? AppColors.error : (load > 0.85 ? AppColors.warningAccent : AppColors.secondary);
    return AppCard(
      padding: const EdgeInsets.all(AppSpace.lg),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          const Icon(Symbols.speed, size: 20, color: AppColors.onSurface),
          Gap.sm,
          Expanded(child: Text('Atelier Capacity & Deadlines', style: AppText.titleSm)),
          Text('THIS WEEK', style: AppText.labelSm.copyWith(color: AppColors.secondary, letterSpacing: 0.8)),
        ]),
        Gap.md,
        IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Expanded(
              child: InsetTile(
                padding: const EdgeInsets.all(AppSpace.md),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Weekly Bench Load', style: AppText.labelMd.copyWith(color: AppColors.onSurfaceVariant)),
                  Gap.sm,
                  Row(children: [
                    SizedBox.square(
                      dimension: 44,
                      child: Stack(alignment: Alignment.center, children: [
                        SizedBox.expand(
                          child: CircularProgressIndicator(value: load.clamp(0, 1).toDouble(), strokeWidth: 4, color: color, backgroundColor: AppColors.surfaceContainerHigh),
                        ),
                        Text('$percent%', style: AppText.labelSm.copyWith(fontWeight: FontWeight.w700)),
                      ]),
                    ),
                    Gap.sm,
                    Expanded(
                      child: Text(
                        summary.capacitySeconds == 0
                            ? 'Set working hours to see capacity'
                            : '${Fmt.hours(summary.plannedSeconds)}h planned of ${Fmt.hours(summary.capacitySeconds)}h',
                        style: AppText.bodySm.copyWith(color: AppColors.onSurfaceVariant),
                      ),
                    ),
                  ]),
                ]),
              ),
            ),
            Gap.sm,
            Expanded(
              child: InsetTile(
                padding: const EdgeInsets.all(AppSpace.md),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Expanded(child: Text('Collections Due', style: AppText.labelMd.copyWith(color: AppColors.onSurfaceVariant))),
                    if (summary.collectionsDue > 0) Text('!', style: AppText.titleSm.copyWith(color: AppColors.error)),
                  ]),
                  Gap.sm,
                  Text('${summary.collectionsDue}', style: AppText.displayLgMobile),
                  Text(summary.collectionsDue == 1 ? 'Collection this week' : 'Collections this week', style: AppText.bodySm.copyWith(color: AppColors.onSurfaceVariant)),
                ]),
              ),
            ),
          ]),
        ),
      ]),
    );
  }
}

/// The day's schedule in sections, as in the Stitch week view.
class DayAgenda extends StatelessWidget {
  const DayAgenda({super.key, required this.day, required this.items});

  final DateTime day;
  final List<CalendarItem> items;

  @override
  Widget build(BuildContext context) {
    final production = items.where((i) => i.kind == CalendarKind.production).toList();
    final appointments = items.where((i) => i.kind == CalendarKind.appointment).toList();
    final dates = items.where((i) => i.allDay).toList();

    if (items.isEmpty) {
      return AppCard(
        padding: const EdgeInsets.symmetric(vertical: AppSpace.xl),
        child: MessageView(
          icon: Symbols.event_available,
          title: 'Nothing planned',
          message: 'No fittings, production blocks or deadlines on ${DateFormat('EEEE d MMMM').format(day)}.',
          actionLabel: 'Schedule appointment',
          onAction: () => context.push(Routes.appointmentNew(date: day)),
        ),
      );
    }

    String range(List<CalendarItem> list) {
      if (list.isEmpty) return '';
      final start = list.map((i) => i.start!).reduce((a, b) => a.isBefore(b) ? a : b);
      final end = list.map((i) => i.end!).reduce((a, b) => a.isAfter(b) ? a : b);
      return '${hm(start)} – ${hm(end)}';
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (dates.isNotEmpty) ...[
        const _SectionTitle(title: 'Deadlines, collections & service', color: AppColors.warningAccent),
        for (final it in dates) ...[_DateCard(item: it), Gap.sm],
        Gap.md,
      ],
      if (production.isNotEmpty) ...[
        _SectionTitle(title: 'Atelier production work', color: AppColors.secondary, trailing: range(production)),
        for (final it in production) ...[_ProductionCard(item: it), Gap.sm],
        Gap.md,
      ],
      if (appointments.isNotEmpty) ...[
        _SectionTitle(title: 'Salon appointments & fittings', color: AppColors.onTertiaryContainer, trailing: range(appointments)),
        for (final it in appointments) ...[_AppointmentCard(item: it), Gap.sm],
      ],
    ]);
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, required this.color, this.trailing});

  final String title;
  final Color color;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.sm),
      child: Row(children: [
        Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        Gap.sm,
        Expanded(child: Text(title.toUpperCase(), style: AppText.labelMd.copyWith(letterSpacing: 0.8))),
        if (trailing != null && trailing!.isNotEmpty) Text(trailing!, style: AppText.labelMd.copyWith(color: AppColors.onSurfaceVariant)),
      ]),
    );
  }
}

class _TimePill extends StatelessWidget {
  const _TimePill({required this.start, required this.end});

  final DateTime start;
  final DateTime end;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(color: AppColors.surfaceContainerLow, borderRadius: AppRadius.small),
        child: Text('${hm(start)} – ${hm(end)}', style: AppText.labelMd.copyWith(fontFeatures: const [FontFeature.tabularFigures()])),
      );
}

class _ProductionCard extends StatelessWidget {
  const _ProductionCard({required this.item});

  final CalendarItem item;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      onTap: item.jobId == null ? null : () => context.push(Routes.job(item.jobId!)),
      child: Row(children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(color: AppColors.secondaryFixed, borderRadius: AppRadius.control),
          child: const Icon(Symbols.content_cut, size: 22, color: AppColors.secondary),
        ),
        Gap.md,
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Wrap(spacing: AppSpace.sm, runSpacing: 2, crossAxisAlignment: WrapCrossAlignment.center, children: [
              Text(item.title, style: AppText.titleSm, maxLines: 1, overflow: TextOverflow.ellipsis),
              if (item.status != null) StatusPill(label: item.status!, tone: item.status == 'In Progress' ? StatusTone.success : StatusTone.neutral, showDot: item.status == 'In Progress'),
            ]),
            if (item.subtitle != null && item.subtitle!.isNotEmpty) Text(item.subtitle!, style: AppText.bodySm.copyWith(color: AppColors.onSurfaceVariant), maxLines: 1, overflow: TextOverflow.ellipsis),
          ]),
        ),
        Gap.sm,
        _TimePill(start: item.start!, end: item.end!),
      ]),
    );
  }
}

class _AppointmentCard extends StatelessWidget {
  const _AppointmentCard({required this.item});

  final CalendarItem item;

  @override
  Widget build(BuildContext context) {
    final a = item.appointment!;
    final closed = !a.status.isOpen;
    return Opacity(
      opacity: closed ? 0.6 : 1,
      child: AppCard(
        onTap: () => context.push(Routes.appointment(a.id)),
        padding: const EdgeInsets.all(AppSpace.lg),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (a.customerName != null) InitialsAvatar(name: a.customerName!, size: 44) else _typeIcon(a.type),
            Gap.md,
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Wrap(spacing: AppSpace.sm, runSpacing: 2, crossAxisAlignment: WrapCrossAlignment.center, children: [
                  Text(a.customerName ?? a.title, style: AppText.titleSm, maxLines: 1, overflow: TextOverflow.ellipsis),
                  StatusPill(label: a.type.label, tone: StatusTone.info, showDot: false),
                ]),
                Text(a.customerName == null ? (a.jobNumber == null ? '' : 'Job #${a.jobNumber}') : a.title, style: AppText.bodySm.copyWith(color: AppColors.onSurfaceVariant), maxLines: 1, overflow: TextOverflow.ellipsis),
              ]),
            ),
          ]),
          Gap.md,
          InsetTile(
            padding: const EdgeInsets.symmetric(horizontal: AppSpace.md, vertical: AppSpace.sm),
            child: Row(children: [
              const Icon(Symbols.location_on, size: 18, color: AppColors.secondary),
              Gap.sm,
              Expanded(child: Text(a.location ?? 'No room set', style: AppText.bodyMd, maxLines: 1, overflow: TextOverflow.ellipsis)),
              StatusPill(label: a.status.label, tone: appointmentTone(a.status)),
            ]),
          ),
          Gap.sm,
          Row(children: [
            _TimePill(start: a.startsAt, end: a.endsAt),
            const Spacer(),
            if (a.jobId != null)
              AppButton(label: 'Job #${a.jobNumber ?? '—'}', icon: Symbols.arrow_forward, variant: AppButtonVariant.text, size: AppButtonSize.small, onPressed: () => context.push(Routes.job(a.jobId!))),
          ]),
        ]),
      ),
    );
  }

  Widget _typeIcon(AppointmentType type) => Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(color: AppColors.surfaceContainer, borderRadius: AppRadius.control),
        child: Icon(type.icon, size: 22, color: AppColors.onSurfaceVariant),
      );
}

class _DateCard extends StatelessWidget {
  const _DateCard({required this.item});

  final CalendarItem item;

  @override
  Widget build(BuildContext context) {
    final due = item.kind == CalendarKind.due;
    return AppCard(
      onTap: item.toolId != null
          ? () => context.push(Routes.tool(item.toolId!))
          : item.jobId == null
              ? null
              : () => context.push(Routes.job(item.jobId!)),
      child: Row(children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(color: item.isOverdue ? AppColors.errorContainer : AppColors.warningContainer, borderRadius: AppRadius.control),
          child: Icon(item.kind == CalendarKind.maintenance ? Symbols.build : (due ? Symbols.flag : Symbols.shopping_bag), size: 22, color: item.isOverdue ? AppColors.error : AppColors.warning),
        ),
        Gap.md,
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(item.title, style: AppText.titleSm, maxLines: 1, overflow: TextOverflow.ellipsis),
            if (item.subtitle != null && item.subtitle!.isNotEmpty) Text(item.subtitle!, style: AppText.bodySm.copyWith(color: AppColors.onSurfaceVariant), maxLines: 1, overflow: TextOverflow.ellipsis),
          ]),
        ),
        if (item.isOverdue) const StatusPill(label: 'Overdue', tone: StatusTone.danger) else Text('All day', style: AppText.labelMd.copyWith(color: AppColors.onSurfaceVariant)),
      ]),
    );
  }
}

/// Month grid: weeks Mon–Sun with dots; days outside the month are faded.
class MonthGrid extends StatelessWidget {
  const MonthGrid({super.key, required this.month, required this.selected, required this.items, required this.onSelect});

  final DateTime month;
  final DateTime selected;
  final List<CalendarItem> items;
  final ValueChanged<DateTime> onSelect;

  @override
  Widget build(BuildContext context) {
    final start = weekStart(DateTime(month.year, month.month));
    final today = dayOf(DateTime.now());
    final byDay = <DateTime, List<CalendarItem>>{};
    for (final it in items) {
      (byDay[it.day] ??= []).add(it);
    }
    return Column(children: [
      Row(children: [
        for (final d in const ['M', 'T', 'W', 'T', 'F', 'S', 'S']) Expanded(child: Center(child: Text(d, style: AppText.labelSm.copyWith(color: AppColors.onSurfaceVariant)))),
      ]),
      Gap.xs,
      for (var w = 0; w < 6; w++)
        Row(children: [
          for (var d = 0; d < 7; d++)
            Expanded(
              child: Builder(builder: (context) {
                final day = start.add(Duration(days: w * 7 + d));
                final inMonth = day.month == month.month;
                final isSelected = day == selected;
                final dots = (byDay[day] ?? const <CalendarItem>[]).take(3).toList();
                return InkWell(
                  onTap: () => onSelect(day),
                  borderRadius: AppRadius.control,
                  child: Container(
                    height: 48,
                    margin: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      color: isSelected ? AppColors.primaryContainer : (day == today ? AppColors.secondaryFixed : null),
                      borderRadius: AppRadius.control,
                    ),
                    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Text(
                        '${day.day}',
                        style: AppText.labelMd.copyWith(
                          color: isSelected ? AppColors.onPrimary : (inMonth ? AppColors.onSurface : AppColors.outlineVariant),
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                      const SizedBox(height: 3),
                      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                        for (final it in dots)
                          Container(
                            width: 4,
                            height: 4,
                            margin: const EdgeInsets.symmetric(horizontal: 1),
                            decoration: BoxDecoration(color: isSelected ? AppColors.onPrimary : calendarColor(it), shape: BoxShape.circle),
                          ),
                      ]),
                    ]),
                  ),
                );
              }),
            ),
        ]),
    ]);
  }
}
