import 'package:uuid/uuid.dart';

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

const _uuid = Uuid();

/// Repositorio unico de datos para toda la app.
///
/// Encapsula el almacen local (fuente de datos operativa en esta demo,
/// diseñado para funcionar 100% offline) exponiendo una API tipada por
/// entidad. La estructura de esta clase refleja 1:1 el esquema SQL de
/// Supabase (supabase/migrations), de forma que sustituir la
/// implementacion interna por llamadas reales a Supabase (postgrest) es
/// un cambio localizado y no afecta a la capa de UI.
class DataRepository {
  final LocalStore _store;

  DataRepository._(this._store);

  static DataRepository? _instance;

  static Future<DataRepository> instance() async {
    if (_instance != null) return _instance!;
    final store = await LocalStore.instance();
    await DemoSeed.ensureSeeded(store);
    _instance = DataRepository._(store);
    return _instance!;
  }

  Future<void> resetDemoData() async {
    await DemoSeed.resetAndReseed(_store);
  }

  // ---------------- Auth / usuarios (simplificado para demo local) ----------------

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
    final profiles = _store.getAll(Collections.profiles);
    final idx = profiles.indexWhere((p) => p['id'] == userId);
    if (idx >= 0) {
      profiles[idx]['is_active'] = active;
      await _store.saveAll(Collections.profiles, profiles);
    }
  }

  Future<void> setUserPremium(String userId, bool premium) async {
    final profiles = _store.getAll(Collections.profiles);
    final idx = profiles.indexWhere((p) => p['id'] == userId);
    if (idx >= 0) {
      profiles[idx]['premium_enabled'] = premium;
      await _store.saveAll(Collections.profiles, profiles);
    }
  }

  // ---------------- Sitios ----------------

  List<Site> listSites() =>
      _store.getAll(Collections.sites).map(Site.fromJson).toList();

  Future<Site> createSite(Site site) async {
    final data = site.toJson();
    data['id'] = data['id'].toString().isEmpty ? _uuid.v4() : data['id'];
    await _store.upsert(Collections.sites, data);
    return Site.fromJson(data);
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
    await _store.upsert(Collections.staff, data);
    return StaffMember.fromJson(data);
  }

  Future<void> setStaffActive(String staffId, bool active) async {
    final all = _store.getAll(Collections.staff);
    final idx = all.indexWhere((s) => s['id'] == staffId);
    if (idx >= 0) {
      all[idx]['is_active'] = active;
      await _store.saveAll(Collections.staff, all);
    }
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
    await _store.upsert(Collections.patients, data);
    return Patient.fromJson(data);
  }

  Future<void> assignPatientToStaff(String patientId, String staffId) async {
    final all = _store.getAll(Collections.staffPatientAssignments);
    final exists = all.any((a) => a['patient_id'] == patientId && a['staff_id'] == staffId);
    if (!exists) {
      all.add({'id': _uuid.v4(), 'staff_id': staffId, 'patient_id': patientId});
      await _store.saveAll(Collections.staffPatientAssignments, all);
    }
  }

  List<PatientComorbidity> listComorbidities(String patientId) => _store
      .getAll(Collections.patientComorbidities)
      .where((c) => c['patient_id'] == patientId)
      .map(PatientComorbidity.fromJson)
      .toList();

  Future<void> upsertComorbidity(PatientComorbidity comorbidity) async {
    await _store.upsert(Collections.patientComorbidities, comorbidity.toJson());
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
    await _store.upsert(Collections.consultations, data);
    return Consultation.fromJson(data);
  }

  Future<void> updateConsultationDraftStatus(String id, bool isDraft) async {
    final all = _store.getAll(Collections.consultations);
    final idx = all.indexWhere((c) => c['id'] == id);
    if (idx >= 0) {
      all[idx]['is_draft'] = isDraft;
      await _store.saveAll(Collections.consultations, all);
    }
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
    data['id'] = data['id'] ?? _uuid.v4();
    data['created_at'] = data['created_at'] ?? DateTime.now().toIso8601String();
    data['is_active'] = data['is_active'] ?? true;
    await _store.upsert(Collections.wounds, data);
    return Wound.fromJson(data);
  }

  // ---------------- Evaluaciones ----------------

  List<WoundAssessment> listAssessmentsForWound(String woundId) => _store
      .getAll(Collections.woundAssessments)
      .where((a) => a['wound_id'] == woundId)
      .map(WoundAssessment.fromJson)
      .toList();

  Future<WoundAssessment> createAssessment(Map<String, dynamic> data) async {
    data['id'] = data['id'] ?? _uuid.v4();
    await _store.upsert(Collections.woundAssessments, data);
    return WoundAssessment.fromJson(data);
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
    data['id'] = data['id'] ?? _uuid.v4();
    await _store.upsert(Collections.woundMeasurements, data);
    return WoundMeasurement.fromJson(data);
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
    data['id'] = data['id'] ?? _uuid.v4();
    await _store.upsert(Collections.perfusionNutrition, data);
    return PerfusionNutritionData.fromJson(data);
  }

  // ---------------- Fotos ----------------

  List<WoundPhoto> listPhotosForWound(String woundId) => _store
      .getAll(Collections.woundPhotos)
      .where((p) => p['wound_id'] == woundId)
      .map(WoundPhoto.fromJson)
      .toList();

  Future<WoundPhoto> createPhoto(Map<String, dynamic> data) async {
    data['id'] = data['id'] ?? _uuid.v4();
    data['taken_at'] = data['taken_at'] ?? DateTime.now().toIso8601String();
    await _store.upsert(Collections.woundPhotos, data);
    return WoundPhoto.fromJson(data);
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
    await _store.upsert(Collections.treatmentPlans, planData);

    // reemplaza componentes
    final allComponents = _store.getAll(Collections.treatmentComponents);
    allComponents.removeWhere((c) => c['treatment_plan_id'] == planId);
    for (var i = 0; i < components.length; i++) {
      final c = components[i];
      allComponents.add({
        'id': c.id.isEmpty ? _uuid.v4() : c.id,
        'treatment_plan_id': planId,
        'method': c.method,
        'product': c.product,
        'origin': c.origin.dbValue,
        'sort_order': i,
      });
    }
    await _store.saveAll(Collections.treatmentComponents, allComponents);

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
    await _store.upsert(Collections.kuraRecommendations, data);
  }

  List<Map<String, dynamic>> listRecommendationsForWound(String woundId) => _store
      .getAll(Collections.kuraRecommendations)
      .where((r) => r['wound_id'] == woundId)
      .toList();

  // ---------------- Checkpoints Sheehan ----------------

  Future<void> saveSheehanCheckpoint(Map<String, dynamic> data) async {
    data['id'] = data['id'] ?? _uuid.v4();
    data['created_at'] = data['created_at'] ?? DateTime.now().toIso8601String();
    await _store.upsert(Collections.sheehanCheckpoints, data);
  }

  List<Map<String, dynamic>> listSheehanCheckpointsForWound(String woundId) => _store
      .getAll(Collections.sheehanCheckpoints)
      .where((c) => c['wound_id'] == woundId)
      .toList();

  // ---------------- Auditoria ----------------

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
    final list = _store.getAll(Collections.auditLog);
    list.add({
      'id': _uuid.v4(),
      'actor_id': actorId,
      'actor_role': actorRole,
      'action': action,
      'table_name': tableName,
      'record_id': recordId,
      'old_data': oldData,
      'new_data': newData,
      'occurred_at': DateTime.now().toIso8601String(),
    });
    await _store.saveAll(Collections.auditLog, list);
  }
}
