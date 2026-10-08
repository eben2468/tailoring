/// The signed-in owner/admin (customers and workers never have accounts).
class AppUser {
  const AppUser({
    required this.id,
    required this.fullName,
    required this.email,
    required this.role,
    required this.permissions,
    this.phone,
  });

  factory AppUser.fromJson(Map<String, dynamic> json) => AppUser(
        id: (json['id'] as num).toInt(),
        fullName: json['full_name'] as String,
        email: json['email'] as String,
        phone: json['phone'] as String?,
        role: json['role'] as String,
        permissions: (json['permissions'] as List<dynamic>? ?? const []).cast<String>(),
      );

  final int id;
  final String fullName;
  final String email;
  final String? phone;
  final String role;
  final List<String> permissions;

  bool get isAdmin => permissions.contains('admin.users');

  String get firstName => fullName.trim().split(RegExp(r'\s+')).first;

  Map<String, dynamic> toJson() => {
        'id': id,
        'full_name': fullName,
        'email': email,
        'phone': phone,
        'role': role,
        'permissions': permissions,
      };
}

/// Business settings the app needs everywhere (name, currency, timezone, units).
class BusinessSettings {
  const BusinessSettings({
    required this.name,
    required this.timezone,
    required this.currency,
    required this.currencySymbol,
    required this.phoneRegion,
    required this.defaultMeasurementUnit,
  });

  factory BusinessSettings.fromJson(Map<String, dynamic> json) => BusinessSettings(
        name: json['name'] as String? ?? 'Nutɔfe',
        timezone: json['timezone'] as String? ?? 'UTC',
        currency: json['currency'] as String? ?? 'GHS',
        currencySymbol: json['currency_symbol'] as String? ?? 'GH₵',
        phoneRegion: json['phone_region'] as String? ?? 'GH',
        defaultMeasurementUnit: json['default_measurement_unit'] as String? ?? 'in',
      );

  final String name;
  final String timezone;
  final String currency;
  final String currencySymbol;
  final String phoneRegion;
  final String defaultMeasurementUnit;

  Map<String, dynamic> toJson() => {
        'name': name,
        'timezone': timezone,
        'currency': currency,
        'currency_symbol': currencySymbol,
        'phone_region': phoneRegion,
        'default_measurement_unit': defaultMeasurementUnit,
      };
}

/// Who is signed in, cached securely so the app opens without a connection.
class Session {
  const Session({required this.user, required this.business});

  factory Session.fromJson(Map<String, dynamic> json) => Session(
        user: AppUser.fromJson(json['user'] as Map<String, dynamic>),
        business: BusinessSettings.fromJson(json['business'] as Map<String, dynamic>),
      );

  final AppUser user;
  final BusinessSettings business;

  Session copyWith({AppUser? user}) => Session(user: user ?? this.user, business: business);

  Map<String, dynamic> toJson() => {'user': user.toJson(), 'business': business.toJson()};
}
