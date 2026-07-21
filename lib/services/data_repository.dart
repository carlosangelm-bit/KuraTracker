import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../core/config/app_config.dart';
import '../models/adverse_event.dart';
import '../models/app_user.dart';
import '../models/consultation.dart';
import '../models/manual_appointment.dart';
import '../models/organization.dart';
import '../models/patient.dart';
import '../models/note_option_catalog.dart';
import '../models/site.dart';
import '../models/staff.dart';
import '../models/treatment_plan.dart';
import '../models/wound.dart';
import '../engine/models/kura_engine_output.dart';
import '../engine/models/kura_engine_enums.dart';
import 'local_db/demo_seed.dart';
import 'local_db/local_store.dart';
import 'remote/data_store.dart';
import 'remote/supabase_data_store.dart';

const _uuid = Uuid();

/// Repositorio unico de datos para toda la app.
///
/// Encapsula el almacen de datos (via la interfaz [DataStore]) exponiendo
/// una API tipada por entidad. La estructura de esta clase refleja 1:1 el
/// esquema SQL de Supabase (supabase/migrations).
///
/// BACKEND: segun [AppConfig.isSupabaseConfigured], `instance()` construye
/// un [SupabaseDataStore] (produccion, Postgrest + RLS en vivo) o un
/// [LocalStoreDataStore] (demo offline-first con datos sinteticos
/// precargados). En ambos casos, [DataRepository] usa exactamente la misma
/// API publica sincrona-en-lectura / asincrona-en-escritura, por lo que
/// ninguna pantalla necesita saber cual backend esta activo.
class DataRepository {
  final DataStore _store;

  DataRepository._(this._store);

  static DataRepository? _instance;

  static Future<DataRepository> instance() async {
    if (_instance != null) return _instance!;

    if (AppConfig.isSupabaseConfigured) {
      final store = SupabaseDataStore(Supabase.instance.client);
      // Si hay sesion activa (usuario ya logueado en un run anterior de la
      // app / refresh de pagina), hidrata la cache de una vez. Si no hay
      // sesion aun, hydrate() se llama explicitamente desde el login
      // (ver SessionController) una vez autenticado, para que las policies
      // de RLS ya tengan auth.uid() disponible.
      if (Supabase.instance.client.auth.currentSession != null) {
        await store.hydrate();
      }
      _instance = DataRepository._(store);
      return _instance!;
    }

    final localStore = await LocalStore.instance();
    await DemoSeed.ensureSeeded(localStore);
    _instance = DataRepository._(LocalStoreDataStore(localStore));
    return _instance!;
  }

  /// Fuerza la re-hidratacion de la cache (backend Supabase) tras login.
  /// No-op en modo local.
  Future<void> hydrateAfterLogin() async {
    final store = _store;
    if (store is SupabaseDataStore) {
      await store.hydrate();
    }
  }

  /// Limpia la cache en memoria (backend Supabase) tras logout, para que
  /// un siguiente login (posiblemente de otro usuario) no vea datos
  /// residuales antes de re-hidratar. No-op en modo local.
  void clearCacheOnLogout() {
    final store = _store;
    if (store is SupabaseDataStore) {
      store.clearCache();
    }
  }

  /// Solo disponible en modo demo local (SharedPreferences). En produccion
  /// (Supabase) esto no aplica: los datos de prueba se cargan una sola vez
  /// via el script de seed SQL (ver supabase/seed/), no desde la app.
  Future<void> resetDemoData() async {
    if (_store is LocalStoreDataStore) {
      final localStore = await LocalStore.instance();
      await DemoSeed.resetAndReseed(localStore);
    }
  }

  // ---------------- Auth / usuarios ----------------
  // NOTA: en modo Supabase, el login/logout real (email+password via
  // Supabase Auth) vive en SessionController (core/providers/session_provider.dart).
  // Estos metodos siguen sirviendo para leer/administrar la tabla `profiles`
  // (p.ej. pantalla de administracion de usuarios) en ambos backends.

  List<AppUser> listUsers() {
    final profiles = _store.getAll(Collections.profiles);
    final staffList = _store.getAll(Collections.staff);
    return profiles.map((p) {
      final staffMatch = staffList.firstWhere(
        (s) => s['profile_id'] == p['id'],
        orElse: () => const {},
      );
      return AppUser.fromJson({
        ...p,
        'staff_id': staffMatch.isEmpty ? null : staffMatch['id'],
      });
    }).toList();
  }

  AppUser? findUserByEmail(String email) {
    final match = listUsers().where(
      (u) => u.email.toLowerCase() == email.toLowerCase(),
    );
    return match.isEmpty ? null : match.first;
  }

  Future<void> setUserActive(String userId, bool active) async {
    await _store.updateRow(Collections.profiles, userId, {'is_active': active});
  }

  Future<void> setUserPremium(String userId, bool premium) async {
    await _store.updateRow(Collections.profiles, userId, {'premium_enabled': premium});
  }

  /// Cambia el rol de un usuario (admin <-> clinico) desde el panel de
  /// Administracion / Plataforma. En Supabase, la RLS de profiles
  /// (profiles_update_own_or_admin) + el trigger anti-escalada
  /// (prevent_profile_privilege_escalation) permiten esto SOLO a admin/master;
  /// un clinico no puede auto-promoverse (0006/0012/0017).
  Future<void> setUserRole(String userId, AppRole role) async {
    await _store.updateRow(Collections.profiles, userId, {'role': role.dbValue});
  }

  /// Da de alta un usuario CON cuenta de acceso (login).
  ///
  /// En Supabase esto NO puede hacerse solo con la anon key: crear la cuenta
  /// en Auth requiere service role, asi que se delega en la Edge Function
  /// `admin-create-user` (que valida que el llamador sea admin/master, crea la
  /// cuenta, el profile y -para clinicos- el staff, y devuelve una contrasena
  /// temporal cuando no hay SMTP configurado). Ver supabase/functions/README.md.
  ///
  /// En modo demo local (sin Supabase) no hay Auth real: se crea directamente
  /// el profile (+ staff si es clinico) para que la pantalla sea funcional en
  /// la demo; [CreatedUser.tempPassword] queda null en ese caso.
  Future<CreatedUser> createUserWithLogin({
    required String email,
    required String fullName,
    required AppRole role,
    required String organizationId,
    String? phone,
    String? cedulaProfesional,
    String? primarySiteId,
    String roleTitle = 'Kurador',
  }) async {
    final store = _store;
    if (store is SupabaseDataStore) {
      Map<String, dynamic> data;
      try {
        data = await store.invokeFunction('admin-create-user', {
          'email': email,
          'fullName': fullName,
          'role': role.dbValue,
          'organizationId': organizationId,
          if (phone != null && phone.isNotEmpty) 'phone': phone,
          if (cedulaProfesional != null && cedulaProfesional.isNotEmpty)
            'cedulaProfesional': cedulaProfesional,
          if (primarySiteId != null) 'primarySiteId': primarySiteId,
          'roleTitle': roleTitle,
        });
      } on FunctionException catch (e) {
        throw Exception(_edgeErrorMessage(e));
      }
      if (data['error'] != null) throw Exception(data['error'].toString());
      // Refresca profiles y staff para que la lista refleje el alta sin
      // re-login (la Edge Function escribio con service role, fuera de la cache).
      await store.refreshCollection(Collections.profiles);
      await store.refreshCollection(Collections.staff);
      return CreatedUser(
        uid: data['uid'] as String,
        email: (data['email'] ?? email) as String,
        tempPassword: data['tempPassword'] as String?,
        role: role,
      );
    }

    // Modo demo local: sin Auth real.
    final uid = _uuid.v4();
    await _store.insertRow(Collections.profiles, {
      'id': uid,
      'role': role.dbValue,
      'full_name': fullName,
      'email': email,
      'is_active': true,
      'premium_enabled': false,
      'organization_id': organizationId,
    });
    if (role == AppRole.clinico) {
      await createStaff(
        fullName: fullName,
        roleTitle: roleTitle,
        organizationId: organizationId,
        primarySiteId: primarySiteId,
        profileId: uid,
        cedulaProfesional: cedulaProfesional,
      );
    }
    return CreatedUser(uid: uid, email: email, tempPassword: null, role: role);
  }

