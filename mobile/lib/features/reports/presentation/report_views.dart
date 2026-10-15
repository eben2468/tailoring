import 'dart:math';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../app/routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/gap.dart';
import '../../inventory/domain/inventory.dart';
import '../domain/reports.dart';
import 'report_widgets.dart';

/// The body of a report: key figures, chart and breakdowns. Display only: the server calculates.
List<Widget> reportBody(BuildContext context, ReportResult r, {required String currency}) => switch (r.kind) {
      ReportKind.jobs => _jobs(context, r),
      ReportKind.hours => _hours(r),
      ReportKind.workload => _workload(r),
      ReportKind.customers => _customers(context, r),
      ReportKind.inventory => _inventory(context, r, currency),
      ReportKind.tools => _tools(context, r),
    };

num _n(Object? v) => v is num ? v : 0;

double _d(Object? v) => _n(v).toDouble();

List<String> _labels(ReportResult r) => [for (final p in r.series) periodLabel(p['period'] as String, r.groupBy)];

List<double> _values(ReportResult r, String key, {double scale = 1}) => [for (final p in r.series) _d(p[key]) / scale];

Color _varianceColor(num? v) => v == null || v == 0 ? AppColors.onSurface : (v > 0 ? AppColors.error : AppColors.onTertiaryContainer);

List<Widget> _spaced(List<Widget> items) => [
      for (final (i, w) in items.indexed) ...[if (i > 0) Gap.md, w],
    ];

List<Widget> _jobs(BuildContext context, ReportResult r) {
  final t = r.section('totals');
  final now = r.section('now');
  final vsDue = t['average_days_vs_due'] as num?;
  final types = r.list('by_job_type');
  final most = types.fold<num>(0, (m, x) => max(m, max(_n(x['completed']), _n(x['created']))));
  return _spaced([
    KpiGrid(items: [
      Kpi('Completed', number(_n(t['completed'])), caption: '${number(_n(t['garments_completed']))} garments'),
      Kpi('New orders', number(_n(t['created'])), caption: '${number(_n(t['cancelled']))} cancelled'),
      Kpi(
        'On time',
        t['on_time_rate'] == null ? '—' : '${number(_n(t['on_time_rate']))}%',
        caption: _n(t['completed']) == 0
            ? 'No job completed in this period'
            : vsDue == null
                ? 'No completed job had a due date'
                :'${vsDue.abs()} days ${vsDue <= 0 ? 'early' : 'late'} on average',
        color: t['on_time_rate'] == null ? null : (_n(t['on_time_rate']) >= 80 ? AppColors.onTertiaryContainer : AppColors.warning),
      ),
      Kpi('Lead time', t['average_lead_days'] == null ? '—' : '${t['average_lead_days']} days', caption: 'Order to completion'),
      Kpi('Open now', number(_n(now['open'])), caption: '${now['in_progress']} in production · ${now['ready_for_collection']} ready'),
      Kpi('Overdue now', number(_n(now['overdue'])), caption: '${now['queued']} queued · ${now['on_hold']} on hold', color: _n(now['overdue']) > 0 ? AppColors.error : null),
    ]),
    BarChartCard(title: 'Orders and completions', labels: _labels(r), series: [
      ChartSeries('Orders', AppColors.secondaryFixedDim, _values(r, 'created')),
      ChartSeries('Completed', AppColors.secondary, _values(r, 'completed')),
    ]),
    BreakdownCard(title: 'By garment', rows: [
      for (final x in types)
        BreakdownRow(
          x['name'] as String,
          '${x['completed']} done',
          detail: '${x['created']} ordered · ${x['on_time']} on time · ${x['late']} late',
          share: most == 0 ? 0 : _n(x['completed']) / most,
        ),
    ]),
  ]);
}

List<Widget> _hours(ReportResult r) {
  final t = r.section('totals');
  BreakdownRow row(Map<String, dynamic> x, String detail) => BreakdownRow(
        x['name'] as String,
        signedPercent(x['variance_percent'] as num?),
        detail: '$detail · ${hoursLabel(_n(x['actual_seconds']))} on ${hoursLabel(_n(x['estimated_seconds']))} estimated',
        valueColor: _varianceColor(x['variance_percent'] as num?),
      );
  return _spaced([
    KpiGrid(items: [
      Kpi('Estimated', hoursLabel(_n(t['estimated_seconds'])), caption: '${t['jobs']} completed jobs'),
      Kpi('Actual', hoursLabel(_n(t['actual_seconds'])), caption: '${number(_n(t['garments']))} garments'),
      Kpi('Variance', signedHours(_n(t['variance_seconds'])), caption: '${signedPercent(t['variance_percent'] as num?)} against the estimate', color: _varianceColor(t['variance_seconds'] as num?)),
      Kpi('Per garment', t['actual_seconds_per_garment'] == null ? '—' : hoursLabel(_n(t['actual_seconds_per_garment'])), caption: 'Actual hours, completed jobs'),
      Kpi('Logged', hoursLabel(_n(t['logged_seconds'])), caption: 'All work logged in the period'),
    ]),
    BarChartCard(title: 'Hours logged', labels: _labels(r), series: [ChartSeries('Hours', AppColors.secondary, _values(r, 'logged_seconds', scale: 3600))], format: (v) => '${number(v.round())} h'),
    BreakdownCard(title: 'By garment', rows: [for (final x in r.list('by_job_type')) row(x, '${x['jobs']} jobs')], empty: 'No job was completed in this period.'),
    BreakdownCard(title: 'By stage', rows: [for (final x in r.list('by_stage')) row(x, '${x['tasks']} stages')], empty: 'No job was completed in this period.'),
  ]);
}

