import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../core/config/app_config.dart';
import '../models/app_user.dart';
import '../models/consultation.dart';
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

  // ---------------- Sitios ----------------

  List<Site> listSites() =>
      _store.getAll(Collections.sites).map(Site.fromJson).toList();

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

  List<StaffMember> listStaff() =>
      _store.getAll(Collections.staff).map(StaffMember.fromJson).toList();

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
  List<NoteOptionCatalogItem> listNoteOptions(NoteOptionField field) {
    return _store
        .getAll(Collections.noteOptionCatalog)
        .map(NoteOptionCatalogItem.fromJsonOrNull)
        .whereType<NoteOptionCatalogItem>()
        .where((o) => o.field == field && o.isActive)
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
  List<NoteOptionCatalogItem> listAllNoteOptions(NoteOptionField field) {
    return _store
        .getAll(Collections.noteOptionCatalog)
        .map(NoteOptionCatalogItem.fromJsonOrNull)
        .whereType<NoteOptionCatalogItem>()
        .where((o) => o.field == field)
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
  }) async {
    final data = {
      'id': _uuid.v4(),
      'field': field.dbValue,
      'label': label,
      'is_active': true,
      'created_by': createdByProfileId,
      'organization_id': organizationId,
    };
    final saved = await _store.insertRow(Collections.noteOptionCatalog, data);
    return NoteOptionCatalogItem.fromJson(saved);
  }

  Future<void> setNoteOptionActive(String id, bool active) async {
    await _store.updateRow(Collections.noteOptionCatalog, id, {'is_active': active});
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
      for (final o in listAllNoteOptions(field)) {
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
