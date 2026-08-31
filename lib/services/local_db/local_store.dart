import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../remote/data_store.dart';

const _uuid = Uuid();

/// Almacen local generico basado en SharedPreferences (JSON por coleccion).
///
/// DECISION DE ARQUITECTURA: para la demo offline-first multiplataforma
/// (Web + iOS + Android) sin depender de bindings nativos de SQLite en
/// Flutter Web (que requieren configuracion adicional de sqlite3.wasm),
/// se usa un almacen de documentos JSON respaldado por SharedPreferences.
/// Cada "tabla" es una lista de mapas serializados como JSON bajo una
/// clave unica. Esto reproduce fielmente el modelo relacional (las
/// relaciones se resuelven por id en la capa de repositorio) y es
/// suficiente para una demo funcional; en produccion, sustituir por
/// Supabase (ver lib/services/supabase) que es la fuente autoritativa.
class LocalStore {
  static const String _keyPrefix = 'kuratracker_';
  static LocalStore? _instance;
  late SharedPreferences _prefs;
  bool _ready = false;

  LocalStore._();

  static Future<LocalStore> instance() async {
    if (_instance != null && _instance!._ready) return _instance!;
    final store = LocalStore._();
    store._prefs = await SharedPreferences.getInstance();
    store._ready = true;
    _instance = store;
    return store;
  }

  String _k(String collection) => '$_keyPrefix$collection';

  List<Map<String, dynamic>> getAll(String collection) {
    final raw = _prefs.getString(_k(collection));
    if (raw == null) return [];
    final decoded = jsonDecode(raw) as List;
    return decoded.cast<Map<String, dynamic>>();
  }

  Future<void> saveAll(String collection, List<Map<String, dynamic>> items) async {
    await _prefs.setString(_k(collection), jsonEncode(items));
  }

  Future<void> upsert(String collection, Map<String, dynamic> item) async {
    final items = getAll(collection);
    final idx = items.indexWhere((e) => e['id'] == item['id']);
    if (idx >= 0) {
      items[idx] = item;
    } else {
      items.add(item);
    }
    await saveAll(collection, items);
  }

  Future<void> delete(String collection, String id) async {
    final items = getAll(collection);
    items.removeWhere((e) => e['id'] == id);
    await saveAll(collection, items);
  }

  Future<void> clearCollection(String collection) async {
    await _prefs.remove(_k(collection));
  }

  bool getBool(String key, {bool defaultValue = false}) =>
      _prefs.getBool('$_keyPrefix$key') ?? defaultValue;

  Future<void> setBool(String key, bool value) async {
    await _prefs.setBool('$_keyPrefix$key', value);
  }

  String? getString(String key) => _prefs.getString('$_keyPrefix$key');

  Future<void> setString(String key, String value) async {
    await _prefs.setString('$_keyPrefix$key', value);
  }

  Future<void> wipeAll() async {
    final keys = _prefs.getKeys().where((k) => k.startsWith(_keyPrefix));
    for (final k in keys) {
      await _prefs.remove(k);
    }
  }
}

/// Adaptador que expone [LocalStore] a traves de la interfaz [DataStore],
/// para que [DataRepository] pueda depender uniformemente de [DataStore]
/// sin importar si el backend es local (demo) o Supabase (produccion).
///
/// Como SharedPreferences ya es sincrono en lectura (una vez cargado en
/// memoria por el plugin), `getAll` delega directamente sin cache adicional;
/// las escrituras generan id (uuid v4) si no viene incluido, igual que hacia
/// antes `DataRepository` manualmente en cada metodo `createX`.
class LocalStoreDataStore implements DataStore {
  final LocalStore _store;
  LocalStoreDataStore(this._store);

  @override
  List<Map<String, dynamic>> getAll(String collection) => _store.getAll(collection);

  @override
  Future<Map<String, dynamic>> insertRow(
      String collection, Map<String, dynamic> data) async {
    final row = Map<String, dynamic>.from(data);
    row['id'] ??= _uuid.v4();
    await _store.upsert(collection, row);
    return row;
  }

  @override
  Future<Map<String, dynamic>> updateRow(
      String collection, String id, Map<String, dynamic> patch) async {
    final items = _store.getAll(collection);
    final idx = items.indexWhere((e) => e['id'] == id);
    if (idx < 0) {
      throw StateError('No existe fila id=$id en "$collection" (update).');
    }
    final merged = {...items[idx], ...patch};
    await _store.upsert(collection, merged);
    return merged;
  }

  @override
  Future<void> deleteRow(String collection, String id) async {
    await _store.delete(collection, id);
  }

  @override
  Future<Map<String, dynamic>> upsertRow(
      String collection, Map<String, dynamic> data) async {
    final row = Map<String, dynamic>.from(data);
    row['id'] ??= _uuid.v4();
    await _store.upsert(collection, row);
    return row;
  }

