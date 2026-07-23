// `master`: administrador de plataforma (ver 0012_master_role.sql). A
// diferencia de `admin` (acotado a su propia organizacion via RLS), un
// master administra estructura (organizations/sites/staff/
// note_option_catalog) de TODOS los centros. NO tiene acceso a datos
// clinicos de pacientes ajenos -- esas policies (0003/0011) no le dan
// ninguna excepcion.
enum AppRole { admin, clinico, master, cuidador, enfermeria }

extension AppRoleLabel on AppRole {
  String get label {
    switch (this) {
      case AppRole.admin:
        return 'Administrador';
      case AppRole.clinico:
        return 'Personal sanitario';
      case AppRole.master:
        return 'Administrador de plataforma';
      case AppRole.cuidador:
        return 'Cuidador';
      case AppRole.enfermeria:
        return 'Enfermería';
    }
  }

  String get dbValue => name;

  bool get isMaster => this == AppRole.master;

  static AppRole fromDb(String s) =>
      AppRole.values.firstWhere((e) => e.name == s, orElse: () => AppRole.clinico);
}

class AppUser {
  final String id;
  final AppRole role;
  final String fullName;
  final String email;
  final bool isActive;
  final bool premiumEnabled;
  final String? staffId; // vinculo a staff.id si role == clinico
  // Centro (organizacion) al que pertenece este usuario. Ver
  // 0011_organizations.sql: profiles.organization_id (not null); es la
  // fuente de verdad que usa current_organization_id() en RLS.
  final String? organizationId;

  const AppUser({
    required this.id,
    required this.role,
    required this.fullName,
    required this.email,
    this.isActive = true,
    this.premiumEnabled = false,
    this.staffId,
    this.organizationId,
  });

  /// true si este usuario es el administrador de plataforma (rol
  /// `master`, ver 0012_master_role.sql). No confundir con `admin`
  /// (administrador de UNA organizacion): un master no esta atado a una
  /// sola organizacion y las pantallas de administracion deben ofrecerle
  /// un selector de centro en vez de auto-filtrar por su
  /// organizationId (que ademas puede ser null para un master).
  bool get isMaster => role == AppRole.master;

  /// Enfermería: rol restringido (observa, reporta, ejecuta). NO diagnostica ni
  /// cambia protocolo.
  bool get isNurse => role == AppRole.enfermeria;

  /// Puede crear/editar diagnóstico y protocolo (valoración, plan, consulta,
  /// diagnósticos). Solo clínico y admin; enfermería NO.
  bool get canDiagnose => role == AppRole.clinico || role == AppRole.admin;

  factory AppUser.fromJson(Map<String, dynamic> json) => AppUser(
        id: json['id'] as String,
        role: AppRoleLabel.fromDb(json['role'] as String),
        fullName: json['full_name'] as String,
        email: json['email'] as String,
        isActive: json['is_active'] as bool? ?? true,
        premiumEnabled: json['premium_enabled'] as bool? ?? false,
        staffId: json['staff_id'] as String?,
        organizationId: json['organization_id'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'role': role.dbValue,
        'full_name': fullName,
        'email': email,
        'is_active': isActive,
        'premium_enabled': premiumEnabled,
        'staff_id': staffId,
        'organization_id': organizationId,
      };

  AppUser copyWith({bool? premiumEnabled, bool? isActive, String? staffId}) => AppUser(
        id: id,
        role: role,
        fullName: fullName,
        email: email,
        isActive: isActive ?? this.isActive,
        premiumEnabled: premiumEnabled ?? this.premiumEnabled,
        staffId: staffId ?? this.staffId,
        organizationId: organizationId,
      );
}
