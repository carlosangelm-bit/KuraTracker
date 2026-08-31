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
  // Terminal Mercado Pago Point asignada al centro (0074). NULL = sin terminal.
  final String? mpPointDeviceId;
  // Tipo de cita de Acuity para las sesiones del plan (0080). NULL = sin config.
  final int? acuitySessionTypeId;
  // Mapeo nombre de tipo de cita de Acuity → tipo de visita Kura (0083):
  // {"<nombre>": "valoracion"|"seguimiento"}. Vacío = sin mapear.
  final Map<String, String> acuityTypeVisitMap;
  // Escalas del protocolo de hospital habilitadas por el centro (0085). null =
  // todas habilitadas.
  final List<String>? enabledScales;
  // Centro de pruebas/andamio (0103): se excluye de KPIs/listados reales.
  final bool isTest;

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
    this.mpPointDeviceId,
    this.acuitySessionTypeId,
    this.acuityTypeVisitMap = const {},
    this.enabledScales,
    this.isTest = false,
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
        mpPointDeviceId: json['mp_point_device_id'] as String?,
        acuitySessionTypeId: (json['acuity_session_type_id'] as num?)?.toInt(),
        acuityTypeVisitMap: (json['acuity_type_visit_map'] as Map?)?.map(
                (k, v) => MapEntry(k.toString(), v.toString())) ??
            const {},
        enabledScales: (json['enabled_scales'] as List?)
            ?.map((e) => e.toString())
            .toList(),
        isTest: json['is_test'] as bool? ?? false,
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
        'mp_point_device_id': mpPointDeviceId,
        'acuity_session_type_id': acuitySessionTypeId,
        'acuity_type_visit_map': acuityTypeVisitMap,
        'enabled_scales': enabledScales,
        'is_test': isTest,
      };
}
