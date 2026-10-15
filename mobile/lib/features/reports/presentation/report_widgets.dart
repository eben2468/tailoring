import 'dart:math';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/gap.dart';
import '../../../core/widgets/section_header.dart';

/// "12.5 h" from seconds (one decimal; whole hours without it).
String hoursLabel(num seconds) {
  final h = seconds / 3600;
  final s = h.abs() >= 100 || h == h.roundToDouble() ? h.toStringAsFixed(0) : h.toStringAsFixed(1);
  return '$s h';
}

/// "+1.5 h" / "−2 h".
String signedHours(num seconds) => seconds == 0 ? '0 h' : '${seconds > 0 ? '+' : '−'}${hoursLabel(seconds.abs())}';

/// "+4.2%" / "−5.6%" / "—".
String signedPercent(num? v) => v == null ? '—' : '${v > 0 ? '+' : (v < 0 ? '−' : '')}${v.abs().toStringAsFixed(1)}%';

String number(num v) => v == v.roundToDouble() ? NumberFormat.decimalPattern().format(v) : NumberFormat('#,##0.##').format(v);

/// Short bucket label for chart axes: day "9", week "6 Oct", month "Oct".
String periodLabel(String ymd, String groupBy) {
  final d = DateTime.parse(ymd);
  return switch (groupBy) {
    'day' => '${d.day}',
    'week' => DateFormat('d MMM').format(d),
    _ => DateFormat('MMM').format(d),
  };
}

/// "Offline · figures from 14:02" banner for a report shown from the phone's copy.
class StaleBanner extends StatelessWidget {
  const StaleBanner({super.key, required this.fetchedAt});

  final DateTime fetchedAt;

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    final sameDay = fetchedAt.year == today.year && fetchedAt.month == today.month && fetchedAt.day == today.day;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(color: AppColors.warningContainer, borderRadius: AppRadius.control),
      child: Row(children: [
        const Icon(Symbols.cloud_off, size: 18, color: AppColors.warning),
        Gap.sm,
        Expanded(
          child: Text(
            'Offline · figures from ${sameDay ? DateFormat('HH:mm').format(fetchedAt) : DateFormat('d MMM, HH:mm').format(fetchedAt)}. Pull down to refresh when connected.',
            style: AppText.bodySm.copyWith(color: AppColors.warning),
          ),
        ),
      ]),
    );
  }
}

/// One key figure.
class Kpi {
  const Kpi(this.label, this.value, {this.caption, this.color});

  final String label;
  final String value;
  final String? caption;
  final Color? color;
}

/// Key figures in a two-column grid of small cards.
class KpiGrid extends StatelessWidget {
  const KpiGrid({super.key, required this.items});

  final List<Kpi> items;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var i = 0; i < items.length; i += 2) {
      if (i > 0) rows.add(Gap.sm);
      rows.add(IntrinsicHeight(
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Expanded(child: _KpiCard(kpi: items[i])),
          Gap.sm,
          Expanded(child: i + 1 < items.length ? _KpiCard(kpi: items[i + 1]) : const SizedBox.shrink()),
        ]),
      ));
    }
    return Column(children: rows);
  }
}

class _KpiCard extends StatelessWidget {
  const _KpiCard({required this.kpi});

  final Kpi kpi;

  @override
  Widget build(BuildContext context) => AppCard(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(kpi.label.toUpperCase(), style: AppText.overline, maxLines: 1, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 8),
          Text(kpi.value, style: AppText.metricNum.copyWith(color: kpi.color ?? AppColors.onSurface), maxLines: 1, overflow: TextOverflow.ellipsis),
          if (kpi.caption != null) ...[
            const SizedBox(height: 2),
            Text(kpi.caption!, style: AppText.labelSm.copyWith(color: AppColors.onSurfaceVariant, fontWeight: FontWeight.w500), maxLines: 2, overflow: TextOverflow.ellipsis),
          ],
        ]),
      );
}

/// A series to draw: one value per period.
class ChartSeries {
  const ChartSeries(this.label, this.color, this.values);

  final String label;
  final Color color;
  final List<double> values;
}

/// Grouped vertical bars per period (up to three series), with a legend and sparse axis labels.
/// Drawn with plain widgets: no chart library.
class BarChartCard extends StatelessWidget {
  const BarChartCard({super.key, required this.title, required this.labels, required this.series, this.format = number, this.height = 140});

  final String title;
  final List<String> labels;
  final List<ChartSeries> series;
  final String Function(num) format;
  final double height;

