import 'center_type.dart';

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
  // Tipo de centro (0040): determina paleta y módulos por defecto.
  final CenterType centerType;
  // Licencia premium del módulo de Insumos (0047): habilita mapeo insumo↔
  // producto, inventario, costeo y reabasto. La tienda base no la requiere.
  final bool premiumInsumos;

  const Organization({
    required this.id,
    required this.name,
    this.isActive = true,
    this.schedulingMode = 'none',
    this.brandPrimaryColor,
    this.brandLogoPath,
    this.centerType = CenterType.clinicaHeridas,
    this.premiumInsumos = false,
  });

  factory Organization.fromJson(Map<String, dynamic> json) => Organization(
        id: json['id'] as String,
        name: json['name'] as String,
        isActive: json['is_active'] as bool? ?? true,
        schedulingMode: (json['scheduling_mode'] as String?) ?? 'none',
        brandPrimaryColor: json['brand_primary_color'] as String?,
        brandLogoPath: json['brand_logo_path'] as String?,
        centerType: CenterTypeX.fromDb(json['center_type'] as String?),
        premiumInsumos: json['premium_insumos'] as bool? ?? false,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'is_active': isActive,
        'scheduling_mode': schedulingMode,
        'brand_primary_color': brandPrimaryColor,
        'brand_logo_path': brandLogoPath,
        'center_type': centerType.dbValue,
        'premium_insumos': premiumInsumos,
      };
}