List<Widget> _workload(ReportResult r) {
  final t = r.section('totals');
  final b = r.section('backlog');
  return _spaced([
    KpiGrid(items: [
      Kpi('Bench load', t['load_percent'] == null ? '—' : '${t['load_percent']}%', caption: 'Planned against capacity', color: _n(t['load_percent']) > 100 ? AppColors.error : null),
      Kpi('Planned', hoursLabel(_n(t['planned_seconds'])), caption: 'Stage blocks in the calendar'),
      Kpi('Capacity', hoursLabel(_n(t['capacity_seconds'])), caption: '${number(_n(t['capacity_hours_per_day']))} h per open day'),
      Kpi('Logged', hoursLabel(_n(t['logged_seconds'])), caption: 'Work actually logged'),
      Kpi('Backlog', hoursLabel(_n(b['remaining_seconds'])), caption: '${b['jobs']} jobs in production'),
      Kpi('Due in period', hoursLabel(_n(b['due_in_period_seconds'])), caption: 'Remaining on jobs due by the end'),
    ]),
    BarChartCard(title: 'Planned against capacity', labels: _labels(r), format: (v) => '${number(v.round())} h', series: [
      ChartSeries('Capacity', AppColors.surfaceContainerHighest, _values(r, 'capacity_seconds', scale: 3600)),
      ChartSeries('Planned', AppColors.secondary, _values(r, 'planned_seconds', scale: 3600)),
      ChartSeries('Logged', AppColors.onTertiaryContainer, _values(r, 'logged_seconds', scale: 3600)),
    ]),
  ]);
}

List<Widget> _customers(BuildContext context, ReportResult r) {
  final t = r.section('totals');
  final top = r.list('top_customers');
  final most = top.fold<num>(0, (m, x) => max(m, _n(x['jobs'])));
  return _spaced([
    KpiGrid(items: [
      Kpi('New customers', number(_n(t['new_customers'])), caption: 'Added in the period'),
      Kpi('Ordering', number(_n(t['ordering_customers'])), caption: 'Placed at least one order'),
      Kpi('Returning', number(_n(t['returning_customers'])), caption: 'Had ordered before'),
      Kpi('First order', number(_n(t['first_time_customers'])), caption: 'Ordered for the first time'),
      Kpi('Active now', number(_n(t['active_customers'])), caption: 'With a job in the workshop'),
      Kpi('All customers', number(_n(t['customers'])), caption: 'Not archived'),
    ]),
    BarChartCard(title: 'New customers', labels: _labels(r), series: [ChartSeries('New', AppColors.secondary, _values(r, 'new_customers'))]),
    BreakdownCard(title: 'Top customers', rows: [
      for (final x in top)
        BreakdownRow(
          x['name'] as String,
          '${x['jobs']} job${x['jobs'] == 1 ? '' : 's'}',
          detail: '${x['completed']} completed',
          share: most == 0 ? 0 : _n(x['jobs']) / most,
          onTap: () => context.push(Routes.customer(x['customer_id'] as String)),
        ),
    ], empty: 'No orders in this period.'),
  ]);
}