  String _edgeErrorMessage(FunctionException e) {
    final details = e.details;
    if (details is Map && details['error'] != null) return details['error'].toString();
    if (details is String && details.isNotEmpty) return details;
    return 'No se pudo crear el usuario (código ${e.status}).';
  }

  // ---------------- Organizaciones (centros) ----------------
  // (organizations, ver 0011_organizations.sql + 0012_master_role.sql).
  // Solo un usuario `master` puede listar TODAS las organizaciones y
  // crear/editar/eliminar directamente via REST (RLS de 0012); un admin
  // normal solo ve la suya (organizations_select_own), consistente con
  // el resto del panel de administracion.

  List<Organization> listOrganizations() =>
      _store.getAll(Collections.organizations).map(Organization.fromJson).toList();

  /// Crea una organizacion (centro) nueva. Uso exclusivo del area
  /// "Plataforma" (solo master, ver PlatformHomeScreen): a diferencia del
  /// RPC create_organization_with_admin (que ademas promueve al llamador
  /// a admin de la organizacion nueva), esto es un INSERT directo -- el
  /// master sigue siendo master, no se vincula automaticamente como admin
  /// de la organizacion creada.
  Future<Organization> createOrganization(String name) async {
    final data = {
      'id': _uuid.v4(),
      'name': name,
      'is_active': true,
    };
    final saved = await _store.insertRow(Collections.organizations, data);
    return Organization.fromJson(saved);
  }

  Future<void> setOrganizationActive(String organizationId, bool active) async {
    await _store.updateRow(Collections.organizations, organizationId, {'is_active': active});
  }

  // ---------------- Agenda: modo por centro + citas manuales ----------------
  // (0020_manual_scheduling.sql). scheduling_mode: none | manual | acuity.

  /// Modo de agenda del centro (none | manual | acuity). 'none' si no se
  /// resuelve la organización.
  String schedulingModeFor(String? organizationId) {
    if (organizationId == null) return 'none';
    final org = listOrganizations().where((o) => o.id == organizationId);
    return org.isEmpty ? 'none' : org.first.schedulingMode;
  }

  /// Fija el branding del centro (color principal + logo) para los reportes.
  /// En Supabase usa el RPC set_org_branding (RLS de organizations es
  /// master-only); en demo actualiza la fila directo.
  Future<void> setOrgBranding(
    String organizationId, {
    String? primaryColor,
    String? logoPath,
  }) async {
    final store = _store;
    if (store is SupabaseDataStore) {
      await store.callRpc('set_org_branding', {
        'p_org': organizationId,
        'p_primary_color': primaryColor,
        'p_logo_path': logoPath,
      });
      await store.refreshCollection(Collections.organizations);
    } else {
      await _store.updateRow(Collections.organizations, organizationId, {
        'brand_primary_color': primaryColor,
        'brand_logo_path': logoPath,
      });
    }
  }

  Future<void> setSchedulingMode(String organizationId, String mode) async {
    final store = _store;
    if (store is SupabaseDataStore) {
      // La RLS de organizations solo permite UPDATE al master; para que el admin
      // del centro pueda activar su modo de agenda se usa un RPC acotado
      // (set_scheduling_mode, 0021) y luego se refresca la cache.
      await store.callRpc('set_scheduling_mode', {
        'p_org': organizationId,
        'p_mode': mode,
      });
      await store.refreshCollection(Collections.organizations);
    } else {
      await _store.updateRow(
          Collections.organizations, organizationId, {'scheduling_mode': mode});
    }
  }

  /// Citas manuales del centro (admin) o de un Kurador (clínico). El aislamiento
  /// real lo aplica la RLS; el filtro aquí acota la vista.
  List<ManualAppointment> listManualAppointments({String? organizationId, String? staffId}) =>
      _store
          .getAll(Collections.manualAppointments)
          .map(ManualAppointment.fromJson)
          .where((a) =>
              (organizationId == null || a.organizationId == organizationId) &&
              (staffId == null || a.staffId == staffId))
          .toList();

  Future<ManualAppointment> createManualAppointment({
    required String organizationId,
    required DateTime datetime,
    String? staffId,
    String? patientId,
    String? title,
    DateTime? endTime,
    String? notes,
    String? address,
    String? contactName,
    String? contactPhone,
    String? photoPath,
    String? createdByProfileId,
  }) async {
    final now = DateTime.now().toIso8601String();
    final data = {
      'id': _uuid.v4(),
      'organization_id': organizationId,
      'staff_id': staffId,
      'patient_id': patientId,
      'title': title,
      'datetime': datetime.toIso8601String(),
      'end_time': endTime?.toIso8601String(),
      'notes': notes,
      'address': address,
      'contact_name': contactName,
      'contact_phone': contactPhone,
      'photo_path': photoPath,
      'status': 'scheduled',
      'created_by': createdByProfileId,
      'created_at': now,
      'updated_at': now,
    };
    final saved = await _store.insertRow(Collections.manualAppointments, data);
    return ManualAppointment.fromJson(saved);
  }

  Future<ManualAppointment> updateManualAppointment(
    String id, {
    String? staffId,
    bool clearStaff = false,
    String? patientId,
    bool clearPatient = false,
    String? title,
    DateTime? datetime,
    DateTime? endTime,
    bool clearEndTime = false,
    String? notes,
    String? status,
    String? address,
    String? contactName,
    String? contactPhone,
    String? photoPath,
  }) async {
    final patch = <String, dynamic>{'updated_at': DateTime.now().toIso8601String()};
    if (clearStaff) {
      patch['staff_id'] = null;
    } else if (staffId != null) {
      patch['staff_id'] = staffId;
    }
    if (clearPatient) {
      patch['patient_id'] = null;
    } else if (patientId != null) {
      patch['patient_id'] = patientId;
    }
    if (title != null) patch['title'] = title;
    if (datetime != null) patch['datetime'] = datetime.toIso8601String();
    if (clearEndTime) {
      patch['end_time'] = null;
    } else if (endTime != null) {
      patch['end_time'] = endTime.toIso8601String();
    }
    if (notes != null) patch['notes'] = notes;
    if (status != null) patch['status'] = status;
    if (address != null) patch['address'] = address;
    if (contactName != null) patch['contact_name'] = contactName;
    if (contactPhone != null) patch['contact_phone'] = contactPhone;
    if (photoPath != null) patch['photo_path'] = photoPath;
    final saved = await _store.updateRow(Collections.manualAppointments, id, patch);
    return ManualAppointment.fromJson(saved);
  }

