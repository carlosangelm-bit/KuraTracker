class StaffMember {
  final String id;
  final String? profileId;
  final String folio; // K2024-0001
  final String fullName;
  final String roleTitle; // Kurador, Medico...
  final String? primarySiteId;
  final bool isActive;
  final DateTime createdAt;
  // Numero de cedula profesional; usado para prellenar la firma de la nota
  // de seguimiento obligatoria (Instructivo de Archivo).
  final String? cedulaProfesional;

  const StaffMember({
    required this.id,
    this.profileId,
    required this.folio,
    required this.fullName,
    this.roleTitle = 'Kurador',
    this.primarySiteId,
    this.isActive = true,
    required this.createdAt,
    this.cedulaProfesional,
  });

  factory StaffMember.fromJson(Map<String, dynamic> json) => StaffMember(
        id: json['id'] as String,
        profileId: json['profile_id'] as String?,
        folio: json['folio'] as String,
        fullName: json['full_name'] as String,
        roleTitle: json['role_title'] as String? ?? 'Kurador',
        primarySiteId: json['primary_site_id'] as String?,
        isActive: json['is_active'] as bool? ?? true,
        createdAt: DateTime.parse(json['created_at'] as String),
        cedulaProfesional: json['cedula_profesional'] as String?,
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
      };
}