  @override
  Future<void> refreshCollection(String collection) async {
    // No-op: SharedPreferences no tiene "servidor" que consultar; getAll()
    // ya lee el estado mas reciente en cada llamada.
  }

  @override
  Future<void> hydrate() async {
    // No-op: no hay cache separada que poblar en el caso local.
  }
}

/// Nombres de colecciones (equivalentes a las tablas SQL de Supabase).
class Collections {
  static const organizations = 'organizations';
  static const profiles = 'profiles';
  static const sites = 'sites';
  static const staff = 'staff';
  static const staffPatientAssignments = 'staff_patient_assignments';
  static const patients = 'patients';
  static const patientComorbidities = 'patient_comorbidities';
  static const patientDiagnoses = 'patient_diagnoses';
  static const patientLabs = 'patient_labs';
  static const patientAdmissions = 'patient_admissions';
  static const riskAssessments = 'risk_assessments';
  static const scaleAssessments = 'scale_assessments';
  static const preventiveActionLog = 'preventive_action_log';
  static const consultations = 'consultations';
  static const wounds = 'wounds';
  static const woundAssessments = 'wound_assessments';
  static const woundMeasurements = 'wound_measurements';
  static const perfusionNutrition = 'perfusion_nutrition_data';
  static const woundPhotos = 'wound_photos';
  static const treatmentPlans = 'treatment_plans';
  static const treatmentComponents = 'treatment_components';
  static const kuraRecommendations = 'kura_recommendations';
  static const sheehanCheckpoints = 'sheehan_checkpoints';
  static const auditLog = 'audit_log';
  static const dataDisclosures = 'data_disclosures';
  static const importBatches = 'import_batches';
  static const noteOptionCatalog = 'note_option_catalog';
  static const manualAppointments = 'manual_appointments';
  static const adverseEvents = 'adverse_events';
  static const consents = 'consents';
  static const referrals = 'referrals';
  static const clinicalAmendments = 'clinical_amendments';
  static const userCenterMemberships = 'user_center_memberships';
  static const moduleSettings = 'module_settings';
  static const preventiveTasks = 'preventive_tasks';
  static const caregiverPatientAssignments = 'caregiver_patient_assignments';
  static const caregiverInstructions = 'caregiver_instructions';
  static const supplyProductMappings = 'supply_product_mappings';
  static const inventoryItems = 'inventory_items';
  static const inventoryMovements = 'inventory_movements';
  static const supplyOrders = 'supply_orders';
  static const supplyOrderItems = 'supply_order_items';
  static const consultationSupplyUsage = 'consultation_supply_usage';
  static const serviceCatalog = 'service_catalog';
  static const charges = 'charges';
  static const chargeItems = 'charge_items';
  static const pointPayments = 'point_payments';
  static const vacTherapies = 'vac_therapies';
  static const vacEvents = 'vac_events';
  static const vacSettings = 'vac_settings';
  static const productCatalog = 'product_catalog';
  static const clinicalParams = 'clinical_params';
  static const treatmentPrograms = 'treatment_programs';
  static const treatmentProgramSupplies = 'treatment_program_supplies';
  static const treatmentProgramSessions = 'treatment_program_sessions';
  static const protocolProductRules = 'protocol_product_rules';

  /// Todas las colecciones/tablas, en un orden razonable para hidratar la
  /// cache de [SupabaseDataStore] tras el login (catalogos primero, luego
  /// datos clinicos). El orden no importa para SELECT (a diferencia de las
  /// migraciones SQL, que si tienen dependencias de FK en INSERT/CREATE).
  static const List<String> all = [
    organizations,
    profiles,
    sites,
    staff,
    staffPatientAssignments,
    patients,
    patientComorbidities,
    patientDiagnoses,
    patientLabs,
    patientAdmissions,
    riskAssessments,
    scaleAssessments,
    preventiveActionLog,
    consultations,
    wounds,
    woundAssessments,
    woundMeasurements,
    perfusionNutrition,
    woundPhotos,
    treatmentPlans,
    treatmentComponents,
    kuraRecommendations,
    sheehanCheckpoints,
    auditLog,
    importBatches,
    noteOptionCatalog,
    manualAppointments,
    adverseEvents,
    consents,
    referrals,
    clinicalAmendments,
    userCenterMemberships,
    moduleSettings,
    preventiveTasks,
    caregiverPatientAssignments,
    caregiverInstructions,
    supplyProductMappings,
    inventoryItems,
    inventoryMovements,
    supplyOrders,
    supplyOrderItems,
    consultationSupplyUsage,
    serviceCatalog,
    charges,
    chargeItems,
    pointPayments,
    vacTherapies,
    vacEvents,
    vacSettings,
    productCatalog,
    clinicalParams,
    treatmentPrograms,
    treatmentProgramSupplies,
    treatmentProgramSessions,
    protocolProductRules,
  ];
}