  /// Refleja el contacto de una cita manual en el expediente del paciente
  /// (cuidador), SOLO si esos campos están vacíos (no pisa datos del clínico).
  /// Opcionalmente agrega una nota (p.ej. domicilio de tratamiento) a
  /// background_notes. Usado por el alta manual cuando el paciente ya existía.
  Future<void> updatePatientContactIfEmpty(
    String patientId, {
    String? caregiverName,
    String? caregiverPhone,
    String? appendBackgroundNote,
  }) async {
    final rows =
        _store.getAll(Collections.patients).where((r) => r['id'] == patientId).toList();
    if (rows.isEmpty) return;
    final r = rows.first;
    final patch = <String, dynamic>{};
    if (((r['caregiver_name'] as String?) ?? '').isEmpty &&
        (caregiverName ?? '').isNotEmpty) {
      patch['caregiver_name'] = caregiverName;
      patch['has_identified_caregiver'] = true;
    }
    if (((r['caregiver_phone'] as String?) ?? '').isEmpty &&
        (caregiverPhone ?? '').isNotEmpty) {
      patch['caregiver_phone'] = caregiverPhone;
      patch['has_identified_caregiver'] = true;
    }
    if ((appendBackgroundNote ?? '').isNotEmpty) {
      final existing = ((r['background_notes'] as String?) ?? '').trim();
      patch['background_notes'] =
          existing.isEmpty ? appendBackgroundNote : '$existing\n$appendBackgroundNote';
    }
    if (patch.isNotEmpty) {
      await _store.updateRow(Collections.patients, patientId, patch);
    }
  }

  Future<void> cancelManualAppointment(String id) async {
    await _store.updateRow(Collections.manualAppointments, id,
        {'status': 'canceled', 'updated_at': DateTime.now().toIso8601String()});
  }

  // ---------------- Acuity por centro (Fase 2, 0022) ----------------
  // Solo en modo Supabase; las credenciales se guardan/consultan por RPC
  // (nunca se lee la API key completa desde el cliente).

  Future<void> setOrgAcuityCredentials(String orgId, String userId, String apiKey) async {
    final store = _store;
    if (store is! SupabaseDataStore) {
      throw Exception('La configuración de Acuity solo está disponible con Supabase.');
    }
    await store.callRpc('set_org_acuity_credentials', {
      'p_org': orgId,
      'p_user_id': userId,
      'p_api_key': apiKey,
    });
  }

  Future<AcuityConfigStatus?> getOrgAcuityStatus(String orgId) async {
    final store = _store;
    if (store is! SupabaseDataStore) return null;
    final rows = await store.callRpcResult('get_org_acuity_status', {'p_org': orgId});
    if (rows is List && rows.isNotEmpty) {
      final r = (rows.first as Map).cast<String, dynamic>();
      return AcuityConfigStatus(
        userId: r['user_id']?.toString() ?? '',
        keyLast4: r['key_last4']?.toString() ?? '',
        webhooksRegistered: r['webhooks_registered'] == true,
      );
    }
    return null;
  }

  Future<void> markAcuityWebhooks(String orgId, bool registered) async {
    final store = _store;
    if (store is! SupabaseDataStore) return;
    await store.callRpc('mark_org_acuity_webhooks', {
      'p_org': orgId,
      'p_registered': registered,
    });
  }

  // ---------------- Sitios ----------------

  /// Lista los sitios. [organizationId] es un filtro OPCIONAL usado
  /// exclusivamente por el area de Plataforma (master): para un admin
  /// normal, se omite (null) y la lista completa ya viene acotada a su
  /// propia organizacion por RLS (Supabase) o porque hoy solo existe 1
  /// organizacion en el seed local de demo. Un master, en cambio, ve en
  /// cache TODAS las organizaciones (RLS de 0012_master_role.sql) y
  /// necesita este filtro para acotar la vista al centro que eligio en
  /// el selector.
  List<Site> listSites({String? organizationId}) => _store
      .getAll(Collections.sites)
      .map(Site.fromJson)
      .where((s) => organizationId == null || s.organizationId == organizationId)
      .toList();

  /// Crea un sitio nuevo del centro. `site.organizationId` es obligatorio en
  /// la practica (columna not null en Supabase, ver 0011_organizations.sql):
  /// el llamador (pantalla de Administracion) debe construir el [Site] con
  /// `organizationId: session.user!.organizationId`.
  Future<Site> createSite(Site site) async {
    final data = site.toJson();
    if ((data['id'] as String?)?.isEmpty ?? true) data['id'] = _uuid.v4();
    final saved = await _store.insertRow(Collections.sites, data);
    return Site.fromJson(saved);
  }

  /// Edita un sitio existente (nombre, tipo, direccion). Solo se envian al
  /// backend los campos que el llamador especifica explicitamente.
  Future<Site> updateSite(
    String id, {
    String? name,
    String? kind,
    String? address,
    bool clearAddress = false,
  }) async {
    final patch = <String, dynamic>{};
    if (name != null) patch['name'] = name;
    if (kind != null) patch['kind'] = kind;
    if (clearAddress) {
      patch['address'] = null;
    } else if (address != null) {
      patch['address'] = address;
    }
    final saved = await _store.updateRow(Collections.sites, id, patch);
    return Site.fromJson(saved);
  }

  Future<void> setSiteActive(String siteId, bool active) async {
    await _store.updateRow(Collections.sites, siteId, {'is_active': active});
  }

  // ---------------- Personal sanitario ----------------

  /// [organizationId] es un filtro OPCIONAL, mismo proposito que en
  /// [listSites]: solo se pasa desde el area de Plataforma (master).
  List<StaffMember> listStaff({String? organizationId}) => _store
      .getAll(Collections.staff)
      .map(StaffMember.fromJson)
      .where((s) => organizationId == null || s.organizationId == organizationId)
      .toList();

  /// Busca un miembro del personal por id. Devuelve `null` si no existe.
  /// Util para prefills (p.ej. cedula profesional en la nota de
  /// seguimiento) sin tener que exponer una consulta directa a la tabla.
  StaffMember? getStaff(String staffId) {
    for (final json in _store.getAll(Collections.staff)) {
      if (json['id'] == staffId) return StaffMember.fromJson(json);
    }
    return null;
  }

  /// Crea un registro de personal sanitario. [organizationId] es requerido
  /// (staff.organization_id not null, ver 0011_organizations.sql): el
  /// llamador siempre debe pasar `session.user!.organizationId` (el centro
  /// del admin que da de alta al personal), nunca el del profile vinculado
  /// (que puede ser null si es alta administrativa sin cuenta).
  Future<StaffMember> createStaff({
    required String fullName,
    required String roleTitle,
    required String? organizationId,
    String? primarySiteId,
    String? profileId,
    String? cedulaProfesional,
  }) async {
    final existing = _store.getAll(Collections.staff);
    final year = DateTime.now().year;
    final countThisYear = existing
        .where((s) => (s['folio'] as String).startsWith('K$year'))
        .length;
    final folio = 'K$year-${(countThisYear + 1).toString().padLeft(4, '0')}';

    final data = {
      'id': _uuid.v4(),
      'profile_id': profileId,
      'folio': folio,
      'full_name': fullName,
      'role_title': roleTitle,
      'primary_site_id': primarySiteId,
      'is_active': true,
      'created_at': DateTime.now().toIso8601String(),
      'cedula_profesional': cedulaProfesional,
      'organization_id': organizationId,
    };
    final saved = await _store.insertRow(Collections.staff, data);
    return StaffMember.fromJson(saved);
  }

