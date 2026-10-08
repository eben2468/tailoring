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
import '../../../core/widgets/state_views.dart';
import '../../../core/widgets/status_pill.dart';
import '../../customers/application/customer_providers.dart';
import '../application/measurement_providers.dart';
import '../domain/measurement.dart';
import 'measurement_widgets.dart';

/// Every recorded set, newest first (nothing is ever overwritten).
class MeasurementHistoryScreen extends ConsumerWidget {
  const MeasurementHistoryScreen({super.key, required this.customerId});

  final String customerId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final history = ref.watch(measurementHistoryProvider(customerId));
    final name = ref.watch(customerProvider(customerId)).value?.fullName;

    return DetailScaffold(
      title: 'Measurement history',
      body: switch (history) {
        AsyncData(:final value) when value.isEmpty =>
          const MessageView(icon: Symbols.history, title: 'No measurements yet', message: 'Recorded measurement sets will be listed here.'),
        AsyncData(:final value) => RefreshIndicator(
            edgeOffset: MediaQuery.paddingOf(context).top + 64,
            onRefresh: () => ref.refresh(measurementHistoryProvider(customerId).future),
            child: ListView.separated(
              padding: belowHeader(context),
              itemCount: value.length + 1,
              separatorBuilder: (_, _) => Gap.sm,
              itemBuilder: (context, i) {
                if (i == 0) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: AppSpace.sm),
                    child: Text(
                      '${name ?? 'Customer'} · ${value.length} recording${value.length == 1 ? '' : 's'}',
                      style: AppText.bodyMd.copyWith(color: AppColors.onSurfaceVariant),
                    ),
                  );
                }
                final set = value[i - 1];
                return _SetCard(set: set, latest: i == 1, onTap: () => context.push(Routes.measurementSet(customerId, set.id)));
              },
            ),
          ),
        AsyncError(:final error) => ErrorView(error: error, onRetry: () => ref.invalidate(measurementHistoryProvider(customerId))),
        _ => const LoadingView(),
      },
    );
  }
}

class _SetCard extends StatelessWidget {
  const _SetCard({required this.set, required this.latest, required this.onTap});

  final MeasurementSet set;
  final bool latest;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      onTap: onTap,
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: 44,
          padding: const EdgeInsets.symmetric(vertical: 6),
          decoration: BoxDecoration(color: latest ? AppColors.primaryContainer : AppColors.surfaceContainer, borderRadius: AppRadius.control),
          child: Column(children: [
            Text('${set.measuredAt.day}', style: AppText.metricNum.copyWith(fontSize: 18, color: latest ? AppColors.onPrimary : AppColors.onSurface)),
            Text(
              Fmt.monthShort(set.measuredAt).toUpperCase(),
              style: AppText.labelSm.copyWith(fontSize: 10, color: latest ? AppColors.primaryFixedDim : AppColors.onSurfaceVariant),
            ),
          ]),
        ),
        Gap.md,
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text(Fmt.dateTime(set.measuredAt), style: AppText.titleSm, overflow: TextOverflow.ellipsis)),
              if (latest) const StatusPill(label: 'Latest', tone: StatusTone.success),
            ]),
            Text(
              '${set.values.length} value${set.values.length == 1 ? '' : 's'} · ${set.enteredUnit.code}${set.recordedBy == null ? '' : ' · by ${set.recordedBy}'}',
              style: AppText.bodySm.copyWith(color: AppColors.onSurfaceVariant),
            ),
            if (set.notes != null && set.notes!.trim().isNotEmpty) ...[
              Gap.xs,
              Text(set.notes!, style: AppText.bodySm.copyWith(color: AppColors.onSurface), maxLines: 2, overflow: TextOverflow.ellipsis),
            ],
          ]),
        ),
        const Icon(Symbols.chevron_right, size: 20, color: AppColors.outline),
      ]),
    );
  }
}

