/// Override de habilitación de un módulo, a nivel centro / sitio / usuario.
/// Ver 0041_module_settings.sql. Sin fila para un módulo → se usa el default
/// por tipo de centro (ver ModuleKey.defaultFor). Resolución efectiva en la
/// app: usuario > sitio > centro > default-por-tipo.
class ModuleSetting {
  final String id;
  final String organizationId;
  final String? siteId; // set => alcance SITIO
  final String? profileId; // set => alcance USUARIO
  final String moduleKey;
  final bool enabled;

  const ModuleSetting({
    required this.id,
    required this.organizationId,
    this.siteId,
    this.profileId,
    required this.moduleKey,
    required this.enabled,
  });

  /// Nivel del override: 'user' | 'site' | 'center'.
  String get scope => profileId != null
      ? 'user'
      : siteId != null
          ? 'site'
          : 'center';

  factory ModuleSetting.fromJson(Map<String, dynamic> json) => ModuleSetting(
        id: json['id'] as String,
        organizationId: json['organization_id'] as String,
        siteId: json['site_id'] as String?,
        profileId: json['profile_id'] as String?,
        moduleKey: json['module_key'] as String,
        enabled: json['enabled'] as bool? ?? true,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'organization_id': organizationId,
        'site_id': siteId,
        'profile_id': profileId,
        'module_key': moduleKey,
        'enabled': enabled,
      };
}