  @override
  Widget build(BuildContext context) {
    final peak = series.expand((s) => s.values).fold<double>(0, max);
    final every = max(1, (labels.length / 8).ceil());
    return AppCard(
      padding: const EdgeInsets.all(AppSpace.lg),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(child: Text(title, style: AppText.titleSm)),
          if (peak > 0) Text('max ${format(peak)}', style: AppText.labelSm.copyWith(color: AppColors.onSurfaceVariant)),
        ]),
        if (series.length > 1) ...[
          Gap.xs,
          Wrap(spacing: 12, children: [
            for (final s in series)
              Row(mainAxisSize: MainAxisSize.min, children: [
                Container(width: 10, height: 10, decoration: BoxDecoration(color: s.color, borderRadius: AppRadius.small)),
                const SizedBox(width: 4),
                Text(s.label, style: AppText.labelSm.copyWith(color: AppColors.onSurfaceVariant)),
              ]),
          ]),
        ],
        Gap.md,
        SizedBox(
          height: height,
          child: peak <= 0
              ? Center(child: Text('Nothing in this period', style: AppText.bodySm.copyWith(color: AppColors.onSurfaceVariant)))
              : Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  for (var i = 0; i < labels.length; i++)
                    Expanded(
                      child: Padding(
                        padding: EdgeInsets.symmetric(horizontal: labels.length > 20 ? 0.5 : 2),
                        child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                          for (final s in series)
                            Expanded(
                              child: FractionallySizedBox(
                                heightFactor: (s.values[i] / peak).clamp(0, 1).toDouble(),
                                child: Container(decoration: BoxDecoration(color: s.color, borderRadius: const BorderRadius.vertical(top: Radius.circular(2)))),
                              ),
                            ),
                        ]),
                      ),
                    ),
                ]),
        ),
        const Divider(height: 1, color: AppColors.surfaceContainerHighest),
        const SizedBox(height: 4),
        Row(children: [
          for (var i = 0; i < labels.length; i++)
            Expanded(
              child: i % every == 0
                  ? Text(labels[i], style: AppText.labelSm.copyWith(color: AppColors.onSurfaceVariant, fontSize: 9), textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.visible, softWrap: false)
                  : const SizedBox.shrink(),
            ),
        ]),
      ]),
    );
  }
}

/// One row of a breakdown: label, optional detail, value, and a bar showing its share.
class BreakdownRow {
  const BreakdownRow(this.label, this.value, {this.detail, this.share, this.valueColor, this.onTap});

  final String label;
  final String value;
  final String? detail;

  /// 0–1, drawn as a thin bar.
  final double? share;
  final Color? valueColor;
  final VoidCallback? onTap;
}

class BreakdownCard extends StatelessWidget {
  const BreakdownCard({super.key, required this.title, required this.rows, this.empty = 'Nothing in this period.', this.count});

  final String title;
  final List<BreakdownRow> rows;
  final String empty;
  final String? count;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.all(AppSpace.lg),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SectionHeader(title: title, count: count),
        if (rows.isEmpty)
          Padding(padding: const EdgeInsets.only(top: AppSpace.sm), child: Text(empty, style: AppText.bodyMd.copyWith(color: AppColors.onSurfaceVariant)))
        else
          for (final (i, r) in rows.indexed) ...[
            if (i > 0) const Divider(height: 1, color: AppColors.surfaceContainer),
            InkWell(
              onTap: r.onTap,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Row(children: [
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(r.label, style: AppText.labelMd, maxLines: 1, overflow: TextOverflow.ellipsis),
                        if (r.detail != null) Text(r.detail!, style: AppText.bodySm.copyWith(color: AppColors.onSurfaceVariant), maxLines: 2, overflow: TextOverflow.ellipsis),
                      ]),
                    ),
                    Gap.sm,
                    Text(r.value, style: AppText.labelMd.copyWith(color: r.valueColor ?? AppColors.onSurface, fontFeatures: const [FontFeature.tabularFigures()])),
                    if (r.onTap != null) const Icon(Symbols.chevron_right, size: 18, color: AppColors.outline),
                  ]),
                  if (r.share != null) ...[
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: AppRadius.full,
                      child: SizedBox(
                        height: 4,
                        child: Stack(children: [
                          const Positioned.fill(child: ColoredBox(color: AppColors.surfaceContainerHighest)),
                          FractionallySizedBox(alignment: Alignment.centerLeft, widthFactor: r.share!.clamp(0, 1).toDouble(), heightFactor: 1, child: const ColoredBox(color: AppColors.secondary)),
                        ]),
                      ),
                    ),
                  ],
                ]),
              ),
            ),
          ],
      ]),
    );
  }
}
