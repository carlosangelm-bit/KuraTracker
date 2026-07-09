enum AppRole { admin, clinico }

extension AppRoleLabel on AppRole {
  String get label {
    switch (this) {
      case AppRole.admin:
        return 'Administrador';
      case AppRole.clinico:
        return 'Personal sanitario';
    }
  }

  String get dbValue => name;

  static AppRole fromDb(String s) =>
      AppRole.values.firstWhere((e) => e.name == s, orElse: () => AppRole.clinico);
}

class AppUser {
  final String id;
  final AppRole role;
  final String fullName;
  final String email;
  final bool isActive;
  final bool premiumEnabled;
  final String? staffId; // vinculo a staff.id si role == clinico

  const AppUser({
    required this.id,
    required this.role,
    required this.fullName,
    required this.email,
    this.isActive = true,
    this.premiumEnabled = false,
    this.staffId,
  });

  factory AppUser.fromJson(Map<String, dynamic> json) => AppUser(
        id: json['id'] as String,
        role: AppRoleLabel.fromDb(json['role'] as String),
        fullName: json['full_name'] as String,
        email: json['email'] as String,
        isActive: json['is_active'] as bool? ?? true,
        premiumEnabled: json['premium_enabled'] as bool? ?? false,
        staffId: json['staff_id'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'role': role.dbValue,
        'full_name': fullName,
        'email': email,
        'is_active': isActive,
        'premium_enabled': premiumEnabled,
        'staff_id': staffId,
      };

  AppUser copyWith({bool? premiumEnabled, bool? isActive}) => AppUser(
        id: id,
        role: role,
        fullName: fullName,
        email: email,
        isActive: isActive ?? this.isActive,
        premiumEnabled: premiumEnabled ?? this.premiumEnabled,
        staffId: staffId,
      );
}