  Future<void> setStaffActive(String staffId, bool active) async {
    await _store.updateRow(Collections.staff, staffId, {'is_active': active});
  }

  /// Edita un registro de personal existente (nombre, cargo, sitio
  /// principal y/o vinculo a un profile_id). Solo se envian al backend los
  /// campos que el llamador especifica explicitamente; para desvincular un
  /// profile_id ya asignado, usar [clearProfileId].
  Future<StaffMember> updateStaff(
    String staffId, {
    String? fullName,
    String? roleTitle,
    String? primarySiteId,
    bool clearPrimarySiteId = false,
    String? profileId,
    bool clearProfileId = false,
    String? cedulaProfesional,
    bool clearCedulaProfesional = false,
  }) async {
    final patch = <String, dynamic>{};
    if (fullName != null) patch['full_name'] = fullName;
    if (roleTitle != null) patch['role_title'] = roleTitle;
    if (clearPrimarySiteId) {
      patch['primary_site_id'] = null;
    } else if (primarySiteId != null) {
      patch['primary_site_id'] = primarySiteId;
    }
    if (clearProfileId) {
      patch['profile_id'] = null;
    } else if (profileId != null) {
      patch['profile_id'] = profileId;
    }
    if (clearCedulaProfesional) {
      patch['cedula_profesional'] = null;
    } else if (cedulaProfesional != null) {
      patch['cedula_profesional'] = cedulaProfesional;
    }
    final saved = await _store.updateRow(Collections.staff, staffId, patch);
    return StaffMember.fromJson(saved);
  }

  /// Perfiles (`profiles`) que aun NO tienen una fila en `staff` vinculada
  /// via profile_id — candidatos para dar de alta como personal sanitario
  /// operativo desde el panel de Administración, sin tocar SQL a mano.
  /// Incluye perfiles admin (un admin puede necesitar staff_id propio para
  /// poder crear consultas, ver aclaración del modelo de datos).
  List<AppUser> listProfilesWithoutStaffLink() {
    final linkedProfileIds = _store
        .getAll(Collections.staff)
        .map((s) => s['profile_id'] as String?)
        .whereType<String>()
        .toSet();
    return listUsers().where((u) => !linkedProfileIds.contains(u.id)).toList();
  }

  /// Fix admin-clinico (licencia individual, ajuste obligatorio #3): un
  /// admin que NUNCA recibio una fila de `staff` (p.ej. el admin del seed
  /// de demo, o un admin creado antes de esta funcion / sin pasar por
  /// create_organization_with_admin en Supabase) no puede crear una
  /// consulta porque consultations.staff_id es NOT NULL. En vez de
  /// bloquear el flujo clinico (como hacian antes ConsultationHubScreen y
  /// FollowUpCaptureScreen con `if (staffId == null) return`), se
  /// aprovisiona SU staff de forma perezosa (lazy) la primera vez que se
  /// necesita: si ya existe una fila de staff vinculada a este profile_id,
  /// se devuelve su id; si no, se crea una (folio '' -- igual que hace el
  /// RPC create_organization_with_admin en Postgres, ver
  /// 0011_organizations.sql secc. 5) y se devuelve el id nuevo.
  ///
  /// Se usa desde SessionController (refreshUser/login/restore) para que
  /// `session.user.staffId` quede resuelto ANTES de que la UI lo lea, sin
  /// que cada pantalla clinica tenga que conocer este detalle.
  Future<String> ensureAdminStaffId(AppUser adminUser) async {
    final existing = _store
        .getAll(Collections.staff)
        .where((s) => s['profile_id'] == adminUser.id);
    if (existing.isNotEmpty) return existing.first['id'] as String;

    final created = await createStaff(
      fullName: adminUser.fullName,
      roleTitle: 'Administrador',
      organizationId: adminUser.organizationId,
      profileId: adminUser.id,
    );
    return created.id;
  }

  // ---------------- Catalogo de conceptos de nota de seguimiento ----------------
  // (note_option_catalog, ver 0010_note_option_catalog.sql). Configurable
  // por el centro (admin) desde el panel de Configuracion; el personal
  // clinico solo lee/selecciona (RLS: SELECT para autenticados, INSERT/
  // UPDATE/DELETE solo admin via is_admin()). No es tabla auditada por el
  // trigger (catalogo administrativo, no dato clinico de paciente).

  /// Conceptos activos para un campo dado, en el orden en que fueron
  /// creados (los precargados por la migracion 0010 primero).
  ///
  /// Usa `fromJsonOrNull` (no `fromJson`) y descarta silenciosamente
  /// cualquier fila malformada (id/label nulo o de tipo inesperado): este
  /// metodo se invoca sin try/catch desde codigo de build() en varias
  /// pantallas, y una unica fila corrupta NO debe tumbar toda la lista ni
  /// la pantalla que la muestra (ver bug "pantalla en blanco al crear
  /// concepto de catalogo", 2026-07-15).
  /// [organizationId] es un filtro OPCIONAL, mismo proposito que en
  /// [listSites]: solo se pasa desde el area de Plataforma (master).
  List<NoteOptionCatalogItem> listNoteOptions(NoteOptionField field, {String? organizationId}) {
    return _store
        .getAll(Collections.noteOptionCatalog)
        .map(NoteOptionCatalogItem.fromJsonOrNull)
        .whereType<NoteOptionCatalogItem>()
        .where((o) =>
            o.field == field &&
            o.isActive &&
            (organizationId == null || o.organizationId == organizationId))
        .toList();
  }

  /// Todos los conceptos (activos e inactivos) de un campo, para la
  /// pantalla de Configuracion del admin, donde tambien se pueden
  /// reactivar conceptos previamente desactivados.
  ///
  /// Ver nota de `listNoteOptions()` sobre `fromJsonOrNull`: este metodo en
  /// particular es el que `_NoteCatalogTabState.build()` llama sin
  /// try/catch en cada rebuild (incluido el rebuild disparado por
  /// `setState()` tras un alta exitosa en `_addOption()`), por lo que es
  /// el punto exacto donde una fila cacheada malformada causaba la
  /// pantalla en blanco reportada.
  /// [organizationId] es un filtro OPCIONAL, mismo proposito que en
  /// [listSites]: solo se pasa desde el area de Plataforma (master).
  List<NoteOptionCatalogItem> listAllNoteOptions(NoteOptionField field, {String? organizationId}) {
    return _store
        .getAll(Collections.noteOptionCatalog)
        .map(NoteOptionCatalogItem.fromJsonOrNull)
        .whereType<NoteOptionCatalogItem>()
        .where((o) =>
            o.field == field &&
            (organizationId == null || o.organizationId == organizationId))
        .toList();
  }

