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
  // Espejo PRIMARIO del conjunto (profiles.role). La autoridad es `roles`
  // (0096/0098); `role` se conserva para compat/revert.
  final AppRole role;
  // Conjunto de roles de la persona en su organización (profiles.roles). Puede
  // venir vacío (stores viejos/demo): en ese caso se deriva de `role`.
  final Set<AppRole> roles;
  final String fullName;
  final String email;
  final bool isActive;
  final bool premiumEnabled;
  final String? staffId; // vinculo a staff.id si tiene rol clinico
  // Centro (organizacion) al que pertenece este usuario. Ver
  // 0011_organizations.sql: profiles.organization_id (not null); es la
  // fuente de verdad que usa current_organization_id() en RLS.
  final String? organizationId;

  const AppUser({
    required this.id,
    required this.role,
    this.roles = const {},
    required this.fullName,
    required this.email,
    this.isActive = true,
    this.premiumEnabled = false,
    this.staffId,
    this.organizationId,
  });

  /// Conjunto efectivo: `roles` si viene poblado; si no, se deriva de `role`
  /// (admin ≡ {admin, clinico}, como el backfill de 0096).
  Set<AppRole> get effectiveRoles => roles.isNotEmpty
      ? roles
      : (role == AppRole.admin
          ? const {AppRole.admin, AppRole.clinico}
          : {role});

  bool hasRole(AppRole r) => effectiveRoles.contains(r);

  /// true si este usuario es el administrador de plataforma (rol
  /// `master`, ver 0012_master_role.sql). No confundir con `admin`
  /// (administrador de UNA organizacion): un master no esta atado a una
  /// sola organizacion y las pantallas de administracion deben ofrecerle
  /// un selector de centro en vez de auto-filtrar por su
  /// organizationId (que ademas puede ser null para un master).
  bool get isMaster => hasRole(AppRole.master);

  /// Administra su centro (y compra insumos). Fase B: "tiene el rol admin".
  bool get isAdmin => hasRole(AppRole.admin);

  /// Enfermería: rol restringido (observa, reporta, ejecuta). NO diagnostica ni
  /// cambia protocolo.
  bool get isNurse => hasRole(AppRole.enfermeria);

  /// Puede crear/editar diagnóstico y protocolo (valoración, plan, consulta,
  /// diagnósticos). Fase B: "tiene el rol clínico" (ya NO || admin: un admin de
  /// oficina sin rol clínico no diagnostica ni firma notas).
  bool get canDiagnose => hasRole(AppRole.clinico);

  /// Enfermería RESTRINGIDA: tiene el rol enfermería y NADA que conceda algo más
  /// amplio (diagnóstico/admin/master). Es la forma correcta para una RESTRICCIÓN
  /// (p. ej. bloquear rutas de escritura): un {clinico,enfermeria} NO debe quedar
  /// bloqueado por tener también enfermería — su rol clínico manda (punto 6 §0).
  bool get isRestrictedNurse =>
      hasRole(AppRole.enfermeria) && !canDiagnose && !isAdmin && !isMaster;

  /// Cuidador EXCLUSIVO: su único rol es cuidador. El punto 7 impone la
  /// exclusividad en el servidor; se escribe explícito para no depender de esa
  /// garantía en las restricciones de UI (punto 6 §0/§2).
  bool get isCaregiverOnly =>
      hasRole(AppRole.cuidador) && effectiveRoles.length == 1;

  factory AppUser.fromJson(Map<String, dynamic> json) => AppUser(
        id: json['id'] as String,
        role: AppRoleLabel.fromDb(json['role'] as String),
        roles: ((json['roles'] as List?) ?? const [])
            .map((e) => AppRoleLabel.fromDb(e as String))
            .toSet(),
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
        if (roles.isNotEmpty) 'roles': roles.map((r) => r.dbValue).toList(),
        'full_name': fullName,
        'email': email,
        'is_active': isActive,
        'premium_enabled': premiumEnabled,
        'staff_id': staffId,
        'organization_id': organizationId,
      };

  AppUser copyWith(
          {Set<AppRole>? roles,
          bool? premiumEnabled,
          bool? isActive,
          String? staffId}) =>
      AppUser(
        id: id,
        role: role,
        roles: roles ?? this.roles,
        fullName: fullName,
        email: email,
        isActive: isActive ?? this.isActive,
        premiumEnabled: premiumEnabled ?? this.premiumEnabled,
        staffId: staffId ?? this.staffId,
        organizationId: organizationId,
      );
}

/// Espejo escalar por precedencia (master>admin>clinico>enfermeria>cuidador),
/// igual que `primary_role()` en la BD (0098). Para derivar el `role` mirror en
/// modo demo (sin trigger) o para mostrar el rol principal.
AppRole primaryRoleOf(Set<AppRole> roles) {
  const precedence = [
    AppRole.master,
    AppRole.admin,
    AppRole.clinico,
    AppRole.enfermeria,
    AppRole.cuidador,
  ];
  for (final r in precedence) {
    if (roles.contains(r)) return r;
  }
  return AppRole.clinico;
}

/// Valida un conjunto de roles con la MISMA regla que la Edge Function
/// admin-create-user (punto 7): no vacío, sin `master` por esta vía, `cuidador`
/// exclusivo. Devuelve un mensaje de error legible, o null si es válido. La BD
/// (RLS + trigger prevent_profile_privilege_escalation, 0096) rechaza la
/// escalada aunque el cliente falle; esto es solo para dar buen error en la UI.
String? validateRoleSet(Set<AppRole> roles) {
  if (roles.isEmpty) return 'Selecciona al menos un rol.';
  if (roles.contains(AppRole.master)) {
    return "No se puede otorgar 'master' por esta vía.";
  }
  if (roles.contains(AppRole.cuidador) && roles.length > 1) {
    return "'Cuidador' es exclusivo: no puede combinarse con otros roles.";
  }
  return null;
}
