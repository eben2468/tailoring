import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../app/section_scaffold.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../core/widgets/bottom_action_bar.dart';
import '../../../core/widgets/feedback.dart';
import '../../../core/widgets/gap.dart';
import '../../../core/widgets/section_header.dart';
import '../../../core/widgets/segmented_tabs.dart';
import '../../../core/widgets/state_views.dart';
import '../../customers/application/customer_providers.dart';
import '../../customers/domain/customer.dart';
import '../../sync/application/sync_providers.dart';
import '../application/measurement_providers.dart';
import '../domain/measurement.dart';
import 'measurement_widgets.dart';

/// Record a new measurement set. Every recording is kept as history; only filled-in fields are
/// saved (a partial re-measure is fine). Current values are shown as hints.
class RecordMeasurementsScreen extends ConsumerWidget {
  const RecordMeasurementsScreen({super.key, required this.customerId});

  final String customerId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final customer = ref.watch(customerProvider(customerId));
    final groups = ref.watch(measurementFieldsProvider);
    final current = ref.watch(currentMeasurementsProvider(customerId));

    return switch ((customer, groups, current)) {
      (AsyncData(value: final c), AsyncData(value: final g), AsyncData(value: final cur)) =>
        _RecordForm(customer: c, groups: g, current: cur, initialUnit: displayUnitFor(c, ref.watch(defaultMeasurementUnitProvider))),
      (AsyncError(:final error), _, _) || (_, AsyncError(:final error), _) || (_, _, AsyncError(:final error)) => DetailScaffold(
          title: 'Record measurements',
          body: ErrorView(
            error: error,
            onRetry: () => ref.invalidate(bootstrapProvider),
          ),
        ),
      _ => const DetailScaffold(title: 'Record measurements', body: LoadingView()),
    };
  }
}

class _RecordForm extends ConsumerStatefulWidget {
  const _RecordForm({required this.customer, required this.groups, required this.current, required this.initialUnit});

  final Customer customer;
  final List<MeasurementGroup> groups;
  final CurrentMeasurements current;
  final MeasurementUnit initialUnit;

  @override
  ConsumerState<_RecordForm> createState() => _RecordFormState();
}

class _RecordFormState extends ConsumerState<_RecordForm> {
  late MeasurementUnit _unit = widget.initialUnit;
  final _lengths = <int, TextEditingController>{};
  final _texts = <int, TextEditingController>{};
  final _choices = <int, String?>{};
  final _notes = TextEditingController();
  final _errors = <int, String>{};
  String? _formError;
  bool _saving = false;

  Iterable<MeasurementField> get _fields => widget.groups.expand((g) => g.fields);

  @override
  void initState() {
    super.initState();
    for (final field in _fields) {
      if (field.isLength) {
        _lengths[field.id] = TextEditingController()..addListener(_changed);
      } else if (field.valueType == 'text') {
        _texts[field.id] = TextEditingController()..addListener(_changed);
      }
    }
  }

  void _changed() => setState(() {});

  @override
  void dispose() {
    for (final c in [..._lengths.values, ..._texts.values, _notes]) {
      c.dispose();
    }
    super.dispose();
  }

  /// Converts already-typed numbers when the tailor switches units mid-entry.
  void _switchUnit(MeasurementUnit unit) {
    if (unit == _unit) return;
    for (final c in _lengths.values) {
      final value = double.tryParse(c.text.replaceAll(',', '.'));
      if (value != null) c.text = unit.format(_unit.toCm(value));
    }
    setState(() => _unit = unit);
  }

  List<(MeasurementField, MeasurementEntry)> _entries() {
    final entries = <(MeasurementField, MeasurementEntry)>[];
    for (final field in _fields) {
      if (field.isLength) {
        final value = double.tryParse(_lengths[field.id]!.text.replaceAll(',', '.'));
        if (value != null) entries.add((field, MeasurementEntry.length(field.id, value)));
      } else if (field.valueType == 'choice') {
        final choice = _choices[field.id];
        if (choice != null) entries.add((field, MeasurementEntry.text(field.id, choice)));
      } else {
        final text = _texts[field.id]!.text.trim();
        if (text.isNotEmpty) entries.add((field, MeasurementEntry.text(field.id, text)));
      }
    }
    return entries;
  }

  /// Same range rules as the server, so mistakes show instantly.
  String? _checkRange(MeasurementField field, double value) {
    final cm = _unit.toCm(value);
    if (value <= 0) return 'Enter a positive number.';
    if ((field.minCm != null && cm < field.minCm!) || (field.maxCm != null && cm > field.maxCm!)) {
      return 'Between ${_unit.format(field.minCm ?? 0)} and ${_unit.format(field.maxCm ?? 999)} ${_unit.code}';
    }
    return null;
  }