  /// Agrega un concepto nuevo al catalogo. Uso previsto: (a) pantalla de
  /// Configuracion del admin, y (b) alta "sobre la marcha" cuando quien
  /// captura la nota de seguimiento es admin y escribe algo nuevo en
  /// "Otro" (se le ofrece guardarlo; si es personal clinico, "Otro" se
  /// usa solo como texto de esa nota y este metodo NO se invoca).
  Future<NoteOptionCatalogItem> createNoteOption({
    required NoteOptionField field,
    required String label,
    required String? organizationId,
    String? createdByProfileId,
    KuraTag? kuraTag,
  }) async {
    final data = {
      'id': _uuid.v4(),
      'field': field.dbValue,
      'label': label,
      'is_active': true,
      'created_by': createdByProfileId,
      'organization_id': organizationId,
      'kura_tag': kuraTag?.dbValue,
    };
    final saved = await _store.insertRow(Collections.noteOptionCatalog, data);
    return NoteOptionCatalogItem.fromJson(saved);
  }

  Future<void> setNoteOptionActive(String id, bool active) async {
    await _store.updateRow(Collections.noteOptionCatalog, id, {'is_active': active});
  }

  /// Actualiza SOLO la etiqueta kura_tag de un concepto existente (dropdown
  /// de NoteCatalogTab en Administracion). `null` limpia la etiqueta
  /// ("Sin etiqueta"). No toca ningun otro campo del concepto.
  Future<void> setNoteOptionKuraTag(String id, KuraTag? kuraTag) async {
    await _store.updateRow(Collections.noteOptionCatalog, id, {'kura_tag': kuraTag?.dbValue});
  }

  /// Borra un concepto del catalogo (pantalla de Configuracion). La
  /// politica RLS `note_option_catalog_admin_delete` (migracion 0011)
  /// ya restringe esto a admins de la misma organizacion; aqui solo se
  /// delega el DELETE. No afecta el historial: las notas de seguimiento
  /// ya guardadas persisten el texto del concepto, no una referencia a
  /// esta fila, asi que borrar solo lo quita de las opciones futuras.
  Future<void> deleteNoteOption(String id) async {
    await _store.deleteRow(Collections.noteOptionCatalog, id);
  }

  /// Resultado de una importacion masiva del catalogo desde CSV (pantalla
  /// de Configuracion): cuantos conceptos se agregaron (no existian),
  /// cuantos se actualizaron (existian con `activo` distinto al de la
  /// fila del CSV) y cuantos se omitieron (fila invalida: seccion
  /// desconocida o concepto vacio).
  Future<NoteOptionImportSummary> bulkImportNoteOptions(
    List<NoteOptionImportRow> rows, {
    required String organizationId,
    String? createdByProfileId,
  }) async {
    var added = 0;
    var updated = 0;
    var skipped = 0;
    final errors = <String>[];

    // Todos los conceptos actuales del centro (activos e inactivos), para
    // poder decidir merge (agregar vs actualizar) sin duplicar por
    // (field, label) dentro de esta misma organizacion.
    final existingByFieldLabel = <String, NoteOptionCatalogItem>{};
    for (final field in NoteOptionField.values) {
      for (final o in listAllNoteOptions(field, organizationId: organizationId)) {
        existingByFieldLabel['${field.dbValue}::${o.label.trim().toLowerCase()}'] = o;
      }
    }

    for (var i = 0; i < rows.length; i++) {
      final row = rows[i];
      final rowNum = i + 2; // +1 encabezado, +1 base-1 para el usuario
      final field = NoteOptionFieldDb.fromCsvSeccion(row.seccion);
      final label = row.concepto.trim();
      if (field == null) {
        skipped++;
        errors.add('Fila $rowNum: sección "${row.seccion}" no reconocida (omitida).');
        continue;
      }
      if (label.isEmpty) {
        skipped++;
        errors.add('Fila $rowNum: concepto vacío (omitida).');
        continue;
      }

      final key = '${field.dbValue}::${label.toLowerCase()}';
      final existing = existingByFieldLabel[key];
      if (existing == null) {
        final created = await createNoteOption(
          field: field,
          label: label,
          organizationId: organizationId,
          createdByProfileId: createdByProfileId,
        );
        existingByFieldLabel[key] = created;
        added++;
      } else if (existing.isActive != row.activo) {
        await setNoteOptionActive(existing.id, row.activo);
        existingByFieldLabel[key] = NoteOptionCatalogItem(
          id: existing.id,
          field: existing.field,
          label: existing.label,
          isActive: row.activo,
          createdBy: existing.createdBy,
          organizationId: existing.organizationId,
          kuraTag: existing.kuraTag,
        );
        updated++;
      }
      // Si existe y `activo` ya coincide: no-op (no cuenta como agregado
      // ni actualizado; se refleja en skipped=false pero tampoco se
      // reporta como error, simplemente no incrementa ningun contador
      // "de cambio" -- el resumen final solo informa added/updated/skipped
      // donde skipped es exclusivamente filas invalidas).
    }

    return NoteOptionImportSummary(
      added: added,
      updated: updated,
      skipped: skipped,
      errors: errors,
    );
  }

  /// Catalogo base curado (misma precarga que la migracion
  /// 0010_note_option_catalog.sql y el espejo de DemoSeed) para las 4
  /// secciones de la nota de seguimiento. Se usa como "punto de partida"
  /// para un centro nuevo que aun no configuro nada (pantalla vacia, ver
  /// captura reportada: un centro creado desde Plataforma por el master
  /// no arrastra ningun concepto -- por diseno, para no imponerle
  /// contenido sin pedirselo -- pero de ahi la necesidad de este boton).
  /// Tercer elemento (kuraTag): etiqueta de mapeo al motor Protocolo Kura+
  /// (ver 0013_note_option_catalog_kura_tag.sql) sembrada por defecto para
  /// los conceptos base curados cuya correspondencia con un metodo del
  /// motor es clara y no ambigua. Los conceptos sin correspondencia clara
  /// (p.ej. "Interconsulta", evolucion, la mayoria de materiales sueltos)
  /// quedan en null ("Sin etiqueta") a proposito -- etiquetar de mas seria
  /// forzar auto-selecciones que no reflejan realmente ese metodo.
  static const List<(NoteOptionField, String, KuraTag?)> defaultNoteOptionCatalog = [
    (NoteOptionField.careType, 'Curación ambulatoria', null),
    (NoteOptionField.careType, 'Visita domiciliaria', null),
    (NoteOptionField.careType, 'Curación en hospitalización', null),
    (NoteOptionField.careType, 'Interconsulta', null),
    (NoteOptionField.careType, 'Desbridamiento programado', KuraTag.desbridamiento),
    (NoteOptionField.procedureDesc, 'Limpieza con solución salina y cambio de apósito', KuraTag.limpieza),
    (NoteOptionField.procedureDesc, 'Desbridamiento cortante parcial', KuraTag.desbridamiento),
    (NoteOptionField.procedureDesc, 'Desbridamiento autolítico/enzimático', KuraTag.desbridamiento),
    (NoteOptionField.procedureDesc, 'Toma de medidas y fotografía de control', null),
    (NoteOptionField.procedureDesc, 'Aplicación de terapia compresiva', KuraTag.compresion),
    (NoteOptionField.procedureDesc, 'Educación al paciente/cuidador', KuraTag.educacion),
    (NoteOptionField.materialsUsed, 'Solución salina 0.9%', KuraTag.limpieza),
    (NoteOptionField.materialsUsed, 'Yodopovidona 10%', KuraTag.antimicrobiano),
    (NoteOptionField.materialsUsed, 'Apósito de espuma (foam)', KuraTag.aposito),
    (NoteOptionField.materialsUsed, 'Apósito de alginato', KuraTag.aposito),
    (NoteOptionField.materialsUsed, 'Apósito hidrocoloide', KuraTag.aposito),
    (NoteOptionField.materialsUsed, 'Gasa estéril', KuraTag.aposito),
    (NoteOptionField.materialsUsed, 'Vendaje de compresión', KuraTag.compresion),
    (NoteOptionField.evolution, 'Favorable, con reducción de área', null),
    (NoteOptionField.evolution, 'Estable, sin cambios significativos', null),
    (NoteOptionField.evolution, 'Sin avance esperado para la semana de tratamiento', null),
    (NoteOptionField.evolution, 'Signos de infección local', null),
    (NoteOptionField.evolution, 'Mejoría del tejido de granulación', null),
  ];

