/// Centro/clinica (tenant). Ver 0011_organizations.sql (tabla
/// organizations) y 0012_master_role.sql (RLS que permite a un usuario
/// `master` leer/crear/editar/eliminar TODAS las organizaciones, no solo
/// la propia). Sigue el mismo patron simple de modelo que [Site].
class Organization {
  final String id;
  final String name;
  final bool isActive;
  // Modo de agenda del centro (0020): 'none' | 'manual' | 'acuity'.
  final String schedulingMode;
  // Branding para reportes (0024): color principal (hex) y logo.
  final String? brandPrimaryColor;
  final String? brandLogoPath;

  const Organization({
    required this.id,
    required this.name,
    this.isActive = true,
    this.schedulingMode = 'none',
    this.brandPrimaryColor,
    this.brandLogoPath,
  });

  factory Organization.fromJson(Map<String, dynamic> json) => Organization(
        id: json['id'] as String,
        name: json['name'] as String,
        isActive: json['is_active'] as bool? ?? true,
        schedulingMode: (json['scheduling_mode'] as String?) ?? 'none',
        brandPrimaryColor: json['brand_primary_color'] as String?,
        brandLogoPath: json['brand_logo_path'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'is_active': isActive,
        'scheduling_mode': schedulingMode,
        'brand_primary_color': brandPrimaryColor,
        'brand_logo_path': brandLogoPath,
      };
}
