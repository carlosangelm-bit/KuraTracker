import 'package:uuid/uuid.dart';
import 'demo_wound_photos.dart';
import 'local_store.dart';

const _uuid = Uuid();

/// Siembra datos de demostracion realistas: sitios, personal, pacientes,
/// heridas, mediciones seriadas y una recomendacion Kura+ de ejemplo.
/// Se ejecuta una sola vez (marca 'seeded' en LocalStore) para permitir
/// una demo navegable inmediata.
class DemoSeed {
  // Flag VERSIONADO: al enriquecer el set de demo, se re-siembra limpio una
  // sola vez en instalaciones demo previas (que tenían 'seeded' v1), evitando
  // duplicados y datos viejos. Solo aplica al modo demo local (SharedPreferences);
  // producción usa Supabase y nunca llama a este seed.
  static const String _seedFlag = 'seeded_v3';

  static Future<void> ensureSeeded(LocalStore store) async {
    if (store.getBool(_seedFlag)) return;
    // Limpia una posible siembra anterior (v1) para no duplicar filas.
    await store.wipeAll();
    await _seed(store);
    await store.setBool(_seedFlag, true);
  }

  static Future<void> resetAndReseed(LocalStore store) async {
    await store.wipeAll();
    await _seed(store);
    await store.setBool(_seedFlag, true);
  }