  /// Carga el catalogo base curado para el centro [organizationId]:
  /// solo AGREGA los conceptos que aun no existan en ese centro (mismo
  /// (field, label), comparado sin importar mayusculas/espacios). A
  /// diferencia de [bulkImportNoteOptions] (pensado para CSV, donde el
  /// admin edita explicitamente la columna `activo` y por eso SI
  /// sincroniza el estado activo/inactivo de las filas existentes), este
  /// metodo NUNCA toca una fila que ya exista -- ni la reactiva ni cambia
  /// su texto -- para no deshacer una desactivacion deliberada del admin
  /// solo porque el texto coincide con el catalogo base. Pensado para el
  /// boton "Cargar catálogo base" de [NoteCatalogTab], util sobre todo
  /// para un centro nuevo (todo vacio, ver createOrganization() que a
  /// proposito no siembra catalogo) que quiere arrancar rapido sin
  /// configurar todo desde cero.
  Future<NoteOptionImportSummary> seedDefaultNoteOptions({
    required String organizationId,
    String? createdByProfileId,
  }) async {
    var added = 0;

    final existingLabelsByField = <NoteOptionField, Set<String>>{};
    for (final field in NoteOptionField.values) {
      existingLabelsByField[field] = listAllNoteOptions(field, organizationId: organizationId)
          .map((o) => o.label.trim().toLowerCase())
          .toSet();
    }

    for (final entry in defaultNoteOptionCatalog) {
      final field = entry.$1;
      final label = entry.$2;
      final kuraTag = entry.$3;
      final existingLabels = existingLabelsByField[field]!;
      if (existingLabels.contains(label.trim().toLowerCase())) continue;

      await createNoteOption(
        field: field,
        label: label,
        organizationId: organizationId,
        createdByProfileId: createdByProfileId,
        kuraTag: kuraTag,
      );
      existingLabels.add(label.trim().toLowerCase());
      added++;
    }

    return NoteOptionImportSummary(added: added, updated: 0, skipped: 0, errors: const []);
  }

  List<Patient> listPatientsForStaff(String staffId) {
    final assignments = _store
        .getAll(Collections.staffPatientAssignments)
        .where((a) => a['staff_id'] == staffId)
        .map((a) => a['patient_id'] as String)
        .toSet();
    return listAllPatients().where((p) => assignments.contains(p.id)).toList();
  }

  // ---------------- Pacientes ----------------

  List<Patient> listAllPatients() =>
      _store.getAll(Collections.patients).map(Patient.fromJson).toList();

  Patient? getPatient(String id) {
    final match = _store.getAll(Collections.patients).where((p) => p['id'] == id);
    return match.isEmpty ? null : Patient.fromJson(match.first);
  }

  /// Crea un expediente de paciente. [organizationId] es requerido
  /// (patients.organization_id not null, ver 0011_organizations.sql --
  /// aislamiento critico de pacientes entre centros): el llamador siempre
  /// debe pasar `session.user!.organizationId`.
  Future<Patient> createPatient({
    required String fullName,
    required String? organizationId,
    DateTime? birthDate,
    String? sex,
    String? primarySiteId,
    String? mobility,
    bool hasIdentifiedCaregiver = false,
    String? caregiverName,
    String? caregiverPhone,
    bool fragilePatient = false,
    String? backgroundNotes,
    String folioPrefix = 'EXP',
  }) async {
    final existing = _store.getAll(Collections.patients);
    final year = DateTime.now().year;
    final countThisYear = existing
        .where((p) => (p['folio'] as String).contains('$year'))
        .length;
    final folio = '$folioPrefix$year-${(countThisYear + 1).toString().padLeft(4, '0')}';

    final data = {
      'id': _uuid.v4(),
      'folio': folio,
      'full_name': fullName,
      'birth_date': birthDate?.toIso8601String().substring(0, 10),
      'sex': sex,
      'primary_site_id': primarySiteId,
      'mobility': mobility,
      'has_identified_caregiver': hasIdentifiedCaregiver,
      'caregiver_name': caregiverName,
      'caregiver_phone': caregiverPhone,
      'fragile_patient': fragilePatient,
      'background_notes': backgroundNotes,
      'ekare_external_id': null,
      'is_active': true,
      'created_at': DateTime.now().toIso8601String(),
      'organization_id': organizationId,
    };
    final saved = await _store.insertRow(Collections.patients, data);
    return Patient.fromJson(saved);
  }

  Future<void> assignPatientToStaff(String patientId, String staffId) async {
    final all = _store.getAll(Collections.staffPatientAssignments);
    final exists = all.any((a) => a['patient_id'] == patientId && a['staff_id'] == staffId);
    if (!exists) {
      await _store.insertRow(Collections.staffPatientAssignments, {
        'staff_id': staffId,
        'patient_id': patientId,
      });
    }
  }

  List<PatientComorbidity> listComorbidities(String patientId) => _store
      .getAll(Collections.patientComorbidities)
      .where((c) => c['patient_id'] == patientId)
      .map(PatientComorbidity.fromJson)
      .toList();

  Future<void> upsertComorbidity(PatientComorbidity comorbidity) async {
    await _store.upsertRow(Collections.patientComorbidities, comorbidity.toJson());
  }

  // ---------------- Consultas ----------------

  List<Consultation> listConsultationsForPatient(String patientId) => _store
      .getAll(Collections.consultations)
      .where((c) => c['patient_id'] == patientId)
      .map(Consultation.fromJson)
      .toList()
    ..sort((a, b) => b.visitDate.compareTo(a.visitDate));

  Consultation? getConsultation(String id) {
    final match = _store.getAll(Collections.consultations).where((c) => c['id'] == id);
    return match.isEmpty ? null : Consultation.fromJson(match.first);
  }

  Future<Consultation> createConsultation({
    required String patientId,
    required String staffId,
    required String siteId,
    required VisitType visitType,
    required DateTime visitDate,
    Map<String, dynamic>? vitalSigns,
    bool isDraft = false,
    // Nota de seguimiento obligatoria (Instructivo de Archivo), aplica a
    // visit_type=seguimiento; ver migracion 0008.
    String? followUpCareType,
    String? followUpProcedureDesc,
    String? followUpMaterialsUsed,
    String? followUpEvolution,
    String? followUpSignedBy,
    String? followUpSignedLicense,
  }) async {
    final data = {
      'id': _uuid.v4(),
      'patient_id': patientId,
      'staff_id': staffId,
      'site_id': siteId,
      'visit_type': visitType.dbValue,
      'visit_date': visitDate.toIso8601String().substring(0, 10),
      'vital_signs': vitalSigns,
      'is_draft': isDraft,
      'created_at': DateTime.now().toIso8601String(),
      'follow_up_care_type': followUpCareType,
      'follow_up_procedure_desc': followUpProcedureDesc,
      'follow_up_materials_used': followUpMaterialsUsed,
      'follow_up_evolution': followUpEvolution,
      'follow_up_signed_by': followUpSignedBy,
      'follow_up_signed_license': followUpSignedLicense,
    };
    final saved = await _store.insertRow(Collections.consultations, data);
    return Consultation.fromJson(saved);
  }

