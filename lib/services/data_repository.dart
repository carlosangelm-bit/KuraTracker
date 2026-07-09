import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../core/config/app_config.dart';
import '../models/app_user.dart';
import '../models/consultation.dart';
import '../models/patient.dart';
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

  Future<Site> createSite(Site site) async {
    final data = site.toJson();
    if ((data['id'] as String?)?.isEmpty ?? true) data['id'] = _uuid.v4();
    final saved = await _store.insertRow(Collections.sites, data);
    return Site.fromJson(saved);
  }

  // ---------------- Personal sanitario ----------------

  List<StaffMember> listStaff() =>
      _store.getAll(Collections.staff).map(StaffMember.fromJson).toList();

  Future<StaffMember> createStaff({
    required String fullName,
    required String roleTitle,
    String? primarySiteId,
    String? profileId,
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
    };
    final saved = await _store.insertRow(Collections.staff, data);
    return StaffMember.fromJson(saved);
  }

  Future<void> setStaffActive(String staffId, bool active) async {
    await _store.updateRow(Collections.staff, staffId, {'is_active': active});
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

  Future<Patient> createPatient({
    required String fullName,
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
  // NOTA: en Supabase, la auditoria de patients/wounds/consultations/
  // measurements/treatment_plans/kura_recommendations/staff/profiles YA se
  // genera automaticamente via triggers AFTER INSERT/UPDATE/DELETE
  // (audit_trigger_fn en 0002_triggers_and_functions.sql). Esta llamada
  // manual queda como registro adicional explicito desde la app (p.ej.
  // para acciones que no tienen trigger, o en modo local donde no hay
  // triggers de Postgres). Ver roadmap paso 4 (auditoria completa) para el
  // trabajo restante de conciliar ambos mecanismos.
  List<Map<String, dynamic>> listAuditLog({int limit = 200}) {
    final list = _store.getAll(Collections.auditLog);
    list.sort((a, b) => (b['occurred_at'] as String).compareTo(a['occurred_at'] as String));
    return list.take(limit).toList();
  }

  Future<void> logAudit({
    required String actorId,
    required String actorRole,
    required String action,
    required String tableName,
    String? recordId,
    Map<String, dynamic>? oldData,
    Map<String, dynamic>? newData,
  }) async {
    await _store.insertRow(Collections.auditLog, {
      'actor_id': actorId.isEmpty ? null : actorId,
      'actor_role': actorRole,
      'action': action,
      'table_name': tableName,
      'record_id': recordId,
      'old_data': oldData,
      'new_data': newData,
      'occurred_at': DateTime.now().toIso8601String(),
    });
  }
}