List<Widget> _inventory(BuildContext context, ReportResult r, String currency) {
  final now = r.section('now');
  final t = r.section('totals');
  final consumption = r.list('consumption');
  String money(num v) => '$currency ${NumberFormatCache.money(v)}';
  return _spaced([
    KpiGrid(items: [
      Kpi('Materials', number(_n(now['materials'])), caption: '${now['ok']} in stock'),
      Kpi('Low stock', number(_n(now['low'])), caption: 'At or below the minimum', color: _n(now['low']) > 0 ? AppColors.warning : null),
      Kpi('Depleted', number(_n(now['out']) + _n(now['negative'])), caption: '${now['negative']} need a recount', color: _n(now['out']) + _n(now['negative']) > 0 ? AppColors.error : null),
      Kpi('Stock value', money(_n(now['stock_value'])), caption: 'At unit cost'),
      Kpi('Used value', money(_n(t['used_value'])), caption: 'Materials with a cost'),
      Kpi('Entries', '${t['usage_entries']} used', caption: '${t['purchase_entries']} received · ${t['write_off_entries']} written off'),
    ]),
    BarChartCard(title: 'Stock entries', labels: _labels(r), series: [
      ChartSeries('Used', AppColors.secondary, _values(r, 'usage_entries')),
      ChartSeries('Received', AppColors.onTertiaryContainer, _values(r, 'purchase_entries')),
    ]),
    BreakdownCard(title: 'Needs attention', count: '${r.list('attention').length}', rows: [
      for (final x in r.list('attention'))
        BreakdownRow(
          x['item_name'] as String,
          StockUnits.format(_n(x['quantity_on_hand']), x['unit'] as String),
          detail: 'Minimum ${StockUnits.format(_n(x['min_stock_level']), x['unit'] as String)}',
          valueColor: AppColors.error,
          onTap: () => context.push(Routes.inventoryItem(x['item_id'] as String)),
        ),
    ], empty: 'Every material is above its minimum.'),
    BreakdownCard(title: 'Consumption', rows: [
      for (final x in consumption.where((x) => _n(x['net_used']) != 0 || _n(x['written_off']) != 0))
        BreakdownRow(
          x['item_name'] as String,
          StockUnits.format(_n(x['net_used']), x['unit'] as String),
          detail: [
            x['category_name'],
            if (_n(x['returned']) > 0) '${StockUnits.format(_n(x['returned']), x['unit'] as String)} returned',
            if (_n(x['written_off']) > 0) '${StockUnits.format(_n(x['written_off']), x['unit'] as String)} written off',
            if (x['used_value'] != null) money(_n(x['used_value'])),
          ].join(' · '),
          onTap: () => context.push(Routes.inventoryItem(x['item_id'] as String)),
        ),
    ], empty: 'No material was used in this period.'),
    if (r.list('by_category').any((c) => _n(c['used_value']) > 0))
      BreakdownCard(title: 'Value by category', rows: [
        for (final c in r.list('by_category').where((c) => _n(c['used_value']) > 0))
          BreakdownRow(c['category_name'] as String, money(_n(c['used_value'])), share: _n(c['used_value']) / max(1, _n(t['used_value']))),
      ]),
  ]);
}

List<Widget> _tools(BuildContext context, ReportResult r) {
  final now = r.section('now');
  BreakdownRow due(Map<String, dynamic> x) {
    final days = x['days_until_due'] as num?;
    return BreakdownRow(
      x['tool_name'] as String,
      days == null ? '—' : (days < 0 ? '${-days} days overdue' : (days == 0 ? 'Due today' : 'In $days days')),
      detail: x['next_maintenance_date'] == null ? null : 'Due ${x['next_maintenance_date']}',
      valueColor: days != null && days < 0 ? AppColors.error : AppColors.warning,
      onTap: () => context.push(Routes.tool(x['tool_id'] as String)),
    );
  }

  final byTool = r.list('by_tool');
  final most = byTool.fold<num>(0, (m, x) => max(m, _n(x['services'])));
  const types = {'routine': 'Routine service', 'repair': 'Repair', 'calibration': 'Calibration', 'inspection': 'Inspection', 'sharpening': 'Sharpening', 'cleaning': 'Cleaning', 'other': 'Other'};
  return _spaced([
    KpiGrid(items: [
      Kpi('Tools', number(_n(now['tools'])), caption: '${now['operational']} operational'),
      Kpi('Services done', number(_n(r.section('totals')['services'])), caption: 'In the period'),
      Kpi('Overdue', number(r.list('overdue').length), color: r.list('overdue').isNotEmpty ? AppColors.error : null, caption: '${r.list('due_soon').length} due soon'),
      Kpi('Not working', number(_n(now['needs_service']) + _n(now['out_of_service'])), caption: '${now['out_of_service']} out of service'),
    ]),
    BreakdownCard(title: 'Service overdue', rows: [for (final x in r.list('overdue')) due(x)], empty: 'No service is overdue.'),
    BreakdownCard(title: 'Service due soon', rows: [for (final x in r.list('due_soon')) due(x)], empty: 'Nothing due in the next days.'),
    BarChartCard(title: 'Services done', labels: _labels(r), series: [ChartSeries('Services', AppColors.secondary, _values(r, 'services'))]),
    BreakdownCard(title: 'By tool', rows: [
      for (final x in byTool)
        BreakdownRow(x['tool_name'] as String, '${x['services']}', detail: 'Last ${x['last_service']}', share: most == 0 ? 0 : _n(x['services']) / most, onTap: () => context.push(Routes.tool(x['tool_id'] as String))),
    ]),
    BreakdownCard(title: 'By type', rows: [
      for (final x in r.list('by_type')) BreakdownRow(types[x['maintenance_type']] ?? '${x['maintenance_type']}', '${x['services']}'),
    ]),
  ]);
}

/// "24,850" / "2,682.50".
abstract final class NumberFormatCache {
  static String money(num v) {
    final whole = v.truncate();
    final cents = ((v - whole) * 100).round();
    final digits = whole.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');
    return cents == 0 ? digits : '$digits.${cents.toString().padLeft(2, '0')}';
  }
}