  Future<void> updateConsultationDraftStatus(String id, bool isDraft) async {
    await _store.updateRow(Collections.consultations, id, {'is_draft': isDraft});
  }

  // ---------------- Eventos adversos (COFEPRIS) ----------------

  /// Bitácora de eventos adversos de un paciente, del más reciente al más
  /// antiguo (por fecha de ocurrencia). Ver migración 0025_adverse_events.sql.
  List<AdverseEvent> listAdverseEventsForPatient(String patientId) => _store
      .getAll(Collections.adverseEvents)
      .where((e) => e['patient_id'] == patientId)
      .map(AdverseEvent.fromJson)
      .toList()
    ..sort((a, b) => b.occurredAt.compareTo(a.occurredAt));

  AdverseEvent? getAdverseEvent(String id) {
    final match =
        _store.getAll(Collections.adverseEvents).where((e) => e['id'] == id);
    return match.isEmpty ? null : AdverseEvent.fromJson(match.first);
  }

  /// Crea un evento adverso. `organizationId` y `staffId` los pasa la pantalla
  /// desde `session.user` (mismo patrón que createPatient/createConsultation):
  /// el repo no lee la sesión. `organizationId` es obligatorio por RLS
  /// (adverse_events.organization_id not null + policy de inserción).
  Future<AdverseEvent> createAdverseEvent({
    required String organizationId,
    required String patientId,
    required String? staffId,
    String? woundId,
    String? consultationId,
    required DateTime occurredAt,
    required String type,
    required AdverseEventSeverity severity,
    Set<AdverseEventAlarmSign> alarmSigns = const {},
    String? description,
    String? actionsTaken,
    String? evolution,
    DateTime? reportedAt,
  }) async {
    final event = AdverseEvent(
      id: _uuid.v4(),
      organizationId: organizationId,
      patientId: patientId,
      staffId: staffId,
      woundId: woundId,
      consultationId: consultationId,
      occurredAt: occurredAt,
      type: type,
      severity: severity,
      alarmSigns: alarmSigns,
      description: description,
      actionsTaken: actionsTaken,
      evolution: evolution,
      reportedAt: reportedAt,
      createdAt: DateTime.now(),
    );
    final saved =
        await _store.insertRow(Collections.adverseEvents, event.toJson());
    return AdverseEvent.fromJson(saved);
  }

  /// Marca un evento como reportado a la autoridad (registra reported_at).
  /// Usado por el recordatorio de reporte ≤24 h de los eventos centinela.
  Future<AdverseEvent> markAdverseEventReported(
    String id, {
    DateTime? reportedAt,
  }) async {
    final saved = await _store.updateRow(Collections.adverseEvents, id, {
      'reported_at': (reportedAt ?? DateTime.now()).toIso8601String(),
    });
    return AdverseEvent.fromJson(saved);
  }

  // ---------------- Heridas ----------------

  List<Wound> listWoundsForPatient(String patientId) => _store
      .getAll(Collections.wounds)
      .where((w) => w['patient_id'] == patientId)
      .map(Wound.fromJson)
      .toList();

  Wound? getWound(String id) {
    final match = _store.getAll(Collections.wounds).where((w) => w['id'] == id);
    return match.isEmpty ? null : Wound.fromJson(match.first);
  }

  Future<Wound> createWound(Map<String, dynamic> data) async {
    final row = Map<String, dynamic>.from(data);
    row['id'] = row['id'] ?? _uuid.v4();
    row['created_at'] = row['created_at'] ?? DateTime.now().toIso8601String();
    row['is_active'] = row['is_active'] ?? true;
    final saved = await _store.insertRow(Collections.wounds, row);
    return Wound.fromJson(saved);
  }

  // ---------------- Evaluaciones ----------------

  List<WoundAssessment> listAssessmentsForWound(String woundId) => _store
      .getAll(Collections.woundAssessments)
      .where((a) => a['wound_id'] == woundId)
      .map(WoundAssessment.fromJson)
      .toList();

  Future<WoundAssessment> createAssessment(Map<String, dynamic> data) async {
    final row = Map<String, dynamic>.from(data);
    row['id'] = row['id'] ?? _uuid.v4();
    final saved = await _store.insertRow(Collections.woundAssessments, row);
    return WoundAssessment.fromJson(saved);
  }

  // ---------------- Mediciones ----------------

  List<WoundMeasurement> listMeasurementsForWound(String woundId) {
    final list = _store
        .getAll(Collections.woundMeasurements)
        .where((m) => m['wound_id'] == woundId)
        .map(WoundMeasurement.fromJson)
        .toList();
    list.sort((a, b) => a.measuredAt.compareTo(b.measuredAt));
    return list;
  }

  Future<WoundMeasurement> createMeasurement(Map<String, dynamic> data) async {
    final row = Map<String, dynamic>.from(data);
    row['id'] = row['id'] ?? _uuid.v4();
    final saved = await _store.insertRow(Collections.woundMeasurements, row);
    return WoundMeasurement.fromJson(saved);
  }

  // ---------------- Perfusion / nutricion ----------------

  PerfusionNutritionData? getPerfusionForWound(String woundId) {
    final list = _store
        .getAll(Collections.perfusionNutrition)
        .where((p) => p['wound_id'] == woundId)
        .toList();
    if (list.isEmpty) return null;
    return PerfusionNutritionData.fromJson(list.last);
  }

  Future<PerfusionNutritionData> upsertPerfusion(Map<String, dynamic> data) async {
    final row = Map<String, dynamic>.from(data);
    row['id'] = row['id'] ?? _uuid.v4();
    final saved = await _store.upsertRow(Collections.perfusionNutrition, row);
    return PerfusionNutritionData.fromJson(saved);
  }

  // ---------------- Fotos ----------------

  List<WoundPhoto> listPhotosForWound(String woundId) => _store
      .getAll(Collections.woundPhotos)
      .where((p) => p['wound_id'] == woundId)
      .map(WoundPhoto.fromJson)
      .toList();

  Future<WoundPhoto> createPhoto(Map<String, dynamic> data) async {
    final row = Map<String, dynamic>.from(data);
    row['id'] = row['id'] ?? _uuid.v4();
    row['taken_at'] = row['taken_at'] ?? DateTime.now().toIso8601String();
    final saved = await _store.insertRow(Collections.woundPhotos, row);
    return WoundPhoto.fromJson(saved);
  }

  // ---------------- Planes de tratamiento ----------------

  TreatmentPlan? getTreatmentPlanForConsultation(String consultationId, String woundId) {
    final plans = _store
        .getAll(Collections.treatmentPlans)
        .where((p) => p['consultation_id'] == consultationId && p['wound_id'] == woundId);
    if (plans.isEmpty) return null;
    final planJson = plans.first;
    final components = _store
        .getAll(Collections.treatmentComponents)
        .where((c) => c['treatment_plan_id'] == planJson['id'])
        .map(TreatmentComponentRecord.fromJson)
        .toList();
    return TreatmentPlan.fromJson(planJson, components: components);
  }

