/// Centro/clinica (tenant). Ver 0011_organizations.sql (tabla
/// organizations) y 0012_master_role.sql (RLS que permite a un usuario
/// `master` leer/crear/editar/eliminar TODAS las organizaciones, no solo
/// la propia). Sigue el mismo patron simple de modelo que [Site].
class Organization {
  final String id;
  final String name;
  final bool isActive;

  const Organization({
    required this.id,
    required this.name,
    this.isActive = true,
  });

  factory Organization.fromJson(Map<String, dynamic> json) => Organization(
        id: json['id'] as String,
        name: json['name'] as String,
        isActive: json['is_active'] as bool? ?? true,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'is_active': isActive,
      };
}
