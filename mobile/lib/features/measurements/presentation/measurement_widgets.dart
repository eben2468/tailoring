import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/gap.dart';
import '../domain/measurement.dart';

/// Icon for a measurement group (Stitch: ruler for jacket, taper for trousers, figure for posture).
IconData measurementGroupIcon(String code) => switch (code) {
      'upper_body' => Symbols.straighten,
      'lower_body' => Symbols.height,
      'posture' => Symbols.accessibility_new,
      _ => Symbols.straighten,
    };

/// One measurement cell: label left, tabular value + unit right, on the tinted inner tile.
class MeasurementCell extends StatelessWidget {
  const MeasurementCell({super.key, required this.label, required this.value, this.unit, this.delta});

  final String label;
  final String value;
  final String? unit;

  /// Change since the previous recording, e.g. "+0.25" (history view).
  final String? delta;

  @override
  Widget build(BuildContext context) {
    return InsetTile(
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm + 2, vertical: AppSpace.sm + 2),
      child: Row(children: [
        Expanded(child: Text(label, style: AppText.bodyMd.copyWith(color: AppColors.onSurfaceVariant), maxLines: 2, overflow: TextOverflow.ellipsis)),
        const SizedBox(width: 6),
        Column(crossAxisAlignment: CrossAxisAlignment.end, mainAxisSize: MainAxisSize.min, children: [
          Row(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
            Text(value, style: AppText.metricNum),
            if (unit != null) ...[const SizedBox(width: 2), Text(unit!, style: AppText.labelSm.copyWith(color: AppColors.onSurfaceVariant))],
          ]),
          if (delta != null)
            Text(delta!, style: AppText.labelSm.copyWith(color: delta!.startsWith('-') ? AppColors.warning : AppColors.onTertiaryContainer)),
        ]),
      ]),
    );
  }
}

/// Two-column grid of cells (lengths), as in the Stitch dossier.
class MeasurementGrid extends StatelessWidget {
  const MeasurementGrid({super.key, required this.cells});

  final List<Widget> cells;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final columns = constraints.maxWidth > 520 ? 3 : 2;
      final width = (constraints.maxWidth - AppSpace.sm * (columns - 1)) / columns;
      return Wrap(
        spacing: AppSpace.sm,
        runSpacing: AppSpace.sm,
        children: [for (final cell in cells) SizedBox(width: width, child: cell)],
      );
    });
  }
}

/// "Upper Body / Jacket" card header: icon tile, title, count, optional trailing pill.
class MeasurementGroupHeader extends StatelessWidget {
  const MeasurementGroupHeader({super.key, required this.code, required this.title, required this.subtitle, this.trailing});

  final String code;
  final String title;
  final String subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(color: AppColors.surfaceContainer, borderRadius: AppRadius.control),
        child: Icon(measurementGroupIcon(code), size: 18, color: AppColors.onSurface),
      ),
      Gap.sm,
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: AppText.titleSm, overflow: TextOverflow.ellipsis),
          Text(subtitle, style: AppText.bodySm.copyWith(color: AppColors.onSurfaceVariant)),
        ]),
      ),
      ?trailing,
    ]);
  }
}

/// Small rounded tag used for posture choices ("Slope: Low right").
class MeasurementTag extends StatelessWidget {
  const MeasurementTag(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: AppColors.surfaceContainerLowest, borderRadius: BorderRadius.circular(6)),
      child: Text(text, style: AppText.labelSm.copyWith(color: AppColors.onSurface)),
    );
  }
}

/// Grouped dossier of current values (length grids + posture/notes card).
class MeasurementDossier extends StatelessWidget {
  const MeasurementDossier({
    super.key,
    required this.groups,
    required this.current,
    required this.unit,
    required this.onToggleUnit,
    this.notes,
    this.recordedBy,
  });

  final List<MeasurementGroup> groups;
  final CurrentMeasurements current;
  final MeasurementUnit unit;
  final VoidCallback onToggleUnit;
  final String? notes;
  final String? recordedBy;

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[];
    final choiceTags = <String>[];

    for (final group in groups) {
      final lengths = <Widget>[];
      for (final field in group.fields) {
        final value = current.byField(field.id);
        if (value == null) continue;
        if (field.isLength && value.valueCm != null) {
          lengths.add(MeasurementCell(label: field.label, value: unit.format(value.valueCm!), unit: unit.code));
        } else if (value.valueText != null) {
          choiceTags.add('${field.label}: ${value.valueText}');
        }
      }
      if (lengths.isEmpty) continue;
      children
        ..add(AppCard(
          padding: const EdgeInsets.all(AppSpace.md),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            MeasurementGroupHeader(
              code: group.code,
              title: group.name,
              subtitle: '${lengths.length} of ${group.fields.where((f) => f.isLength).length} measured',
              trailing: children.isEmpty ? _UnitPill(unit: unit, onTap: onToggleUnit) : null,
            ),
            Gap.md,
            MeasurementGrid(cells: lengths),
          ]),
        ))
        ..add(Gap.md);
    }

    if (choiceTags.isNotEmpty || (notes != null && notes!.trim().isNotEmpty)) {
      children.add(PostureNotesCard(notes: notes, tags: choiceTags, updatedAt: current.lastMeasuredAt, recordedBy: recordedBy));
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children);
  }
}

class _UnitPill extends StatelessWidget {
  const _UnitPill({required this.unit, required this.onTap});

  final MeasurementUnit unit;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Showing ${unit.label}. Tap to switch units.',
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(color: AppColors.secondaryFixed, borderRadius: AppRadius.full),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Text(unit.label, style: AppText.labelSm.copyWith(color: AppColors.onSecondaryFixedVariant)),
            const SizedBox(width: 2),
            const Icon(Symbols.swap_horiz, size: 14, color: AppColors.onSecondaryFixedVariant),
          ]),
        ),
      ),
    );
  }
}

/// Blue "Posture & Silhouette Notes" card from the dossier design.
class PostureNotesCard extends StatelessWidget {
  const PostureNotesCard({super.key, this.notes, this.tags = const [], this.updatedAt, this.recordedBy});

  final String? notes;
  final List<String> tags;
  final DateTime? updatedAt;
  final String? recordedBy;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpace.lg),
      decoration: BoxDecoration(color: AppColors.secondaryFixed.withValues(alpha: 0.55), borderRadius: AppRadius.card),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: 32,
          height: 32,
          decoration: const BoxDecoration(color: AppColors.secondary, shape: BoxShape.circle),
          child: const Icon(Symbols.accessibility_new, size: 18, color: AppColors.onSecondary),
        ),
        Gap.md,
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Posture & Fit Notes', style: AppText.titleSm),
            if (notes != null && notes!.trim().isNotEmpty) ...[
              Gap.xs,
              Text(notes!, style: AppText.bodyMd.copyWith(color: AppColors.onSurfaceVariant)),
            ],
            if (tags.isNotEmpty) ...[
              Gap.sm,
              Wrap(spacing: 6, runSpacing: 6, children: [for (final tag in tags) MeasurementTag(tag)]),
            ],
            if (updatedAt != null) ...[
              Gap.md,
              Row(children: [
                const Icon(Symbols.verified, size: 16, color: AppColors.onTertiaryContainer),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    'Updated ${Fmt.date(updatedAt!)}${recordedBy == null ? '' : ' by $recordedBy'}',
                    style: AppText.labelSm.copyWith(color: AppColors.onSurfaceVariant),
                  ),
                ),
              ]),
            ],
          ]),
        ),
      ]),
    );
  }
}