/// One recorded set with the change of each value against the previous time it was measured.
class MeasurementSetScreen extends ConsumerWidget {
  const MeasurementSetScreen({super.key, required this.customerId, required this.setId});

  final String customerId;
  final String setId;

  Future<void> _discard(BuildContext context, WidgetRef ref) async {
    final ok = await confirmAction(
      context,
      title: 'Remove this recording?',
      message: 'Use this only for a set recorded by mistake. It disappears from history and current measurements (it is kept in the audit trail).',
      confirmLabel: 'Remove recording',
      destructive: true,
    );
    if (!ok) return;
    try {
      await ref.read(measurementsApiProvider).discard(setId);
      ref
        ..invalidate(measurementHistoryProvider(customerId))
        ..invalidate(currentMeasurementsProvider(customerId))
        ..invalidate(customerProvider(customerId));
      if (context.mounted) {
        showAppSnack(context, 'Recording removed.');
        context.pop();
      }
    } on ApiException catch (e) {
      if (context.mounted) showAppSnack(context, e.message, isError: true);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final history = ref.watch(measurementHistoryProvider(customerId));
    final groups = ref.watch(measurementFieldsProvider);

    return DetailScaffold(
      title: 'Recording',
      body: switch ((history, groups)) {
        (AsyncData(value: final sets), AsyncData(value: final g)) => () {
            final index = sets.indexWhere((s) => s.id == setId);
            if (index < 0) return const MessageView(icon: Symbols.search_off, title: 'Not found', message: 'This recording no longer exists.');
            final set = sets[index];
            final older = sets.sublist(index + 1);
            final unit = set.enteredUnit;

            final lengthCells = <Widget>[];
            final tags = <String>[];
            for (final field in g.expand((group) => group.fields)) {
              final value = set.values.where((v) => v.fieldId == field.id).firstOrNull;
              if (value == null) continue;
              if (value.valueCm != null) {
                final previous = older.expand((s) => s.values).where((v) => v.fieldId == field.id && v.valueCm != null).firstOrNull;
                final diff = previous == null ? null : unit.fromCm(value.valueCm!) - unit.fromCm(previous.valueCm!);
                lengthCells.add(MeasurementCell(
                  label: field.label,
                  value: unit.format(value.valueCm!),
                  unit: unit.code,
                  delta: diff == null || diff.abs() < 0.005 ? null : '${diff > 0 ? '+' : '−'}${diff.abs().toStringAsFixed(2)}',
                ));
              } else if (value.valueText != null) {
                tags.add('${field.label}: ${value.valueText}');
              }
            }

            return ListView(padding: belowHeader(context), children: [
              Text(Fmt.dateTime(set.measuredAt), style: AppText.headlineLg),
              Gap.xs,
              Text(
                '${set.values.length} values in ${unit.label}${set.recordedBy == null ? '' : ' · recorded by ${set.recordedBy}'}',
                style: AppText.bodyMd.copyWith(color: AppColors.onSurfaceVariant),
              ),
              if (older.isNotEmpty) ...[
                Gap.xs,
                Text('Changes are compared with the previous time each value was measured.', style: AppText.bodySm.copyWith(color: AppColors.outline)),
              ],
              Gap.lg,
              if (lengthCells.isNotEmpty) AppCard(padding: const EdgeInsets.all(AppSpace.md), child: MeasurementGrid(cells: lengthCells)),
              if (tags.isNotEmpty || (set.notes?.trim().isNotEmpty ?? false)) ...[Gap.md, PostureNotesCard(notes: set.notes, tags: tags)],
              Gap.xl,
              AppButton(label: 'Remove recording', icon: Symbols.delete, variant: AppButtonVariant.danger, expand: true, onPressed: () => _discard(context, ref)),
            ]);
          }(),
        (AsyncError(:final error), _) || (_, AsyncError(:final error)) => ErrorView(error: error, onRetry: () => ref.invalidate(measurementHistoryProvider(customerId))),
        _ => const LoadingView(),
      },
    );
  }
}
