/// Measurement configuration and history models. Lengths are canonical in cm; the UI shows
/// the customer's preferred unit (or the business default).
library;

enum MeasurementUnit {
  inch('in', 'Imperial (in)'),
  cm('cm', 'Metric (cm)');

  const MeasurementUnit(this.code, this.label);

  final String code;
  final String label;

  static MeasurementUnit parse(String? code, {MeasurementUnit fallback = MeasurementUnit.inch}) =>
      MeasurementUnit.values.where((u) => u.code == code).firstOrNull ?? fallback;

  double fromCm(double cm) => this == MeasurementUnit.inch ? cm / 2.54 : cm;

  double toCm(double value) => this == MeasurementUnit.inch ? value * 2.54 : value;

  /// "42.0", "18.75", "106.7" — at least one decimal, at most two (cm: one).
  String format(double cm) {
    final value = fromCm(cm);
    final decimals = this == MeasurementUnit.cm ? 1 : 2;
    var text = value.toStringAsFixed(decimals);
    if (text.contains('.')) {
      text = text.replaceFirst(RegExp(r'0+$'), '');
      if (text.endsWith('.')) text = '${text}0';
    }
    return text;
  }
}

class MeasurementField {
  const MeasurementField({
    required this.id,
    required this.code,
    required this.label,
    required this.valueType,
    this.choiceOptions = const [],
    this.minCm,
    this.maxCm,
    this.helpText,
  });

  factory MeasurementField.fromJson(Map<String, dynamic> json) => MeasurementField(
        id: (json['id'] as num).toInt(),
        code: json['code'] as String,
        label: json['label'] as String,
        valueType: json['value_type'] as String,
        choiceOptions: (json['choice_options'] as List<dynamic>? ?? const []).cast<String>(),
        minCm: (json['min_cm'] as num?)?.toDouble(),
        maxCm: (json['max_cm'] as num?)?.toDouble(),
        helpText: json['help_text'] as String?,
      );

  final int id;
  final String code;
  final String label;

  /// length | text | choice
  final String valueType;
  final List<String> choiceOptions;
  final double? minCm;
  final double? maxCm;
  final String? helpText;

  bool get isLength => valueType == 'length';
}

class MeasurementGroup {
  const MeasurementGroup({required this.id, required this.code, required this.name, required this.fields});

  factory MeasurementGroup.fromJson(Map<String, dynamic> json) => MeasurementGroup(
        id: (json['id'] as num).toInt(),
        code: json['code'] as String,
        name: json['name'] as String,
        fields: (json['fields'] as List<dynamic>).cast<Map<String, dynamic>>().map(MeasurementField.fromJson).toList(),
      );

  final int id;
  final String code;
  final String name;
  final List<MeasurementField> fields;
}

/// Latest value of one field (from v_customer_current_measurements).
class CurrentValue {
  const CurrentValue({required this.fieldId, required this.code, required this.label, required this.groupId, required this.measuredAt, this.valueCm, this.valueText});

  factory CurrentValue.fromJson(Map<String, dynamic> json) => CurrentValue(
        fieldId: (json['field_id'] as num).toInt(),
        code: json['code'] as String,
        label: json['label'] as String,
        groupId: (json['group_id'] as num).toInt(),
        valueCm: (json['value_cm'] as num?)?.toDouble(),
        valueText: json['value_text'] as String?,
        measuredAt: DateTime.parse(json['measured_at'] as String).toLocal(),
      );

  final int fieldId;
  final String code;
  final String label;
  final int groupId;
  final double? valueCm;
  final String? valueText;
  final DateTime measuredAt;
}

class CurrentMeasurements {
  const CurrentMeasurements({required this.values, this.lastMeasuredAt});

  factory CurrentMeasurements.fromJson(Map<String, dynamic> json) => CurrentMeasurements(
        lastMeasuredAt: DateTime.tryParse(json['last_measured_at'] as String? ?? '')?.toLocal(),
        values: (json['values'] as List<dynamic>).cast<Map<String, dynamic>>().map(CurrentValue.fromJson).toList(),
      );

  final List<CurrentValue> values;
  final DateTime? lastMeasuredAt;

  bool get isEmpty => values.isEmpty;

  CurrentValue? byField(int fieldId) => values.where((v) => v.fieldId == fieldId).firstOrNull;
}

class SetValue {
  const SetValue({required this.fieldId, required this.code, required this.label, this.valueCm, this.valueText});

  factory SetValue.fromJson(Map<String, dynamic> json) => SetValue(
        fieldId: (json['field_id'] as num).toInt(),
        code: json['code'] as String? ?? '',
        label: json['label'] as String? ?? '',
        valueCm: (json['value_cm'] as num?)?.toDouble(),
        valueText: json['value_text'] as String?,
      );

  final int fieldId;
  final String code;
  final String label;
  final double? valueCm;
  final String? valueText;
}

/// One measuring session (immutable).
class MeasurementSet {
  const MeasurementSet({
    required this.id,
    required this.measuredAt,
    required this.enteredUnit,
    required this.values,
    this.notes,
    this.recordedBy,
    this.supersedesSetId,
  });

  factory MeasurementSet.fromJson(Map<String, dynamic> json) => MeasurementSet(
        id: json['id'] as String,
        measuredAt: DateTime.parse(json['measured_at'] as String).toLocal(),
        enteredUnit: MeasurementUnit.parse(json['entered_unit'] as String?),
        notes: json['notes'] as String?,
        recordedBy: json['recorded_by'] as String?,
        supersedesSetId: json['supersedes_set_id'] as String?,
        values: (json['values'] as List<dynamic>? ?? const []).cast<Map<String, dynamic>>().map(SetValue.fromJson).toList(),
      );

  final String id;
  final DateTime measuredAt;
  final MeasurementUnit enteredUnit;
  final String? notes;
  final String? recordedBy;
  final String? supersedesSetId;
  final List<SetValue> values;
}

/// One value typed into the record-measurements form.
class MeasurementEntry {
  const MeasurementEntry.length(this.fieldId, double this.value) : text = null;

  const MeasurementEntry.text(this.fieldId, String this.text) : value = null;

  final int fieldId;
  final double? value;
  final String? text;

  Map<String, dynamic> toJson() => value != null ? {'field_id': fieldId, 'value': value} : {'field_id': fieldId, 'value_text': text};
}
