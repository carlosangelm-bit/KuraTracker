import 'app_user.dart';

/// Membresía usuario↔centro. Ver 0040_center_types_memberships.sql. Lista a
/// qué centros puede entrar un usuario y con qué rol en cada uno. El centro
/// ACTIVO vive en profiles.organization_id; esta tabla alimenta el switcher
/// del ícono de apósitos.
class UserCenterMembership {
  final String id;
  final String profileId;
  final String organizationId;
  final AppRole role;
  final bool isActive;
  final DateTime createdAt;

  const UserCenterMembership({
    required this.id,
    required this.profileId,
    required this.organizationId,
    required this.role,
    this.isActive = true,
    required this.createdAt,
  });

  factory UserCenterMembership.fromJson(Map<String, dynamic> json) => UserCenterMembership(
        id: json['id'] as String,
        profileId: json['profile_id'] as String,
        organizationId: json['organization_id'] as String,
        role: AppRoleLabel.fromDb(json['role'] as String),
        isActive: json['is_active'] as bool? ?? true,
        createdAt: DateTime.parse(json['created_at'] as String),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'profile_id': profileId,
        'organization_id': organizationId,
        'role': role.dbValue,
        'is_active': isActive,
        'created_at': createdAt.toIso8601String(),
      };
}
