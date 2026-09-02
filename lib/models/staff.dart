class StaffMember {
  final String id;
  final String? profileId;
  final String folio; // K2024-0001
  final String fullName;
  final String roleTitle; // Especialista, Médico...
  final String? primarySiteId;
  final bool isActive;
  final DateTime createdAt;
  // Numero de cedula profesional; usado para prellenar la firma de la nota
  // de seguimiento obligatoria (Instructivo de Archivo).
  final String? cedulaProfesional;
  // Especialidad del profesional (para la firma NOM-024/004). Ver 0039.
  final String? especialidad;
  // Centro (organizacion) al que pertenece este personal. Se guarda de
  // forma explicita (no solo derivada via profileId) porque puede haber
  // personal administrativo SIN cuenta de acceso vinculada (profileId
  // null) que igualmente debe quedar resoluble a una organizacion. Ver
  // 0011_organizations.sql: staff.organization_id (not null).
  final String? organizationId;
  // Calendario de Acuity del profesional (0016), para agendar en su calendario.
  final int? acuityCalendarId;

  const StaffMember({
    required this.id,
    this.profileId,
    required this.folio,
    required this.fullName,
    this.roleTitle = 'Especialista',
    this.primarySiteId,
    this.isActive = true,
    required this.createdAt,
    this.cedulaProfesional,
    this.especialidad,
    this.organizationId,
    this.acuityCalendarId,
  });

  factory StaffMember.fromJson(Map<String, dynamic> json) => StaffMember(
        id: json['id'] as String,
        profileId: json['profile_id'] as String?,
        folio: json['folio'] as String,
        fullName: json['full_name'] as String,
        roleTitle: json['role_title'] as String? ?? 'Especialista',
        primarySiteId: json['primary_site_id'] as String?,
        isActive: json['is_active'] as bool? ?? true,
        createdAt: DateTime.parse(json['created_at'] as String),
        cedulaProfesional: json['cedula_profesional'] as String?,
        especialidad: json['especialidad'] as String?,
        organizationId: json['organization_id'] as String?,
        acuityCalendarId: (json['acuity_calendar_id'] as num?)?.toInt(),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'profile_id': profileId,
        'folio': folio,
        'full_name': fullName,
        'role_title': roleTitle,
        'primary_site_id': primarySiteId,
        'is_active': isActive,
        'created_at': createdAt.toIso8601String(),
        'cedula_profesional': cedulaProfesional,
        'especialidad': especialidad,
        'organization_id': organizationId,
      };
}
