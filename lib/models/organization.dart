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
  // Add-ons premium a nivel CENTRO (módulos que se añaden a la licencia):
  // Insumos (0047: mapeo/inventario/costeo/reabasto) y Protocolo Kura+ (0049).
  final bool premiumInsumos;
  final bool premiumProtocoloKura;
  final bool shopifyMirror;
  // Alcance del inventario (0053): 'site' (por sitio) | 'center' (por centro).
  final String inventoryScope;

  const Organization({
    required this.id,
    required this.name,
    this.isActive = true,
    this.schedulingMode = 'none',
    this.brandPrimaryColor,
    this.brandLogoPath,
    this.centerType = CenterType.clinicaHeridas,
    this.premiumInsumos = false,
    this.premiumProtocoloKura = false,
    this.shopifyMirror = false,
    this.inventoryScope = 'site',
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
        premiumProtocoloKura: json['premium_protocolo_kura'] as bool? ?? false,
        shopifyMirror: json['shopify_mirror'] as bool? ?? false,
        inventoryScope: (json['inventory_scope'] as String?) ?? 'site',
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
        'premium_protocolo_kura': premiumProtocoloKura,
        'shopify_mirror': shopifyMirror,
        'inventory_scope': inventoryScope,
      };
}
