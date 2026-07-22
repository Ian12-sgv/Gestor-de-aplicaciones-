class AppUser {
  const AppUser({
    required this.id,
    required this.email,
    required this.username,
    required this.roles,
    this.firstName,
    this.lastName,
    this.status = 'ACTIVE',
    this.lastLoginAt,
    this.passwordMustChange = false,
    this.passwordChangedAt,
  });

  final String id;
  final String email;
  final String username;
  final List<String> roles;
  final String? firstName;
  final String? lastName;
  final String status;
  final String? lastLoginAt;
  final bool passwordMustChange;
  final String? passwordChangedAt;

  String get name {
    final parts = <String>[
      if (firstName != null && firstName!.trim().isNotEmpty) firstName!.trim(),
      if (lastName != null && lastName!.trim().isNotEmpty) lastName!.trim(),
    ];

    if (parts.isNotEmpty) {
      return parts.join(' ');
    }

    if (username.trim().isNotEmpty) {
      return username;
    }

    return email;
  }

  String get primaryRole => roles.isNotEmpty ? roles.first : 'EMPLOYEE';

  bool get canDeleteAppsFromStore => roles.contains('SUPER_ADMIN');

  factory AppUser.fromJson(Map<String, dynamic> json) {
    final parsedRoles = switch (json['roles']) {
      final List<dynamic> roles =>
        roles.whereType<String>().toList(growable: false),
      _ when json['role'] is String => <String>[json['role'] as String],
      _ => const <String>[],
    };

    return AppUser(
      id: (json['userId'] as String?) ?? (json['id'] as String? ?? ''),
      email: json['email'] as String? ?? '',
      username: (json['username'] as String?) ??
          (json['name'] as String?) ??
          (json['email'] as String? ?? ''),
      roles: parsedRoles,
      firstName: json['firstName'] as String?,
      lastName: json['lastName'] as String?,
      status: json['status'] as String? ?? 'ACTIVE',
      lastLoginAt: json['lastLoginAt'] as String?,
      passwordMustChange: json['passwordMustChange'] as bool? ?? false,
      passwordChangedAt: json['passwordChangedAt'] as String?,
    );
  }
}