  Future<void> _save() async {
    FocusScope.of(context).unfocus();
    final entries = _entries();
    setState(() {
      _errors.clear();
      _formError = null;
      for (final (field, entry) in entries) {
        if (entry.value != null) {
          final problem = _checkRange(field, entry.value!);
          if (problem != null) _errors[field.id] = problem;
        }
      }
    });
    if (entries.isEmpty || _errors.isNotEmpty) return;

    setState(() => _saving = true);
    try {
      await ref.read(measurementsApiProvider).record(
            widget.customer.id,
            unit: _unit,
            entries: [for (final (_, e) in entries) e],
            notes: _notes.text,
          );
      ref
        ..invalidate(currentMeasurementsProvider(widget.customer.id))
        ..invalidate(measurementHistoryProvider(widget.customer.id))
        ..invalidate(customerProvider(widget.customer.id))
        ..invalidate(customerListProvider);
      if (!mounted) return;
      showAppSnack(context, '${entries.length} measurement${entries.length == 1 ? '' : 's'} saved to history.');
      context.pop();
    } on ValidationException catch (e) {
      // Server keys look like "values.3.value" — map the index back to the field.
      setState(() {
        e.fieldErrors.forEach((key, messages) {
          final index = int.tryParse(RegExp(r'^values\.(\d+)\.').firstMatch(key)?.group(1) ?? '');
          if (index != null && index < entries.length) {
            _errors[entries[index].$1.id] = messages.first;
          } else {
            _formError = messages.first;
          }
        });
      });
    } on ApiException catch (e) {
      setState(() => _formError = e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final count = _entries().length;

    return DetailScaffold(
      title: 'Record measurements',
      bottomBar: BottomActionBar(
        child: AppButton(
          label: count == 0 ? 'Enter at least one measurement' : 'Save $count measurement${count == 1 ? '' : 's'}',
          icon: Symbols.save,
          expand: true,
          loading: _saving,
          onPressed: count == 0 ? null : _save,
        ),
      ),
      body: ListView(
        padding: belowHeader(context),
        children: [
          Text(widget.customer.fullName, style: AppText.headlineLg),
          Gap.xs,
          Text(
            widget.current.isEmpty
                ? 'First measurements for this customer.'
                : 'Previous values are shown in grey. Fill in only what you measured today; everything is kept in history.',
            style: AppText.bodyMd.copyWith(color: AppColors.onSurfaceVariant),
          ),
          Gap.lg,
          SegmentedTabs(
            labels: const ['Inches (in)', 'Centimetres (cm)'],
            selected: _unit == MeasurementUnit.inch ? 0 : 1,
            onChanged: (i) => _switchUnit(i == 0 ? MeasurementUnit.inch : MeasurementUnit.cm),
          ),
          if (_formError != null) ...[Gap.md, FormBanner(message: _formError!)],
          Gap.lg,
          for (final group in widget.groups) ...[
            AppCard(
              padding: const EdgeInsets.all(AppSpace.md),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                MeasurementGroupHeader(code: group.code, title: group.name, subtitle: '${group.fields.length} field${group.fields.length == 1 ? '' : 's'}'),
                Gap.md,
                MeasurementGrid(cells: [for (final f in group.fields.where((f) => f.isLength)) _lengthInput(f)]),
                for (final f in group.fields.where((f) => !f.isLength)) ...[Gap.md, _otherInput(f)],
              ]),
            ),
            Gap.md,
          ],
          const Kicker('Posture & fit notes'),
          AppCard(
            padding: const EdgeInsets.all(AppSpace.lg),
            child: AppTextField(
              label: 'Notes for the cutter',
              controller: _notes,
              hint: 'e.g. Erect posture, right shoulder ~0.5in low',
              maxLines: 6,
              minLines: 3,
              textCapitalization: TextCapitalization.sentences,
            ),
          ),
        ],
      ),
    );
  }

  Widget _lengthInput(MeasurementField field) {
    final previous = widget.current.byField(field.id)?.valueCm;
    final error = _errors[field.id];
    return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      Padding(
        padding: const EdgeInsets.only(left: 2, bottom: 4),
        child: Text(field.label, style: AppText.labelMd.copyWith(color: AppColors.onSurfaceVariant), maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
      TextField(
        controller: _lengths[field.id],
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        textInputAction: TextInputAction.next,
        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d{0,3}([.,]\d{0,3})?'))],
        style: AppText.metricNum.copyWith(fontSize: 17),
        decoration: InputDecoration(
          hintText: previous == null ? '—' : _unit.format(previous),
          hintStyle: AppText.metricNum.copyWith(fontSize: 17, color: AppColors.outlineVariant),
          suffixText: _unit.code,
          suffixStyle: AppText.labelSm.copyWith(color: AppColors.onSurfaceVariant),
          errorText: error,
          errorMaxLines: 2,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: AppSpace.md, vertical: 12),
        ),
      ),
    ]);
  }

  Widget _otherInput(MeasurementField field) {
    final previous = widget.current.byField(field.id)?.valueText;
    if (field.valueType == 'choice') {
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(
          previous == null ? field.label : '${field.label} · last: $previous',
          style: AppText.labelMd.copyWith(color: AppColors.onSurfaceVariant),
        ),
        Gap.sm,
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final option in field.choiceOptions)
            ChoiceChip(
              label: Text(option),
              selected: _choices[field.id] == option,
              onSelected: (on) => setState(() => _choices[field.id] = on ? option : null),
              labelStyle: AppText.labelMd.copyWith(color: _choices[field.id] == option ? AppColors.onPrimary : AppColors.onSurface),
              selectedColor: AppColors.primaryContainer,
              backgroundColor: AppColors.surfaceContainerLow,
              side: BorderSide.none,
              showCheckmark: false,
              shape: RoundedRectangleBorder(borderRadius: AppRadius.full),
            ),
        ]),
        if (_errors[field.id] != null) Text(_errors[field.id]!, style: AppText.bodySm.copyWith(color: AppColors.error)),
      ]);
    }
    return AppTextField(
      label: field.label,
      controller: _texts[field.id],
      hint: previous,
      maxLines: 3,
      errorText: _errors[field.id],
      textCapitalization: TextCapitalization.sentences,
    );
  }
}