  Future<TreatmentPlan> saveTreatmentPlan({
    required String consultationId,
    required String woundId,
    required bool usedKuraProtocol,
    String? finalDescription,
    required List<TreatmentComponentRecord> components,
  }) async {
    final existing = _store
        .getAll(Collections.treatmentPlans)
        .where((p) => p['consultation_id'] == consultationId && p['wound_id'] == woundId);
    final planId = existing.isEmpty ? _uuid.v4() : existing.first['id'] as String;

    final planData = {
      'id': planId,
      'consultation_id': consultationId,
      'wound_id': woundId,
      'used_kura_protocol': usedKuraProtocol,
      'final_description': finalDescription,
    };
    await _store.upsertRow(Collections.treatmentPlans, planData);

    // Reemplaza componentes: borra los existentes del plan y crea los nuevos.
    // (Se hace fila por fila via la interfaz DataStore, en vez de un
    // "replace masivo", para que funcione igual sobre LocalStore y sobre
    // Postgrest sin necesitar un endpoint de bulk-replace).
    final existingComponents = _store
        .getAll(Collections.treatmentComponents)
        .where((c) => c['treatment_plan_id'] == planId)
        .toList();
    for (final c in existingComponents) {
      await _store.deleteRow(Collections.treatmentComponents, c['id'] as String);
    }
    for (var i = 0; i < components.length; i++) {
      final c = components[i];
      await _store.insertRow(Collections.treatmentComponents, {
        'id': c.id.isEmpty ? _uuid.v4() : c.id,
        'treatment_plan_id': planId,
        'method': c.method,
        'product': c.product,
        'origin': c.origin.dbValue,
        'sort_order': i,
      });
    }

    return getTreatmentPlanForConsultation(consultationId, woundId)!;
  }

  // ---------------- Recomendaciones Kura+ ----------------

  Future<void> saveKuraRecommendation({
    required String consultationId,
    required String woundId,
    String? treatmentPlanId,
    required KuraEngineOutput output,
    required ClinicianDecision decision,
    String? clinicianNotes,
  }) async {
    final data = {
      'id': _uuid.v4(),
      'consultation_id': consultationId,
      'wound_id': woundId,
      'treatment_plan_id': treatmentPlanId,
      'model_version': output.modelVersion,
      'adjustments_version': output.adjustmentsVersion,
      'rules_version': output.rulesVersion,
      'prob_a': output.probabilities.entries.firstWhere((e) => e.key.code == 'A').value,
      'prob_b': output.probabilities.entries.firstWhere((e) => e.key.code == 'B').value,
      'prob_c': output.probabilities.entries.firstWhere((e) => e.key.code == 'C').value,
      'dominant_scenario': output.dominantScenario.code,
      'commercial_phenotype': output.dominantScenario.commercialPhenotype,
      'regimen': output.regimen.map((r) => r.toJson()).toList(),
      'interconsultas': output.interconsultas.map((i) => i.toJson()).toList(),
      'alertas': output.alertas,
      'debug_features': output.debugFeatures,
      'debug_raw_scores': output.debugRawScores,
      'clinician_decision': decision.name,
      'clinician_decision_at': DateTime.now().toIso8601String(),
      'clinician_notes': clinicianNotes,
      'generated_at': output.generatedAt.toIso8601String(),
      'created_at': DateTime.now().toIso8601String(),
    };
    await _store.insertRow(Collections.kuraRecommendations, data);
  }

  List<Map<String, dynamic>> listRecommendationsForWound(String woundId) => _store
      .getAll(Collections.kuraRecommendations)
      .where((r) => r['wound_id'] == woundId)
      .toList();

  // ---------------- Checkpoints Sheehan ----------------

  Future<void> saveSheehanCheckpoint(Map<String, dynamic> data) async {
    final row = Map<String, dynamic>.from(data);
    row['id'] = row['id'] ?? _uuid.v4();
    row['created_at'] = row['created_at'] ?? DateTime.now().toIso8601String();
    await _store.insertRow(Collections.sheehanCheckpoints, row);
  }

  List<Map<String, dynamic>> listSheehanCheckpointsForWound(String woundId) => _store
      .getAll(Collections.sheehanCheckpoints)
      .where((c) => c['wound_id'] == woundId)
      .toList();

  // ---------------- Auditoria ----------------
  // La auditoria de patients/wounds/consultations/measurements/
  // treatment_plans/kura_recommendations/staff/profiles la genera
  // EXCLUSIVAMENTE el trigger AFTER INSERT/UPDATE/DELETE de Postgres
  // (audit_trigger_fn en 0002_triggers_and_functions.sql), que corre como
  // SECURITY DEFINER. Ningun flujo clinico de la app debe insertar
  // manualmente en audit_log: la tabla solo tiene politica de SELECT para
  // admin (audit_log_admin_select) y deliberadamente NO tiene politica de
  // INSERT, para que un cliente no pueda falsificar la bitacora. Por eso
  // se eliminaron los antiguos metodos logAudit()/listAuditLog() de este
  // repositorio (y sus 3 llamadas desde la UI): un INSERT directo del
  // cliente a audit_log siempre sera rechazado por RLS con 403. Si se
  // necesita registrar una accion adicional, se debe agregar/ajustar el
  // trigger en Postgres, nunca una llamada manual desde el cliente.
}

/// Resultado del alta de un usuario con login (createUserWithLogin). En
/// Supabase, [tempPassword] es una contrasena temporal generada por la Edge
/// Function para compartir con el usuario cuando no hay SMTP configurado; en
/// modo demo local es null (no hay Auth real).
class CreatedUser {
  final String uid;
  final String email;
  final String? tempPassword;
  final AppRole role;

  const CreatedUser({
    required this.uid,
    required this.email,
    required this.tempPassword,
    required this.role,
  });
}

/// Estado de la conexión de Acuity de un centro (sin exponer la API key: solo
/// el user id, los últimos 4 de la key y si los webhooks quedaron registrados).
class AcuityConfigStatus {
  final String userId;
  final String keyLast4;
  final bool webhooksRegistered;
  const AcuityConfigStatus({
    required this.userId,
    required this.keyLast4,
    required this.webhooksRegistered,
  });
}

/// Una fila cruda del CSV de importacion del catalogo (Configuracion >
/// catalogo de la nota de seguimiento). `activo` ya viene parseado a bool
/// (columna CSV "activo" con valores "true"/"false"/"1"/"0"/"si"/"no"; el
/// parseo tolerante vive en la pantalla que lee el archivo, no aqui).
class NoteOptionImportRow {
  final String seccion;
  final String concepto;
  final bool activo;

  const NoteOptionImportRow({
    required this.seccion,
    required this.concepto,
    required this.activo,
  });
}

/// Resumen de una importacion masiva (bulkImportNoteOptions), mostrado al
/// admin en un dialogo tras cargar el CSV.
class NoteOptionImportSummary {
  final int added;
  final int updated;
  final int skipped;
  final List<String> errors;

  const NoteOptionImportSummary({
    required this.added,
    required this.updated,
    required this.skipped,
    required this.errors,
  });
}
