import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

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

/// Nombres de colecciones (equivalentes a las tablas SQL de Supabase).
class Collections {
  static const profiles = 'profiles';
  static const sites = 'sites';
  static const staff = 'staff';
  static const staffPatientAssignments = 'staff_patient_assignments';
  static const patients = 'patients';
  static const patientComorbidities = 'patient_comorbidities';
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
  static const importBatches = 'import_batches';
}
