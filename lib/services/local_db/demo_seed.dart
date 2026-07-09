import 'package:uuid/uuid.dart';
import 'local_store.dart';

const _uuid = Uuid();

/// Siembra datos de demostracion realistas: sitios, personal, pacientes,
/// heridas, mediciones seriadas y una recomendacion Kura+ de ejemplo.
/// Se ejecuta una sola vez (marca 'seeded' en LocalStore) para permitir
/// una demo navegable inmediata.
class DemoSeed {
  static Future<void> ensureSeeded(LocalStore store) async {
    if (store.getBool('seeded')) return;
    await _seed(store);
    await store.setBool('seeded', true);
  }

  static Future<void> resetAndReseed(LocalStore store) async {
    await store.wipeAll();
    await _seed(store);
    await store.setBool('seeded', true);
  }

  static Future<void> _seed(LocalStore store) async {
    final now = DateTime.now();
    String iso(DateTime d) => d.toIso8601String();
    String isoDate(DateTime d) => d.toIso8601String().substring(0, 10);

    // ---------------- Sitios ----------------
    final siteClinicaCentro = _uuid.v4();
    final siteClinicaNorte = _uuid.v4();
    final siteDomicilio = _uuid.v4();

    await store.saveAll(Collections.sites, [
      {
        'id': siteClinicaCentro,
        'name': 'Kura+ Clinica Centro',
        'kind': 'clinica',
        'address': 'Av. Reforma 123, CDMX',
        'is_active': true,
      },
      {
        'id': siteClinicaNorte,
        'name': 'Kura+ Clinica Norte',
        'kind': 'clinica',
        'address': 'Blvd. Norte 456, Monterrey',
        'is_active': true,
      },
      {
        'id': siteDomicilio,
        'name': 'Atencion a domicilio',
        'kind': 'domicilio',
        'address': null,
        'is_active': true,
      },
    ]);

    // ---------------- Usuarios / Perfiles ----------------
    final adminProfileId = _uuid.v4();
    final clinico1ProfileId = _uuid.v4();
    final clinico2ProfileId = _uuid.v4();

    await store.saveAll(Collections.profiles, [
      {
        'id': adminProfileId,
        'role': 'admin',
        'full_name': 'Administrador Procomsa',
        'email': 'admin@curamas.mx',
        'is_active': true,
        'premium_enabled': true,
      },
      {
        'id': clinico1ProfileId,
        'role': 'clinico',
        'full_name': 'Dra. Ana Martinez',
        'email': 'ana.martinez@curamas.mx',
        'is_active': true,
        'premium_enabled': true,
      },
      {
        'id': clinico2ProfileId,
        'role': 'clinico',
        'full_name': 'Lic. Carlos Ramirez',
        'email': 'carlos.ramirez@curamas.mx',
        'is_active': true,
        'premium_enabled': false,
      },
    ]);

    // ---------------- Personal sanitario ----------------
    final staff1Id = _uuid.v4();
    final staff2Id = _uuid.v4();

    await store.saveAll(Collections.staff, [
      {
        'id': staff1Id,
        'profile_id': clinico1ProfileId,
        'folio': 'K2024-0001',
        'full_name': 'Dra. Ana Martinez',
        'role_title': 'Kuradora / Medico',
        'primary_site_id': siteClinicaCentro,
        'is_active': true,
        'created_at': iso(now.subtract(const Duration(days: 400))),
      },
      {
        'id': staff2Id,
        'profile_id': clinico2ProfileId,
        'folio': 'K2024-0002',
        'full_name': 'Lic. Carlos Ramirez',
        'role_title': 'Kurador',
        'primary_site_id': siteClinicaNorte,
        'is_active': true,
        'created_at': iso(now.subtract(const Duration(days: 250))),
      },
    ]);

    // ---------------- Pacientes ----------------
    final p1Id = _uuid.v4(); // pie diabetico, escenario B probable
    final p2Id = _uuid.v4(); // LPP, escenario dependiente
    final p3Id = _uuid.v4(); // vascular con isquemia critica (caso de seguridad)
    final p4Id = _uuid.v4(); // quirurgica
    final p5Id = _uuid.v4(); // traumatica, cierre rapido

    await store.saveAll(Collections.patients, [
      {
        'id': p1Id,
        'folio': 'EXP2025-0001',
        'full_name': 'Roberto Sanchez Lopez',
        'birth_date': isoDate(DateTime(1958, 3, 12)),
        'sex': 'M',
        'primary_site_id': siteClinicaCentro,
        'mobility': 'ambulatorio',
        'has_identified_caregiver': true,
        'caregiver_name': 'Maria Sanchez (hija)',
        'caregiver_phone': '555-0101',
        'fragile_patient': false,
        'background_notes': 'Diabetes mellitus tipo 2 de 15 anos de evolucion. '
            'Neuropatia periferica. Control glucemico irregular.',
        'ekare_external_id': 'EKARE-PT-88213',
        'is_active': true,
        'created_at': iso(now.subtract(const Duration(days: 120))),
      },
      {
        'id': p2Id,
        'folio': 'EXP2025-0002',
        'full_name': 'Guadalupe Torres Ibarra',
        'birth_date': isoDate(DateTime(1940, 7, 5)),
        'sex': 'F',
        'primary_site_id': siteDomicilio,
        'mobility': 'encamado',
        'has_identified_caregiver': true,
        'caregiver_name': 'Jose Torres (esposo)',
        'caregiver_phone': '555-0202',
        'fragile_patient': true,
        'background_notes': 'Paciente encamada por fractura de cadera. '
            'Movilidad muy reducida, riesgo alto de nuevas LPP.',
        'ekare_external_id': 'EKARE-PT-77410',
        'is_active': true,
        'created_at': iso(now.subtract(const Duration(days: 90))),
      },
      {
        'id': p3Id,
        'folio': 'EXP2025-0003',
        'full_name': 'Fernando Castillo Vega',
        'birth_date': isoDate(DateTime(1952, 11, 20)),
        'sex': 'M',
        'primary_site_id': siteClinicaCentro,
        'mobility': 'ambulatorio',
        'has_identified_caregiver': false,
        'fragile_patient': false,
        'background_notes': 'Enfermedad arterial periferica avanzada, '
            'tabaquismo activo intenso (40 cigarrillos/dia).',
        'ekare_external_id': 'EKARE-PT-65120',
        'is_active': true,
        'created_at': iso(now.subtract(const Duration(days: 60))),
      },
      {
        'id': p4Id,
        'folio': 'EXP2025-0004',
        'full_name': 'Patricia Nunez Reyes',
        'birth_date': isoDate(DateTime(1975, 2, 18)),
        'sex': 'F',
        'primary_site_id': siteClinicaNorte,
        'mobility': 'ambulatorio',
        'has_identified_caregiver': false,
        'fragile_patient': false,
        'background_notes': 'Postquirurgica de colecistectomia abierta, '
            'dehiscencia de herida quirurgica en el 10o dia postoperatorio.',
        'ekare_external_id': 'EKARE-PT-90044',
        'is_active': true,
        'created_at': iso(now.subtract(const Duration(days: 20))),
      },
      {
        'id': p5Id,
        'folio': 'PA2026-0005',
        'full_name': 'Miguel Angel Duran',
        'birth_date': isoDate(DateTime(1990, 9, 30)),
        'sex': 'M',
        'primary_site_id': siteClinicaNorte,
        'mobility': 'ambulatorio',
        'has_identified_caregiver': false,
        'fragile_patient': false,
        'background_notes': 'Herida traumatica por accidente laboral '
            '(objeto punzocortante). Sin comorbilidades relevantes.',
        'ekare_external_id': null,
        'is_active': true,
        'created_at': iso(now.subtract(const Duration(days: 10))),
      },
    ]);

    // ---------------- Asignaciones staff-paciente ----------------
    await store.saveAll(Collections.staffPatientAssignments, [
      {'id': _uuid.v4(), 'staff_id': staff1Id, 'patient_id': p1Id},
      {'id': _uuid.v4(), 'staff_id': staff1Id, 'patient_id': p2Id},
      {'id': _uuid.v4(), 'staff_id': staff1Id, 'patient_id': p3Id},
      {'id': _uuid.v4(), 'staff_id': staff2Id, 'patient_id': p4Id},
      {'id': _uuid.v4(), 'staff_id': staff2Id, 'patient_id': p5Id},
      {'id': _uuid.v4(), 'staff_id': staff1Id, 'patient_id': p4Id}, // ana tambien ve p4
    ]);

    // ---------------- Comorbilidades ----------------
    await store.saveAll(Collections.patientComorbidities, [
      // Paciente 1: pie diabetico
      {'id': _uuid.v4(), 'patient_id': p1Id, 'code': 'diabetes_mellitus', 'status': 'presente'},
      {'id': _uuid.v4(), 'patient_id': p1Id, 'code': 'movilidad_reducida', 'status': 'no_evaluado'},
      {'id': _uuid.v4(), 'patient_id': p1Id, 'code': 'obesidad', 'status': 'negado'},
      // Paciente 2: LPP
      {'id': _uuid.v4(), 'patient_id': p2Id, 'code': 'movilidad_reducida', 'status': 'presente'},
      {'id': _uuid.v4(), 'patient_id': p2Id, 'code': 'malnutricion', 'status': 'presente'},
      // Paciente 3: vascular con isquemia critica
      {'id': _uuid.v4(), 'patient_id': p3Id, 'code': 'enfermedad_arterial_periferica', 'status': 'presente'},
      {'id': _uuid.v4(), 'patient_id': p3Id, 'code': 'tabaquismo_activo', 'status': 'presente'},
      // Paciente 4: quirurgica
      {'id': _uuid.v4(), 'patient_id': p4Id, 'code': 'obesidad', 'status': 'presente'},
      // Paciente 5: traumatica, sin comorbilidades
      {'id': _uuid.v4(), 'patient_id': p5Id, 'code': 'diabetes_mellitus', 'status': 'negado'},
    ]);

    // ---------------- Heridas ----------------
    final w1Id = _uuid.v4(); // pie diabetico
    final w2Id = _uuid.v4(); // LPP sacra
    final w3Id = _uuid.v4(); // vascular, isquemia critica
    final w4Id = _uuid.v4(); // quirurgica
    final w5Id = _uuid.v4(); // traumatica

    await store.saveAll(Collections.wounds, [
      {
        'id': w1Id,
        'patient_id': p1Id,
        'etiology': 'pie_diabetico',
        'subtype': 'Ulcera neuropatica plantar',
        'body_location_primary': 'pie_derecho_planta',
        'body_location_secondary': null,
        'onset_date': isoDate(now.subtract(const Duration(days: 45))),
        'wagner_grade': 'g2',
        'ceap_class': null,
        'wuwhs_grade': null,
        'agente_causal': null,
        'is_active': true,
        'closed_at': null,
        'created_at': iso(now.subtract(const Duration(days: 45))),
      },
      {
        'id': w2Id,
        'patient_id': p2Id,
        'etiology': 'lpp',
        'subtype': 'LPP categoria III',
        'body_location_primary': 'sacro',
        'body_location_secondary': 'trocanter_izquierdo',
        'onset_date': isoDate(now.subtract(const Duration(days: 60))),
        'wagner_grade': null,
        'ceap_class': null,
        'wuwhs_grade': null,
        'agente_causal': null,
        'is_active': true,
        'closed_at': null,
        'created_at': iso(now.subtract(const Duration(days: 60))),
      },
      {
        'id': w3Id,
        'patient_id': p3Id,
        'etiology': 'vascular',
        'subtype': 'Ulcera isquemica',
        'body_location_primary': 'pierna_izquierda_maleolo',
        'body_location_secondary': null,
        'onset_date': isoDate(now.subtract(const Duration(days: 30))),
        'wagner_grade': null,
        'ceap_class': 'c5',
        'wuwhs_grade': null,
        'agente_causal': null,
        'is_active': true,
        'closed_at': null,
        'created_at': iso(now.subtract(const Duration(days: 30))),
      },
      {
        'id': w4Id,
        'patient_id': p4Id,
        'etiology': 'quirurgica',
        'subtype': 'Dehiscencia de herida quirurgica',
        'body_location_primary': 'abdomen_superior',
        'body_location_secondary': null,
        'onset_date': isoDate(now.subtract(const Duration(days: 12))),
        'wagner_grade': null,
        'ceap_class': null,
        'wuwhs_grade': 'g2',
        'agente_causal': null,
        'is_active': true,
        'closed_at': null,
        'created_at': iso(now.subtract(const Duration(days: 12))),
      },
      {
        'id': w5Id,
        'patient_id': p5Id,
        'etiology': 'traumatica',
        'subtype': 'Herida punzocortante',
        'body_location_primary': 'antebrazo_izquierdo',
        'body_location_secondary': null,
        'onset_date': isoDate(now.subtract(const Duration(days: 8))),
        'wagner_grade': null,
        'ceap_class': null,
        'wuwhs_grade': null,
        'agente_causal': 'punzocortante',
        'is_active': true,
        'closed_at': null,
        'created_at': iso(now.subtract(const Duration(days: 8))),
      },
    ]);

    // ---------------- Consultas (encabezados) ----------------
    final c1Id = _uuid.v4();
    final c2Id = _uuid.v4();
    final c3Id = _uuid.v4();
    final c4Id = _uuid.v4();
    final c5Id = _uuid.v4();
    // Consultas de seguimiento adicionales para p1 (para graficas de tendencia)
    final c1bId = _uuid.v4();
    final c1cId = _uuid.v4();

    await store.saveAll(Collections.consultations, [
      {
        'id': c1Id,
        'patient_id': p1Id,
        'staff_id': staff1Id,
        'site_id': siteClinicaCentro,
        'visit_type': 'valoracion',
        'visit_date': isoDate(now.subtract(const Duration(days: 45))),
        'vital_signs': {'ta': '130/85', 'fc': 76, 'temp': 36.6},
        'is_draft': false,
        'created_at': iso(now.subtract(const Duration(days: 45))),
      },
      {
        'id': c1bId,
        'patient_id': p1Id,
        'staff_id': staff1Id,
        'site_id': siteClinicaCentro,
        'visit_type': 'seguimiento',
        'visit_date': isoDate(now.subtract(const Duration(days: 31))),
        'vital_signs': {'ta': '128/82', 'fc': 74, 'temp': 36.5},
        'is_draft': false,
        'created_at': iso(now.subtract(const Duration(days: 31))),
      },
      {
        'id': c1cId,
        'patient_id': p1Id,
        'staff_id': staff1Id,
        'site_id': siteClinicaCentro,
        'visit_type': 'seguimiento',
        'visit_date': isoDate(now.subtract(const Duration(days: 17))),
        'vital_signs': {'ta': '125/80', 'fc': 72, 'temp': 36.4},
        'is_draft': false,
        'created_at': iso(now.subtract(const Duration(days: 17))),
      },
      {
        'id': c2Id,
        'patient_id': p2Id,
        'staff_id': staff1Id,
        'site_id': siteDomicilio,
        'visit_type': 'valoracion',
        'visit_date': isoDate(now.subtract(const Duration(days: 60))),
        'vital_signs': {'ta': '110/70', 'fc': 82, 'temp': 36.8},
        'is_draft': false,
        'created_at': iso(now.subtract(const Duration(days: 60))),
      },
      {
        'id': c3Id,
        'patient_id': p3Id,
        'staff_id': staff1Id,
        'site_id': siteClinicaCentro,
        'visit_type': 'valoracion',
        'visit_date': isoDate(now.subtract(const Duration(days: 30))),
        'vital_signs': {'ta': '145/90', 'fc': 88, 'temp': 36.7},
        'is_draft': false,
        'created_at': iso(now.subtract(const Duration(days: 30))),
      },
      {
        'id': c4Id,
        'patient_id': p4Id,
        'staff_id': staff2Id,
        'site_id': siteClinicaNorte,
        'visit_type': 'valoracion',
        'visit_date': isoDate(now.subtract(const Duration(days: 12))),
        'vital_signs': {'ta': '118/76', 'fc': 80, 'temp': 37.1},
        'is_draft': false,
        'created_at': iso(now.subtract(const Duration(days: 12))),
      },
      {
        'id': c5Id,
        'patient_id': p5Id,
        'staff_id': staff2Id,
        'site_id': siteClinicaNorte,
        'visit_type': 'valoracion',
        'visit_date': isoDate(now.subtract(const Duration(days: 8))),
        'vital_signs': {'ta': '120/78', 'fc': 70, 'temp': 36.5},
        'is_draft': false,
        'created_at': iso(now.subtract(const Duration(days: 8))),
      },
    ]);

    // ---------------- Evaluaciones clinicas ----------------
    await store.saveAll(Collections.woundAssessments, [
      {
        'id': _uuid.v4(),
        'consultation_id': c1Id,
        'wound_id': w1Id,
        'glucose_mg_dl': 180,
        'first_assessment_date': isoDate(now.subtract(const Duration(days: 45))),
        'edema': 'leve',
        'pain': true,
        'pain_type': 'neuropatico',
        'pain_duration': 'cronico',
        'pain_vas': 4,
        'exudate_amount': 'moderado',
        'infection_criteria': <String>[],
        'odor': 'leve',
        'wound_edge': 'irregular',
        'perilesional_skin': ['hiperqueratosica', 'callosidad'],
      },
      {
        'id': _uuid.v4(),
        'consultation_id': c2Id,
        'wound_id': w2Id,
        'glucose_mg_dl': null,
        'first_assessment_date': isoDate(now.subtract(const Duration(days: 60))),
        'edema': 'ninguno',
        'pain': true,
        'pain_type': 'nociceptivo',
        'pain_duration': 'cronico',
        'pain_vas': 6,
        'exudate_amount': 'abundante',
        'infection_criteria': ['olorAumentado', 'exudadoAumentado'],
        'odor': 'moderado',
        'wound_edge': 'definido',
        'perilesional_skin': ['macerada', 'fragil'],
      },
      {
        'id': _uuid.v4(),
        'consultation_id': c3Id,
        'wound_id': w3Id,
        'glucose_mg_dl': 95,
        'first_assessment_date': isoDate(now.subtract(const Duration(days: 30))),
        'edema': 'ninguno',
        'pain': true,
        'pain_type': 'isquemico',
        'pain_duration': 'agudo',
        'pain_vas': 8,
        'exudate_amount': 'escaso',
        'infection_criteria': <String>[],
        'odor': 'ninguno',
        'wound_edge': 'definido',
        'perilesional_skin': ['seca'],
      },
      {
        'id': _uuid.v4(),
        'consultation_id': c4Id,
        'wound_id': w4Id,
        'glucose_mg_dl': 110,
        'first_assessment_date': isoDate(now.subtract(const Duration(days: 12))),
        'edema': 'moderado',
        'pain': true,
        'pain_type': 'nociceptivo',
        'pain_duration': 'agudo',
        'pain_vas': 5,
        'exudate_amount': 'moderado',
        'infection_criteria': ['eritemaPerilesional', 'calorLocal'],
        'odor': 'ninguno',
        'wound_edge': 'dehiscente',
        'perilesional_skin': ['eritematosa'],
      },
      {
        'id': _uuid.v4(),
        'consultation_id': c5Id,
        'wound_id': w5Id,
        'glucose_mg_dl': 92,
        'first_assessment_date': isoDate(now.subtract(const Duration(days: 8))),
        'edema': 'ninguno',
        'pain': true,
        'pain_type': 'nociceptivo',
        'pain_duration': 'agudo',
        'pain_vas': 3,
        'exudate_amount': 'escaso',
        'infection_criteria': <String>[],
        'odor': 'ninguno',
        'wound_edge': 'definido',
        'perilesional_skin': ['normal'],
      },
    ]);

    // ---------------- Mediciones seriadas ----------------
    await store.saveAll(Collections.woundMeasurements, [
      // Paciente 1 (pie diabetico) - 3 mediciones mostrando evolucion
      {
        'id': _uuid.v4(),
        'wound_id': w1Id,
        'consultation_id': c1Id,
        'measured_at': isoDate(now.subtract(const Duration(days: 45))),
        'length_cm': 3.2,
        'width_cm': 2.5,
        'area_cm2': 8.0,
        'depth_cm': 0.6,
        'tunneling': false,
        'undermining': false,
        'granulation_pct': 40,
        'slough_pct': 35,
        'necrosis_pct': 10,
        'epithelialization_pct': 15,
        'captured_before_debridement': true,
      },
      {
        'id': _uuid.v4(),
        'wound_id': w1Id,
        'consultation_id': c1bId,
        'measured_at': isoDate(now.subtract(const Duration(days: 31))),
        'length_cm': 2.8,
        'width_cm': 2.1,
        'area_cm2': 5.88,
        'depth_cm': 0.4,
        'tunneling': false,
        'undermining': false,
        'granulation_pct': 55,
        'slough_pct': 20,
        'necrosis_pct': 5,
        'epithelialization_pct': 20,
        'captured_before_debridement': true,
      },
      {
        'id': _uuid.v4(),
        'wound_id': w1Id,
        'consultation_id': c1cId,
        'measured_at': isoDate(now.subtract(const Duration(days: 17))),
        'length_cm': 2.1,
        'width_cm': 1.6,
        'area_cm2': 3.36,
        'depth_cm': 0.3,
        'tunneling': false,
        'undermining': false,
        'granulation_pct': 65,
        'slough_pct': 10,
        'necrosis_pct': 0,
        'epithelialization_pct': 25,
        'captured_before_debridement': true,
      },
      // Paciente 2 (LPP)
      {
        'id': _uuid.v4(),
        'wound_id': w2Id,
        'consultation_id': c2Id,
        'measured_at': isoDate(now.subtract(const Duration(days: 60))),
        'length_cm': 5.5,
        'width_cm': 4.0,
        'area_cm2': 22.0,
        'depth_cm': 1.8,
        'tunneling': true,
        'undermining': true,
        'granulation_pct': 25,
        'slough_pct': 40,
        'necrosis_pct': 25,
        'epithelialization_pct': 10,
        'captured_before_debridement': true,
      },
      // Paciente 3 (vascular, isquemia critica)
      {
        'id': _uuid.v4(),
        'wound_id': w3Id,
        'consultation_id': c3Id,
        'measured_at': isoDate(now.subtract(const Duration(days: 30))),
        'length_cm': 2.0,
        'width_cm': 1.5,
        'area_cm2': 3.0,
        'depth_cm': 0.5,
        'tunneling': false,
        'undermining': false,
        'granulation_pct': 10,
        'slough_pct': 30,
        'necrosis_pct': 45,
        'epithelialization_pct': 15,
        'captured_before_debridement': true,
      },
      // Paciente 4 (quirurgica)
      {
        'id': _uuid.v4(),
        'wound_id': w4Id,
        'consultation_id': c4Id,
        'measured_at': isoDate(now.subtract(const Duration(days: 12))),
        'length_cm': 6.0,
        'width_cm': 2.0,
        'area_cm2': 12.0,
        'depth_cm': 1.2,
        'tunneling': false,
        'undermining': false,
        'granulation_pct': 30,
        'slough_pct': 30,
        'necrosis_pct': 10,
        'epithelialization_pct': 30,
        'captured_before_debridement': true,
      },
      // Paciente 5 (traumatica) — herida pequena, cierre rapido esperado
      {
        'id': _uuid.v4(),
        'wound_id': w5Id,
        'consultation_id': c5Id,
        'measured_at': isoDate(now.subtract(const Duration(days: 8))),
        'length_cm': 1.5,
        'width_cm': 0.8,
        'area_cm2': 1.2,
        'depth_cm': 0.2,
        'tunneling': false,
        'undermining': false,
        'granulation_pct': 70,
        'slough_pct': 10,
        'necrosis_pct': 0,
        'epithelialization_pct': 20,
        'captured_before_debridement': true,
      },
    ]);

    // ---------------- Perfusion / nutricion ----------------
    await store.saveAll(Collections.perfusionNutrition, [
      {
        'id': _uuid.v4(),
        'consultation_id': c1Id,
        'wound_id': w1Id,
        'abi_right': 0.95,
        'abi_left': 0.92,
        'is_lower_extremity': true,
        'albumin_g_dl': 3.6,
      },
      {
        'id': _uuid.v4(),
        'consultation_id': c2Id,
        'wound_id': w2Id,
        'abi_right': null,
        'abi_left': null,
        'is_lower_extremity': false,
        'albumin_g_dl': 2.8,
      },
      {
        'id': _uuid.v4(),
        'consultation_id': c3Id,
        'wound_id': w3Id,
        'abi_right': 0.55,
        'abi_left': 0.38, // isquemia critica en pierna izquierda (herida)
        'is_lower_extremity': true,
        'albumin_g_dl': 3.1,
      },
      {
        'id': _uuid.v4(),
        'consultation_id': c4Id,
        'wound_id': w4Id,
        'abi_right': null,
        'abi_left': null,
        'is_lower_extremity': false,
        'albumin_g_dl': 3.9,
      },
      {
        'id': _uuid.v4(),
        'consultation_id': c5Id,
        'wound_id': w5Id,
        'abi_right': null,
        'abi_left': null,
        'is_lower_extremity': false,
        'albumin_g_dl': null,
      },
    ]);

    // Planes de tratamiento y componentes de ejemplo (manuales, no premium)
    final tp5Id = _uuid.v4();
    await store.saveAll(Collections.treatmentPlans, [
      {
        'id': tp5Id,
        'consultation_id': c5Id,
        'wound_id': w5Id,
        'used_kura_protocol': false,
        'final_description':
            'Limpieza con solucion salina, cierre por segunda intencion, '
            'aposito de espuma. Revision en 7 dias.',
      },
    ]);
    await store.saveAll(Collections.treatmentComponents, [
      {
        'id': _uuid.v4(),
        'treatment_plan_id': tp5Id,
        'method': 'Limpieza de la herida',
        'product': 'Solucion salina',
        'origin': 'manual',
        'sort_order': 0,
      },
      {
        'id': _uuid.v4(),
        'treatment_plan_id': tp5Id,
        'method': 'Aposito',
        'product': 'Espuma con borde adhesivo',
        'origin': 'manual',
        'sort_order': 1,
      },
    ]);
  }
}