  static Future<void> _seed(LocalStore store) async {
    final now = DateTime.now();
    String iso(DateTime d) => d.toIso8601String();
    String isoDate(DateTime d) => d.toIso8601String().substring(0, 10);

    // ---------------- Organizacion (centro) ----------------
    // 0011_organizations.sql: el centro es el tenant raiz; sitios, personal,
    // pacientes y catalogo de notas quedan aislados por organizationId.
    final organizationId = _uuid.v4();
    // Segundo centro (0012_master_role.sql): existe UNICAMENTE para poder
    // demostrar/probar en el modo demo local que el rol master ve y
    // administra estructura de TODOS los centros, no solo de Kura+. No
    // tiene pacientes propios (fuera del alcance de master, ver regla de
    // oro), solo un sitio y un miembro de personal minimos para que el
    // selector de centro en PlatformHomeScreen tenga algo real que
    // mostrar al cambiar de organizacion.
    final organizationId2 = _uuid.v4();

    await store.saveAll(Collections.organizations, [
      {
        'id': organizationId,
        'name': 'Kura+',
        'is_active': true,
        'created_at': iso(now.subtract(const Duration(days: 400))),
      },
      {
        'id': organizationId2,
        'name': 'Clínica Vitalis',
        'is_active': true,
        'created_at': iso(now.subtract(const Duration(days: 30))),
      },
    ]);

    // ---------------- Sitios ----------------
    // El centro Kura+ tiene 1->N sitios; el personal puede operar en TODOS
    // los sitios de su organizacion (no se restringe por primary_site_id,
    // ver Part A del modelo Centro -> Sitios -> Personal).
    final siteClinicaCdmx = _uuid.v4();
    final siteClinicaGdl = _uuid.v4();
    final siteDomicilioCdmx = _uuid.v4();
    final siteDomicilioGdl = _uuid.v4();
    final siteVitalisMty = _uuid.v4();

    await store.saveAll(Collections.sites, [
      {
        'id': siteClinicaCdmx,
        'organization_id': organizationId,
        'name': 'Kura+ Clinica CDMX',
        'kind': 'clinica',
        'address': 'Av. Reforma 123, CDMX',
        'is_active': true,
      },
      {
        'id': siteClinicaGdl,
        'organization_id': organizationId,
        'name': 'Kura+ Clinica GDL',
        'kind': 'clinica',
        'address': 'Av. Vallarta 456, Guadalajara',
        'is_active': true,
      },
      {
        'id': siteDomicilioCdmx,
        'organization_id': organizationId,
        'name': 'Atencion a domicilio CDMX',
        'kind': 'domicilio',
        'address': null,
        'is_active': true,
      },
      {
        'id': siteDomicilioGdl,
        'organization_id': organizationId,
        'name': 'Atencion a domicilio GDL',
        'kind': 'domicilio',
        'address': null,
        'is_active': true,
      },
      // Sitio del segundo centro (Clinica Vitalis), ver comentario en
      // organizationId2 mas arriba.
      {
        'id': siteVitalisMty,
        'organization_id': organizationId2,
        'name': 'Vitalis Clinica Monterrey',
        'kind': 'clinica',
        'address': 'Av. Constitucion 789, Monterrey',
        'is_active': true,
      },
    ]);

    // ---------------- Usuarios / Perfiles ----------------
    final adminProfileId = _uuid.v4();
    final clinico1ProfileId = _uuid.v4();
    final clinico2ProfileId = _uuid.v4();
    // Usuario master (administrador de plataforma, ver
    // 0012_master_role.sql): NO pertenece a ninguna organizacion en
    // particular (organization_id null) -- administra estructura de
    // TODOS los centros via el area "Plataforma", nunca a traves del
    // panel de Administracion (que sigue acotado por organizacion para
    // el rol admin normal).
    final masterProfileId = _uuid.v4();
    // Admin propio del segundo centro (Clinica Vitalis), para poder
    // verificar en la demo que un admin normal de OTRO centro sigue sin
    // ver nada de Kura+ (y viceversa), mientras que el master ve ambos.
    final adminVitalisProfileId = _uuid.v4();

    await store.saveAll(Collections.profiles, [
      {
        'id': adminProfileId,
        'organization_id': organizationId,
        'role': 'admin',
        'full_name': 'Administrador Procomsa',
        'email': 'admin@curamas.mx',
        'is_active': true,
        'premium_enabled': true,
      },
      {
        'id': clinico1ProfileId,
        'organization_id': organizationId,
        'role': 'clinico',
        'full_name': 'Dra. Ana Martinez',
        'email': 'ana.martinez@curamas.mx',
        'is_active': true,
        'premium_enabled': true,
      },
      {
        'id': clinico2ProfileId,
        'organization_id': organizationId,
        'role': 'clinico',
        'full_name': 'Lic. Carlos Ramirez',
        'email': 'carlos.ramirez@curamas.mx',
        'is_active': true,
        'premium_enabled': false,
      },
      {
        'id': masterProfileId,
        'organization_id': null,
        'role': 'master',
        'full_name': 'Master KuraTracker',
        'email': 'master@kuratracker.mx',
        'is_active': true,
        'premium_enabled': false,
      },
      {
        'id': adminVitalisProfileId,
        'organization_id': organizationId2,
        'role': 'admin',
        'full_name': 'Administradora Vitalis',
        'email': 'admin@vitalis.mx',
        'is_active': true,
        'premium_enabled': false,
      },
    ]);

    // ---------------- Personal sanitario ----------------
    // adminStaffId: fila de staff para el administrador (Adjuste #3 -
    // admin-clinico con licencia individual). En produccion la crea
    // create_organization_with_admin()/ensureAdminStaffId() de forma
    // perezosa; aqui se siembra directamente para que el modo demo ya
    // refleje el mismo esquema (el admin puede registrar consultas y
    // se le auto-asignan los pacientes que da de alta, igual que
    // cualquier otro miembro del personal).
    final adminStaffId = _uuid.v4();
    final staff1Id = _uuid.v4();
    final staff2Id = _uuid.v4();
    final adminVitalisStaffId = _uuid.v4();

    await store.saveAll(Collections.staff, [
      {
        'id': adminStaffId,
        'organization_id': organizationId,
        'profile_id': adminProfileId,
        'folio': '',
        'full_name': 'Administrador Procomsa',
        'role_title': 'Administrador',
        'primary_site_id': siteClinicaCdmx,
        'is_active': true,
        'created_at': iso(now.subtract(const Duration(days: 400))),
      },
      {
        'id': staff1Id,
        'organization_id': organizationId,
        'profile_id': clinico1ProfileId,
        'folio': 'K2024-0001',
        'full_name': 'Dra. Ana Martinez',
        'role_title': 'Kuradora / Medico',
        'primary_site_id': siteClinicaCdmx,
        'is_active': true,
        'created_at': iso(now.subtract(const Duration(days: 400))),
      },
      {
        'id': staff2Id,
        'organization_id': organizationId,
        'profile_id': clinico2ProfileId,
        'folio': 'K2024-0002',
        'full_name': 'Lic. Carlos Ramirez',
        'role_title': 'Kurador',
        'primary_site_id': siteClinicaGdl,
        'is_active': true,
        'created_at': iso(now.subtract(const Duration(days: 250))),
      },
      // Staff del admin de Clinica Vitalis (segundo centro, ver
      // organizationId2 mas arriba) -- mismo patron que adminStaffId.
      {
        'id': adminVitalisStaffId,
        'organization_id': organizationId2,
        'profile_id': adminVitalisProfileId,
        'folio': '',
        'full_name': 'Administradora Vitalis',
        'role_title': 'Administrador',
        'primary_site_id': siteVitalisMty,
        'is_active': true,
        'created_at': iso(now.subtract(const Duration(days: 30))),
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
        'organization_id': organizationId,
        'folio': 'EXP2025-0001',
        'full_name': 'Roberto Sanchez Lopez',
        'birth_date': isoDate(DateTime(1958, 3, 12)),
        'sex': 'M',
        'primary_site_id': siteClinicaCdmx,
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
        'organization_id': organizationId,
        'folio': 'EXP2025-0002',
        'full_name': 'Guadalupe Torres Ibarra',
        'birth_date': isoDate(DateTime(1940, 7, 5)),
        'sex': 'F',
        'primary_site_id': siteDomicilioCdmx,
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
        'organization_id': organizationId,
        'folio': 'EXP2025-0003',
        'full_name': 'Fernando Castillo Vega',
        'birth_date': isoDate(DateTime(1952, 11, 20)),
        'sex': 'M',
        'primary_site_id': siteClinicaCdmx,
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
        'organization_id': organizationId,
        'folio': 'EXP2025-0004',
        'full_name': 'Patricia Nunez Reyes',
        'birth_date': isoDate(DateTime(1975, 2, 18)),
        'sex': 'F',
        'primary_site_id': siteClinicaGdl,
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
        'organization_id': organizationId,
        'folio': 'PA2026-0005',
        'full_name': 'Miguel Angel Duran',
        'birth_date': isoDate(DateTime(1990, 9, 30)),
        'sex': 'M',
        'primary_site_id': siteClinicaGdl,
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
        'site_id': siteClinicaCdmx,
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
        'site_id': siteClinicaCdmx,
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
        'site_id': siteClinicaCdmx,
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
        'site_id': siteDomicilioCdmx,
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
        'site_id': siteClinicaCdmx,
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
        'site_id': siteClinicaGdl,
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
        'site_id': siteClinicaGdl,
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

    // ---------------- Catalogo de conceptos de nota de seguimiento ----------------
    // Espejo de la precarga de la migracion 0010_note_option_catalog.sql
    // (+ kura_tag de 0013_note_option_catalog_kura_tag.sql / defaultNoteOptionCatalog
    // en DataRepository), para que el modo demo local tenga los mismos
    // chips base -- con las mismas etiquetas de mapeo al motor -- que
    // produccion (el admin los administra igual desde Configuracion).
    final noteOptionRows = <Map<String, dynamic>>[];
    void noteOption(String field, String label, [String? kuraTag]) {
      noteOptionRows.add({
        'id': _uuid.v4(),
        'organization_id': organizationId,
        'field': field,
        'label': label,
        'is_active': true,
        'created_by': null,
        'created_at': iso(now),
        'kura_tag': kuraTag,
      });
    }

    noteOption('care_type', 'Curación ambulatoria');
    noteOption('care_type', 'Visita domiciliaria');
    noteOption('care_type', 'Curación en hospitalización');
    noteOption('care_type', 'Interconsulta');
    noteOption('care_type', 'Desbridamiento programado', 'desbridamiento');
    noteOption('procedure_desc', 'Limpieza con solución salina y cambio de apósito', 'limpieza');
    noteOption('procedure_desc', 'Desbridamiento cortante parcial', 'desbridamiento');
    noteOption('procedure_desc', 'Desbridamiento autolítico/enzimático', 'desbridamiento');
    noteOption('procedure_desc', 'Toma de medidas y fotografía de control');
    noteOption('procedure_desc', 'Aplicación de terapia compresiva', 'compresion');
    noteOption('procedure_desc', 'Educación al paciente/cuidador', 'educacion');
    noteOption('materials_used', 'Solución salina 0.9%', 'limpieza');
    noteOption('materials_used', 'Yodopovidona 10%', 'antimicrobiano');
    noteOption('materials_used', 'Apósito de espuma (foam)', 'aposito');
    noteOption('materials_used', 'Apósito de alginato', 'aposito');
    noteOption('materials_used', 'Apósito hidrocoloide', 'aposito');
    noteOption('materials_used', 'Gasa estéril', 'aposito');
    noteOption('materials_used', 'Vendaje de compresión', 'compresion');
    noteOption('evolution', 'Favorable, con reducción de área');
    noteOption('evolution', 'Estable, sin cambios significativos');
    noteOption('evolution', 'Sin avance esperado para la semana de tratamiento');
    noteOption('evolution', 'Signos de infección local');
    noteOption('evolution', 'Mejoría del tejido de granulación');
    await store.saveAll(Collections.noteOptionCatalog, noteOptionRows);

    // ================================================================
    // Datos de demo ADICIONALES: trayectorias variadas (verde/ámbar/rojo/
    // sin datos) en varios cuadros diagnósticos, para que el tablero y las
    // gráficas de evolución luzcan en la demo. Se AGREGA con getAll+saveAll
    // (saveAll sobrescribe la colección; por eso se re-lee antes de guardar).
    // Las series de área están calibradas al checkpoint de Sheehan (sem. 4:
    // ≥50% cierre / ≥30% observación / <30% no avanza).
    // ================================================================
    Future<void> appendRows(String c, List<Map<String, dynamic>> rows) async {
      await store.saveAll(c, [...store.getAll(c), ...rows]);
    }

    Map<String, dynamic> meas(String woundId, String consultId, DateTime d,
        double area, int gran, int slough, int necr, int epi, double depth) {
      return {
        'id': _uuid.v4(),
        'wound_id': woundId,
        'consultation_id': consultId,
        'measured_at': isoDate(d),
        'length_cm': double.parse((area / 2).toStringAsFixed(1)),
        'width_cm': 2.0,
        'area_cm2': area,
        'depth_cm': depth,
        'tunneling': false,
        'undermining': false,
        'granulation_pct': gran,
        'slough_pct': slough,
        'necrosis_pct': necr,
        'epithelialization_pct': epi,
        'captured_before_debridement': true,
      };
    }

    Map<String, dynamic> consulta(String id, String pid, String staffId,
        String siteId, String visitType, DateTime d) {
      return {
        'id': id,
        'patient_id': pid,
        'staff_id': staffId,
        'site_id': siteId,
        'visit_type': visitType,
        'visit_date': isoDate(d),
        'vital_signs': {'ta': '120/80', 'fc': 75, 'temp': 36.5},
        'is_draft': false,
        'created_at': iso(d),
      };
    }

    // ---- Seguimientos que dan trayectoria a pacientes ya existentes ----
    // p4 (quirúrgica): mejora franca -> verde.
    final c4bId = _uuid.v4();
    final c4cId = _uuid.v4();
    await appendRows(Collections.consultations, [
      consulta(c4bId, p4Id, staff2Id, siteClinicaGdl, 'seguimiento',
          now.subtract(const Duration(days: 6))),
      consulta(c4cId, p4Id, staff2Id, siteClinicaGdl, 'seguimiento', now),
    ]);
    await appendRows(Collections.woundMeasurements, [
      meas(w4Id, c4bId, now.subtract(const Duration(days: 6)), 8.0, 45, 25, 5, 25, 0.9),
      meas(w4Id, c4cId, now, 5.0, 60, 15, 0, 25, 0.6),
    ]);

    // p2 (LPP): estancada -> rojo (no avanza).
    final c2bId = _uuid.v4();
    final c2cId = _uuid.v4();
    await appendRows(Collections.consultations, [
      consulta(c2bId, p2Id, staff1Id, siteDomicilioCdmx, 'seguimiento',
          now.subtract(const Duration(days: 30))),
      consulta(c2cId, p2Id, staff1Id, siteDomicilioCdmx, 'seguimiento', now),
    ]);
    await appendRows(Collections.woundMeasurements, [
      meas(w2Id, c2bId, now.subtract(const Duration(days: 30)), 20.0, 28, 38, 24, 10, 1.7),
      meas(w2Id, c2cId, now, 19.0, 30, 36, 22, 12, 1.6),
    ]);

    // p3 (vascular isquémica): empeora -> rojo.
    final c3bId = _uuid.v4();
    final c3cId = _uuid.v4();
    await appendRows(Collections.consultations, [
      consulta(c3bId, p3Id, staff1Id, siteClinicaCdmx, 'seguimiento',
          now.subtract(const Duration(days: 15))),
      consulta(c3cId, p3Id, staff1Id, siteClinicaCdmx, 'seguimiento', now),
    ]);
    await appendRows(Collections.woundMeasurements, [
      meas(w3Id, c3bId, now.subtract(const Duration(days: 15)), 3.4, 8, 32, 48, 12, 0.6),
      meas(w3Id, c3cId, now, 3.8, 6, 34, 50, 10, 0.7),
    ]);

    // ---- Pacientes NUEVOS (cuadros y evoluciones variados) ----
    var folioSeq = 6;
    Future<void> addCase({
      required String name,
      required DateTime birth,
      required String sex,
      required String siteId,
      required String staffId,
      required String etiology,
      required String subtype,
      required String location,
      required String background,
      required List<List<String>> comorbid,
      required List<double> areas, // [basal, media, actual]
      int baselineDaysAgo = 28,
      bool fragile = false,
      Map<String, dynamic> woundExtra = const {},
    }) async {
      final pid = _uuid.v4();
      final wid = _uuid.v4();
      final cBase = _uuid.v4();
      final cMid = _uuid.v4();
      final cCur = _uuid.v4();
      final base = now.subtract(Duration(days: baselineDaysAgo));
      final mid = now.subtract(Duration(days: baselineDaysAgo ~/ 2));
      final folio = 'EXP2025-00${folioSeq.toString().padLeft(2, '0')}';
      folioSeq++;
      final improving = areas.last < areas.first;

      await appendRows(Collections.patients, [
        {
          'id': pid,
          'organization_id': organizationId,
          'folio': folio,
          'full_name': name,
          'birth_date': isoDate(birth),
          'sex': sex,
          'primary_site_id': siteId,
          'mobility': fragile ? 'encamado' : 'ambulatorio',
          'has_identified_caregiver': fragile,
          'fragile_patient': fragile,
          'background_notes': background,
          'ekare_external_id': null,
          'is_active': true,
          'created_at': iso(base),
        }
      ]);
      await appendRows(
          Collections.patientComorbidities,
          comorbid
              .map((c) => {
                    'id': _uuid.v4(),
                    'patient_id': pid,
                    'code': c[0],
                    'status': c[1],
                  })
              .toList());
      await appendRows(Collections.wounds, [
        {
          'id': wid,
          'patient_id': pid,
          'etiology': etiology,
          'subtype': subtype,
          'body_location_primary': location,
          'body_location_secondary': null,
          'onset_date': isoDate(base.subtract(const Duration(days: 10))),
          'wagner_grade': woundExtra['wagner_grade'],
          'ceap_class': woundExtra['ceap_class'],
          'wuwhs_grade': woundExtra['wuwhs_grade'],
          'agente_causal': woundExtra['agente_causal'],
          'is_active': true,
          'closed_at': null,
          'created_at': iso(base),
        }
      ]);
      await appendRows(Collections.consultations, [
        consulta(cBase, pid, staffId, siteId, 'valoracion', base),
        consulta(cMid, pid, staffId, siteId, 'seguimiento', mid),
        consulta(cCur, pid, staffId, siteId, 'seguimiento', now),
      ]);
      await appendRows(Collections.woundAssessments, [
        {
          'id': _uuid.v4(),
          'consultation_id': cBase,
          'wound_id': wid,
          'glucose_mg_dl': null,
          'first_assessment_date': isoDate(base),
          'edema': 'leve',
          'pain': true,
          'pain_type': 'nociceptivo',
          'pain_duration': 'cronico',
          'pain_vas': 4,
          'exudate_amount': 'moderado',
          'infection_criteria': <String>[],
          'odor': 'leve',
          'wound_edge': 'definido',
          'perilesional_skin': ['normal'],
        }
      ]);
      final cB = improving ? [40, 35, 10, 15] : [30, 35, 25, 10];
      final cM = improving ? [55, 22, 5, 18] : [28, 36, 26, 10];
      final cC = improving ? [70, 12, 0, 18] : [25, 38, 27, 10];
      await appendRows(Collections.woundMeasurements, [
        meas(wid, cBase, base, areas[0], cB[0], cB[1], cB[2], cB[3], 0.6),
        meas(wid, cMid, mid, areas[1], cM[0], cM[1], cM[2], cM[3], 0.5),
        meas(wid, cCur, now, areas[2], cC[0], cC[1], cC[2], cC[3], 0.4),
      ]);
      await appendRows(Collections.staffPatientAssignments, [
        {'id': _uuid.v4(), 'staff_id': staffId, 'patient_id': pid},
      ]);
    }

    // Verde (avanza): venosa mejorando.
    await addCase(
      name: 'Laura Jiménez Ruiz',
      birth: DateTime(1963, 4, 22),
      sex: 'F',
      siteId: siteClinicaGdl,
      staffId: staff1Id,
      etiology: 'vascular',
      subtype: 'Úlcera venosa',
      location: 'pierna_derecha_tercio_distal',
      background: 'Insuficiencia venosa crónica; buena adherencia a compresión.',
      comorbid: [
        ['obesidad', 'presente'],
        ['diabetes_mellitus', 'negado'],
      ],
      areas: [12.0, 8.0, 4.5],
      woundExtra: {'ceap_class': 'c6'},
    );
    // Ámbar (con reservas): pie diabético estancándose.
    await addCase(
      name: 'José Herrera Campos',
      birth: DateTime(1955, 8, 3),
      sex: 'M',
      siteId: siteClinicaCdmx,
      staffId: staff2Id,
      etiology: 'pie_diabetico',
      subtype: 'Úlcera neuropática plantar',
      location: 'pie_izquierdo_planta',
      background: 'DM2 con neuropatía; adherencia irregular al descargo.',
      comorbid: [
        ['diabetes_mellitus', 'presente'],
        ['movilidad_reducida', 'no_evaluado'],
      ],
      areas: [9.0, 7.2, 5.9],
      woundExtra: {'wagner_grade': 'g2'},
    );
    // Rojo (no avanza): arterial empeorando.
    await addCase(
      name: 'Rosa Delgado Mora',
      birth: DateTime(1948, 12, 15),
      sex: 'F',
      siteId: siteClinicaCdmx,
      staffId: staff1Id,
      etiology: 'vascular',
      subtype: 'Úlcera arterial',
      location: 'pie_derecho_dorso',
      background: 'Enfermedad arterial periférica; dolor isquémico en reposo.',
      comorbid: [
        ['enfermedad_arterial_periferica', 'presente'],
        ['tabaquismo_activo', 'presente'],
      ],
      areas: [6.0, 6.6, 7.2],
    );
    // Ámbar (con reservas): LPP con avance lento.
    await addCase(
      name: 'Antonio Ríos Peña',
      birth: DateTime(1938, 1, 9),
      sex: 'M',
      siteId: siteDomicilioGdl,
      staffId: staff2Id,
      etiology: 'lpp',
      subtype: 'LPP categoría II',
      location: 'talon_derecho',
      background: 'Movilidad reducida, atención domiciliaria.',
      comorbid: [
        ['movilidad_reducida', 'presente'],
        ['malnutricion', 'presente'],
      ],
      areas: [8.0, 6.6, 5.3],
      fragile: true,
    );
    // Verde (avanza): quirúrgica cerrando bien.
    await addCase(
      name: 'Carmen Solís Vega',
      birth: DateTime(1980, 6, 27),
      sex: 'F',
      siteId: siteClinicaCdmx,
      staffId: adminStaffId,
      etiology: 'quirurgica',
      subtype: 'Herida quirúrgica (cierre por 2a intención)',
      location: 'abdomen_bajo',
      background: 'Postoperatorio de cesárea, sin datos de infección.',
      comorbid: [
        ['obesidad', 'presente'],
      ],
      areas: [7.0, 4.0, 2.4],
      baselineDaysAgo: 21,
    );
    // Rojo (no avanza): herida de etiología mixta estancada.
    await addCase(
      name: 'Héctor Navarro Luna',
      birth: DateTime(1969, 10, 2),
      sex: 'M',
      siteId: siteClinicaGdl,
      staffId: staff1Id,
      etiology: 'otra',
      subtype: 'Úlcera de etiología mixta',
      location: 'pierna_izquierda',
      background: 'Úlcera crónica de etiología mixta en estudio.',
      comorbid: [
        ['diabetes_mellitus', 'presente'],
        ['enfermedad_arterial_periferica', 'presente'],
      ],
      areas: [10.0, 9.4, 8.8],
    );

    // ---- Caso con EVIDENCIA FOTOGRÁFICA real (LPP sacra, 5 visitas) ----
    // Fotos de una evolución compartida para demostración (ver
    // demo_wound_photos.dart). 5 puntos (basal -> 4 seguimientos) con área
    // decreciente y composición del lecho mejorando, para lucir el antes/
    // después, el % de reducción y la galería en el reporte y el detalle.
    {
      final pid = _uuid.v4();
      final wid = _uuid.v4();
      final folio = 'EXP2025-00${folioSeq.toString().padLeft(2, '0')}';
      folioSeq++;
      final dates =
          [28, 21, 14, 7, 0].map((d) => now.subtract(Duration(days: d))).toList();
      final areas = [24.0, 18.0, 12.0, 7.0, 3.5];
      // [granulación, esfacelo, necrosis, epitelización] por visita.
      final comps = [
        [10, 35, 45, 10],
        [25, 40, 25, 10],
        [45, 35, 8, 12],
        [65, 20, 0, 15],
        [78, 7, 0, 15],
      ];
      final depths = [1.8, 1.5, 1.1, 0.7, 0.4];
      final consultIds = List.generate(5, (_) => _uuid.v4());
      final measIds = List.generate(5, (_) => _uuid.v4());

      await appendRows(Collections.patients, [
        {
          'id': pid,
          'organization_id': organizationId,
          'folio': folio,
          'full_name': 'Ricardo Salinas Vega',
          'birth_date': isoDate(DateTime(1948, 3, 15)),
          'sex': 'M',
          'primary_site_id': siteDomicilioCdmx,
          'mobility': 'encamado',
          'has_identified_caregiver': true,
          'caregiver_name': 'Marta Salinas (hija)',
          'caregiver_phone': '55 1234 5678',
          'fragile_patient': true,
          'background_notes':
              'Paciente encamado. LPP sacra grado 3, manejo domiciliario.',
          'ekare_external_id': null,
          'is_active': true,
          'created_at': iso(dates.first),
        }
      ]);
      await appendRows(Collections.patientComorbidities, [
        {'id': _uuid.v4(), 'patient_id': pid, 'code': 'diabetes_mellitus', 'status': 'presente'},
        {'id': _uuid.v4(), 'patient_id': pid, 'code': 'malnutricion', 'status': 'presente'},
      ]);
      await appendRows(Collections.wounds, [
        {
          'id': wid,
          'patient_id': pid,
          'etiology': 'lpp',
          'subtype': 'Lesión por presión',
          'body_location_primary': 'sacro',
          'body_location_secondary': null,
          'onset_date': isoDate(dates.first.subtract(const Duration(days: 14))),
          'wagner_grade': null,
          'ceap_class': null,
          'wuwhs_grade': 'g3',
          'agente_causal': null,
          'is_active': true,
          'closed_at': null,
          'created_at': iso(dates.first),
        }
      ]);
      final consults = <Map<String, dynamic>>[];
      final measures = <Map<String, dynamic>>[];
      final photos = <Map<String, dynamic>>[];
      for (var i = 0; i < 5; i++) {
        final type = i == 0 ? 'valoracion' : 'seguimiento';
        consults.add(
            consulta(consultIds[i], pid, staff1Id, siteDomicilioCdmx, type, dates[i]));
        final c = comps[i];
        measures.add({
          ...meas(wid, consultIds[i], dates[i], areas[i], c[0], c[1], c[2], c[3], depths[i]),
          'id': measIds[i],
        });
        photos.add({
          'id': _uuid.v4(),
          'wound_id': wid,
          'consultation_id': consultIds[i],
          'measurement_id': measIds[i],
          'storage_path': DemoWoundPhotos.all[i],
          'taken_at': iso(dates[i]),
          'is_baseline': i == 0,
          'photo_stage': null,
        });
      }
      await appendRows(Collections.consultations, consults);
      await appendRows(Collections.woundMeasurements, measures);
      await appendRows(Collections.woundPhotos, photos);
      await appendRows(Collections.woundAssessments, [
        {
          'id': _uuid.v4(),
          'consultation_id': consultIds.first,
          'wound_id': wid,
          'first_assessment_date': isoDate(dates.first),
          'edema': 'moderado',
          'pain': true,
          'pain_vas': 5,
          'exudate_amount': 'abundante',
          'infection_criteria': <String>[],
          'odor': 'moderado',
          'wound_edge': 'macerado',
          'perilesional_skin': ['macerada'],
        }
      ]);
      await appendRows(Collections.staffPatientAssignments, [
        {'id': _uuid.v4(), 'staff_id': staff1Id, 'patient_id': pid},
      ]);
    }
  }
}
