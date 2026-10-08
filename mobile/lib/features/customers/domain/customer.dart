/// A customer (they never have an account — records kept by the owner).
class Customer {
  const Customer({
    required this.id,
    required this.fullName,
    required this.version,
    required this.isArchived,
    required this.createdAt,
    this.phone,
    this.phoneAlt,
    this.email,
    this.address,
    this.notes,
    this.stylePreferences,
    this.preferredUnit,
    this.summary,
  });

  factory Customer.fromJson(Map<String, dynamic> json) => Customer(
        id: json['id'] as String,
        fullName: json['full_name'] as String,
        phone: json['phone'] as String?,
        phoneAlt: json['phone_alt'] as String?,
        email: json['email'] as String?,
        address: json['address'] as String?,
        notes: json['notes'] as String?,
        stylePreferences: json['style_preferences'] as String?,
        preferredUnit: json['preferred_unit'] as String?,
        isArchived: json['is_archived'] as bool? ?? false,
        version: (json['version'] as num).toInt(),
        summary: json['summary'] is Map<String, dynamic> ? CustomerSummary.fromJson(json['summary'] as Map<String, dynamic>) : null,
        createdAt: DateTime.parse(json['created_at'] as String).toLocal(),
      );

  final String id;
  final String fullName;
  final String? phone;
  final String? phoneAlt;
  final String? email;
  final String? address;
  final String? notes;
  final String? stylePreferences;

  /// 'in' / 'cm', or null = business default.
  final String? preferredUnit;
  final bool isArchived;
  final int version;
  final CustomerSummary? summary;
  final DateTime createdAt;
}

class CustomerSummary {
  const CustomerSummary({required this.activeJobs, required this.completedJobs, required this.measurementSets, this.lastMeasuredAt});

  factory CustomerSummary.fromJson(Map<String, dynamic> json) => CustomerSummary(
        activeJobs: (json['active_jobs'] as num?)?.toInt() ?? 0,
        completedJobs: (json['completed_jobs'] as num?)?.toInt() ?? 0,
        measurementSets: (json['measurement_sets'] as num?)?.toInt() ?? 0,
        lastMeasuredAt: DateTime.tryParse(json['last_measured_at'] as String? ?? '')?.toLocal(),
      );

  final int activeJobs;
  final int completedJobs;
  final int measurementSets;
  final DateTime? lastMeasuredAt;
}

/// Editable customer fields (create / update form).
class CustomerDraft {
  const CustomerDraft({
    required this.fullName,
    this.phone,
    this.phoneAlt,
    this.email,
    this.address,
    this.notes,
    this.stylePreferences,
    this.preferredUnit,
  });

  final String fullName;
  final String? phone;
  final String? phoneAlt;
  final String? email;
  final String? address;
  final String? notes;
  final String? stylePreferences;
  final String? preferredUnit;

  Map<String, dynamic> toJson() => {
        'full_name': fullName,
        'phone': _blankToNull(phone),
        'phone_alt': _blankToNull(phoneAlt),
        'email': _blankToNull(email),
        'address': _blankToNull(address),
        'notes': _blankToNull(notes),
        'style_preferences': _blankToNull(stylePreferences),
        'preferred_unit': preferredUnit,
      };

  static String? _blankToNull(String? value) => value == null || value.trim().isEmpty ? null : value.trim();
}

/// A customer already using a phone number (duplicate warning).
class PhoneMatch {
  const PhoneMatch({required this.id, required this.fullName, this.phone, this.isArchived = false});

  factory PhoneMatch.fromJson(Map<String, dynamic> json) => PhoneMatch(
        id: json['id'] as String,
        fullName: json['full_name'] as String,
        phone: json['phone'] as String?,
        isArchived: json['is_archived'] as bool? ?? false,
      );

  final String id;
  final String fullName;
  final String? phone;
  final bool isArchived;
}
