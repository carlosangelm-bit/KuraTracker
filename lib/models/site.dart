class Site {
  final String id;
  final String name;
  final String kind; // clinica | domicilio | hospital | otro
  final String? address;
  final bool isActive;
  // Centro (organizacion) dueno de este sitio. Ver
  // 0011_organizations.sql: sites.organization_id (not null). El personal
  // de esa organizacion puede operar en CUALQUIERA de sus sitios (no solo
  // en su primary_site_id, que es solo un default opcional).
  final String? organizationId;
  // Tipo de cita de Acuity para las sesiones del plan en este sitio (0081).
  final int? acuitySessionTypeId;

  const Site({
    required this.id,
    required this.name,
    required this.kind,
    this.address,
    this.isActive = true,
    this.organizationId,
    this.acuitySessionTypeId,
  });

  factory Site.fromJson(Map<String, dynamic> json) => Site(
        id: json['id'] as String,
        name: json['name'] as String,
        kind: json['kind'] as String? ?? 'clinica',
        address: json['address'] as String?,
        isActive: json['is_active'] as bool? ?? true,
        organizationId: json['organization_id'] as String?,
        acuitySessionTypeId: (json['acuity_session_type_id'] as num?)?.toInt(),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'kind': kind,
        'address': address,
        'is_active': isActive,
        'organization_id': organizationId,
        'acuity_session_type_id': acuitySessionTypeId,
      };
}
