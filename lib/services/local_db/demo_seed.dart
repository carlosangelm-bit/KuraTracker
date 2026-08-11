import 'package:uuid/uuid.dart';
import 'demo_wound_photos.dart';
import 'local_store.dart';

const _uuid = Uuid();

/// Siembra datos de demostración realistas y CURADOS por escenario:
///
///  1. Clínica de heridas (Kura+, paleta morada) — recorrido de TRATAMIENTO
///     foto-primero: alta → consentimientos → comorbilidades/diagnósticos →
///     consulta → captura y mediciones seriadas → seguimientos → plan →
///     referencia/evento adverso → reportes/eKare. 7 pacientes que cubren las
///     etiologías y las 4 trayectorias (mejora / estanca / empeora / cerrada),
///     uno de ellos con evidencia fotográfica real.
///
///  2. Hospital (paleta azul) — recorrido de PREVENCIÓN centrado en el paciente:
///     internamiento (piso/área/cama) → valoración de Braden → tablero de riesgo
///     → rondas (tareas SIN dueño, las marca quien está de turno) → dashboard del
///     centro (distribución por banda, cumplimiento por turno). 5 pacientes que
///     cubren las 4 bandas de Braden (muy alto / alto / medio / bajo).
///
///  3. Cuidadores (paleta rosa) — recorrido del CUIDADOR: monitoreo de sus
///     pacientes asignados, tareas con estados variados (hecha / vencida /
///     futura) e indicaciones del centro. 3 pacientes a domicilio.
///
/// Se ejecuta una sola vez (marca el flag versionado en LocalStore) para
/// permitir una demo navegable inmediata. Solo aplica al modo demo local
/// (SharedPreferences); producción usa Supabase y nunca llama a este seed.
class DemoSeed {
  // Flag VERSIONADO: al enriquecer/limpiar el set de demo, se re-siembra limpio
  // una sola vez en instalaciones demo previas (wipeAll + _seed), evitando
  // duplicados y datos viejos. Cada rediseño del roster sube este número.
  // v12: roster curado por escenario (clínica 7 / hospital 5 / cuidadores 3).
  static const String _seedFlag = 'seeded_v24';

  static Future<void> ensureSeeded(LocalStore store) async {
    if (store.getBool(_seedFlag)) return;
    // Limpia cualquier siembra anterior para no duplicar filas ni arrastrar
    // pacientes de versiones previas.
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

    // saveAll SOBRESCRIBE la colección completa; los constructores por escenario
    // agregan filas de forma incremental, así que se re-lee antes de guardar.
    Future<void> appendRows(String c, List<Map<String, dynamic>> rows) async {
      await store.saveAll(c, [...store.getAll(c), ...rows]);
    }

    // ---------------- Organizaciones (centros) ----------------
    // El centro es el tenant raíz; sitios, personal, pacientes y catálogo de
    // notas quedan aislados por organizationId. Cuatro centros: dos clínicas de
    // heridas (moradas), un hospital (azul) y un centro de cuidadores (rosa).
    final organizationId = _uuid.v4(); // Kura+ (clínica principal)
    final organizationId2 = _uuid.v4(); // Clínica Vitalis (2º tenant, para master)
    final organizationIdHospital = _uuid.v4();
    final organizationIdCuidadores = _uuid.v4();

    await store.saveAll(Collections.organizations, [
      {
        'id': organizationId,
        'name': 'Kura+',
        'is_active': true,
        'center_type': 'clinica_heridas',
        // Demo: la clínica opera su agenda en modo MANUAL (la integración Acuity
        // solo lee de Supabase, no aplica en local) para poder mostrar citas.
        'scheduling_mode': 'manual',
        // Demo: add-ons premium del centro activos para mostrar el módulo de
        // Insumos (0047) y el Protocolo Kura+ para todo el centro (0049).
        'premium_insumos': true,
        'premium_protocolo_kura': true,
        'created_at': iso(now.subtract(const Duration(days: 400))),
      },
      {
        'id': organizationId2,
        'name': 'Clínica Vitalis',
        'is_active': true,
        'center_type': 'clinica_heridas',
        'created_at': iso(now.subtract(const Duration(days: 30))),
      },
      {
        'id': organizationIdHospital,
        'name': 'Hospital General Demo',
        'is_active': true,
        'center_type': 'hospital',
        // Turnos del centro (módulo de prevención hospitalaria): alimentan la
        // ventana de cumplimiento por turno del dashboard (/hospital).
        'shift_config': [
          {'name': 'Matutino', 'startHour': 7, 'endHour': 15},
          {'name': 'Vespertino', 'startHour': 15, 'endHour': 23},
          {'name': 'Nocturno', 'startHour': 23, 'endHour': 7},
        ],
        'created_at': iso(now.subtract(const Duration(days: 20))),
      },
      {
        'id': organizationIdCuidadores,
        'name': 'Cuidados en Casa Demo',
        'is_active': true,
        'center_type': 'cuidadores',
        'created_at': iso(now.subtract(const Duration(days: 10))),
      },
    ]);

    // ---------------- Sitios ----------------
    final siteClinicaCdmx = _uuid.v4();
    final siteClinicaGdl = _uuid.v4();
    final siteDomicilioCdmx = _uuid.v4();
    final siteDomicilioGdl = _uuid.v4();
    final siteVitalisMty = _uuid.v4();

    await store.saveAll(Collections.sites, [
      {
        'id': siteClinicaCdmx,
        'organization_id': organizationId,
        'name': 'Kura+ Clínica CDMX',
        'kind': 'clinica',
        'address': 'Av. Reforma 123, CDMX',
        'is_active': true,
      },
      {
        'id': siteClinicaGdl,
        'organization_id': organizationId,
        'name': 'Kura+ Clínica GDL',
        'kind': 'clinica',
        'address': 'Av. Vallarta 456, Guadalajara',
        'is_active': true,
      },
      {
        'id': siteDomicilioCdmx,
        'organization_id': organizationId,
        'name': 'Atención a domicilio CDMX',
        'kind': 'domicilio',
        'address': null,
        'is_active': true,
      },
      {
        'id': siteDomicilioGdl,
        'organization_id': organizationId,
        'name': 'Atención a domicilio GDL',
        'kind': 'domicilio',
        'address': null,
        'is_active': true,
      },
      {
        'id': siteVitalisMty,
        'organization_id': organizationId2,
        'name': 'Vitalis Clínica Monterrey',
        'kind': 'clinica',
        'address': 'Av. Constitución 789, Monterrey',
        'is_active': true,
      },
    ]);

    // ---------------- Usuarios / Perfiles ----------------
    final adminProfileId = _uuid.v4();
    final clinico1ProfileId = _uuid.v4();
    final clinico2ProfileId = _uuid.v4();
    // El perfil Master (plataforma) es de acceso interno y no se siembra en la
    // demo (ver más abajo): no se declara su id.
    final adminVitalisProfileId = _uuid.v4();
    // Cuidador demo: login por teléfono (5512345678 + clave). El correo es
    // sintético derivado del teléfono, igual que en producción.
    final cuidadorProfileId = _uuid.v4();
    // Enfermería demo: personal del Hospital demo (acceso center-wide, ejecuta
    // rondas pero no diagnostica/prescribe).
    final enfermeriaProfileId = _uuid.v4();

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
        'full_name': 'Dra. Ana Martínez',
        'email': 'ana.martinez@curamas.mx',
        'is_active': true,
        'premium_enabled': true,
      },
      {
        'id': clinico2ProfileId,
        'organization_id': organizationId,
        'role': 'clinico',
        'full_name': 'Lic. Carlos Ramírez',
        'email': 'carlos.ramirez@curamas.mx',
        'is_active': true,
        'premium_enabled': false,
      },
      // El perfil Master (plataforma) NO se siembra en la demo: es de acceso
      // interno. Se omite a propósito para que no pueda entrarse como master
      // ni desde el selector de perfiles ni tecleando su correo en el login.
      {
        'id': adminVitalisProfileId,
        'organization_id': organizationId2,
        'role': 'admin',
        'full_name': 'Administradora Vitalis',
        'email': 'admin@vitalis.mx',
        'is_active': true,
        'premium_enabled': false,
      },
      {
        'id': cuidadorProfileId,
        'organization_id': organizationIdCuidadores,
        'role': 'cuidador',
        'full_name': 'Cuidador Demo',
        'email': '5512345678@cuidador.kuramas.com',
        'phone': '5512345678',
        'is_active': true,
        'premium_enabled': false,
      },
      {
        'id': enfermeriaProfileId,
        'organization_id': organizationIdHospital,
        'role': 'enfermeria',
        'full_name': 'Enfermería Demo',
        'email': 'enfermeria@hospital.mx',
        'is_active': true,
        'premium_enabled': false,
      },
    ]);

    // ---------------- Membresías de centro ----------------
    // El admin Procomsa tiene membresía a los 3 tipos de centro (Kura+, Hospital,
    // Cuidadores) para DEMOSTRAR el switcher del ícono de apósitos (paleta
    // morado → azul → rosa). El resto tiene una sola membresía a su centro.
    await store.saveAll(Collections.userCenterMemberships, [
      for (final orgId in [
        organizationId,
        organizationIdHospital,
        organizationIdCuidadores
      ])
        {
          'id': _uuid.v4(),
          'profile_id': adminProfileId,
          'organization_id': orgId,
          'role': 'admin',
          'is_active': true,
          'created_at': iso(now),
        },
      {
        'id': _uuid.v4(),
        'profile_id': clinico1ProfileId,
        'organization_id': organizationId,
        'role': 'clinico',
        'is_active': true,
        'created_at': iso(now),
      },
      {
        'id': _uuid.v4(),
        'profile_id': clinico2ProfileId,
        'organization_id': organizationId,
        'role': 'clinico',
        'is_active': true,
        'created_at': iso(now),
      },
      {
        'id': _uuid.v4(),
        'profile_id': adminVitalisProfileId,
        'organization_id': organizationId2,
        'role': 'admin',
        'is_active': true,
        'created_at': iso(now),
      },
      {
        'id': _uuid.v4(),
        'profile_id': cuidadorProfileId,
        'organization_id': organizationIdCuidadores,
        'role': 'cuidador',
        'is_active': true,
        'created_at': iso(now),
      },
      {
        'id': _uuid.v4(),
        'profile_id': enfermeriaProfileId,
        'organization_id': organizationIdHospital,
        'role': 'enfermeria',
        'is_active': true,
        'created_at': iso(now),
      },
    ]);

    // ---------------- Personal sanitario ----------------
    final adminStaffId = _uuid.v4();
    final staff1Id = _uuid.v4();
    final staff2Id = _uuid.v4();
    final adminVitalisStaffId = _uuid.v4();
    final enfermeriaStaffId = _uuid.v4();

    await store.saveAll(Collections.staff, [
      {
        'id': enfermeriaStaffId,
        'organization_id': organizationIdHospital,
        'profile_id': enfermeriaProfileId,
        'folio': 'ENF-0001',
        'full_name': 'Enfermería Demo',
        'role_title': 'Enfermería',
        'is_active': true,
        'created_at': iso(now.subtract(const Duration(days: 5))),
      },
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
        'full_name': 'Dra. Ana Martínez',
        'role_title': 'Kuradora / Médico',
        'primary_site_id': siteClinicaCdmx,
        'is_active': true,
        'created_at': iso(now.subtract(const Duration(days: 400))),
      },
      {
        'id': staff2Id,
        'organization_id': organizationId,
        'profile_id': clinico2ProfileId,
        'folio': 'K2024-0002',
        'full_name': 'Lic. Carlos Ramírez',
        'role_title': 'Kurador',
        'primary_site_id': siteClinicaGdl,
        'is_active': true,
        'created_at': iso(now.subtract(const Duration(days: 250))),
      },
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

    // ---------------- Catálogo de conceptos de nota ----------------
    // Espejo de la precarga de producción (0010 + kura_tag de 0013): mismos chips
    // y etiquetas de mapeo al motor que en el flujo real.
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
    noteOption('procedure_desc',
        'Limpieza con solución salina y cambio de apósito', 'limpieza');
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
    // Helpers compartidos por los constructores de escenario.
    // ================================================================
    Map<String, dynamic> meas(
        String woundId, String? consultId, DateTime d, double area, int gran,
        int slough, int necr, int epi, double depth) {
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

    // ================================================================
    // ESCENARIO 1 — CLÍNICA DE HERIDAS (Kura+, morado): 7 pacientes.
    // Recorrido de tratamiento foto-primero con mediciones seriadas. Cada
    // paciente demuestra un estado distinto (etiología × trayectoria).
    // ================================================================
    var expSeq = 1;

    /// Crea un caso clínico completo en Kura+ y devuelve los ids clave (paciente,
    /// herida, consultas) para adjuntar extras (referencia, evento adverso, etc.).
    Future<Map<String, dynamic>> addClinicalCase({
      required String name,
      required DateTime birth,
      required String sex,
      required String siteId,
      required String staffId,
      required String mobility,
      required String background,
      required String etiology,
      required String subtype,
      required String location,
      required List<List<String>> comorbid, // [code, status]
      required List<double> areas, // serie de área basal → actual
      required List<List<int>> comps, // [gran, slough, necr, epi] por visita
      List<Map<String, String>> diagnoses = const [], // {code,name,relation,primary}
      List<double>? depths,
      int baselineDaysAgo = 28,
      bool fragile = false,
      String? caregiverName,
      String? caregiverPhone,
      String? ekareId,
      Map<String, dynamic> woundExtra = const {},
      double? glucose,
      List<String> infectionCriteria = const [],
      double? abiRight,
      double? abiLeft,
      bool isLowerExtremity = false,
      double? albumin,
      bool closed = false,
      String? dischargeNote,
      String? treatmentDescription,
      List<List<String>> treatmentComponents = const [], // [method, product]
      bool withPhotos = false, // foto basal + más reciente (evidencia antes/después)
      bool withFollowUpNotes = false, // narrativa de seguimiento por visita
      String followUpSignedBy = 'Dra. Ana Martínez',
      String followUpSignedLicense = 'K2024-0001',
    }) async {
      final pid = _uuid.v4();
      final wid = _uuid.v4();
      final folio = 'EXP2026-${expSeq.toString().padLeft(4, '0')}';
      expSeq++;
      final n = areas.length;
      final dates = List<DateTime>.generate(
          n,
          (i) => now.subtract(
              Duration(days: (baselineDaysAgo * (n - 1 - i) / (n - 1)).round())));
      final dpt = depths ??
          List<double>.generate(
              n,
              (i) => double.parse(
                  (0.6 - 0.35 * i / (n - 1)).toStringAsFixed(2)));
      final consultIds = List.generate(n, (_) => _uuid.v4());

      await appendRows(Collections.patients, [
        {
          'id': pid,
          'organization_id': organizationId,
          'folio': folio,
          'full_name': name,
          'birth_date': isoDate(birth),
          'sex': sex,
          'primary_site_id': siteId,
          'mobility': mobility,
          'has_identified_caregiver': caregiverName != null,
          if (caregiverName != null) 'caregiver_name': caregiverName,
          if (caregiverPhone != null) 'caregiver_phone': caregiverPhone,
          'fragile_patient': fragile,
          'background_notes': background,
          'ekare_external_id': ekareId,
          'is_active': true,
          'created_at': iso(dates.first),
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
      if (diagnoses.isNotEmpty) {
        await appendRows(
            Collections.patientDiagnoses,
            diagnoses
                .map((d) => {
                      'id': _uuid.v4(),
                      'organization_id': organizationId,
                      'patient_id': pid,
                      'wound_id': null,
                      'staff_id': staffId,
                      'code': d['code'],
                      'name': d['name'],
                      'relation': d['relation'],
                      'is_primary': d['primary'] == 'true',
                      'status': 'activo',
                      'notes': null,
                      'noted_at': iso(dates.first),
                      'noted_by': null,
                      'created_at': iso(dates.first),
                    })
                .toList());
      }
      // Consentimientos otorgados (el flujo foto-primero los requiere).
      await appendRows(Collections.consents, [
        for (final type in ['privacidad', 'fotografia', 'desbridamiento'])
          {
            'id': _uuid.v4(),
            'patient_id': pid,
            'type': type,
            'granted': true,
            'granted_at': iso(dates.first),
            'signed_by': 'Paciente (demo)',
            'doc_ref': null,
            'created_at': iso(dates.first),
          }
      ]);
      await appendRows(Collections.wounds, [
        {
          'id': wid,
          'patient_id': pid,
          'etiology': etiology,
          'subtype': subtype,
          'body_location_primary': location,
          'body_location_secondary': null,
          'onset_date': isoDate(dates.first.subtract(const Duration(days: 12))),
          'wagner_grade': woundExtra['wagner_grade'],
          'ceap_class': woundExtra['ceap_class'],
          'wuwhs_grade': woundExtra['wuwhs_grade'],
          'agente_causal': woundExtra['agente_causal'],
          'discharge_reason': closed ? 'cierre' : null,
          'discharge_note': dischargeNote,
          'is_active': !closed,
          'closed_at': closed ? iso(dates.last) : null,
          'created_at': iso(dates.first),
        }
      ]);
      final consults = <Map<String, dynamic>>[];
      for (var i = 0; i < n; i++) {
        final row = consulta(consultIds[i], pid, staffId, siteId,
            i == 0 ? 'valoracion' : 'seguimiento', dates[i]);
        if (withFollowUpNotes && i > 0) {
          final c = comps[i];
          final prev = areas[i - 1];
          final cur = areas[i];
          final trend = cur < prev * 0.98
              ? 'en mejoría'
              : (cur > prev * 1.02 ? 'con deterioro' : 'estable');
          row.addAll({
            'follow_up_care_type': 'Curación avanzada',
            'follow_up_procedure_desc':
                'Limpieza con solución salina 0.9%, desbridamiento de esfacelo '
                    'según hallazgos y colocación de apósito acorde al exudado.',
            'follow_up_materials_used':
                'Solución salina 0.9%, gasas estériles, apósito primario '
                    '(espuma/hidrocoloide según exudado).',
            'follow_up_evolution':
                'Lecho de ${cur.toStringAsFixed(1)} cm²; granulación ${c[0]}%, '
                    'esfacelo ${c[1]}%${c[2] > 0 ? ', necrosis ${c[2]}%' : ''}, '
                    'epitelización ${c[3]}%. Evolución $trend.',
            'follow_up_signed_by': followUpSignedBy,
            'follow_up_signed_license': followUpSignedLicense,
          });
        }
        consults.add(row);
      }
      await appendRows(Collections.consultations, consults);
      await appendRows(Collections.woundAssessments, [
        {
          'id': _uuid.v4(),
          'consultation_id': consultIds.first,
          'wound_id': wid,
          'glucose_mg_dl': glucose,
          'first_assessment_date': isoDate(dates.first),
          'edema': 'leve',
          'pain': true,
          'pain_type': 'nociceptivo',
          'pain_duration': 'cronico',
          'pain_vas': 4,
          'exudate_amount': 'moderado',
          'infection_criteria': infectionCriteria,
          'odor': infectionCriteria.isEmpty ? 'ninguno' : 'moderado',
          'wound_edge': 'definido',
          'perilesional_skin': ['normal'],
        }
      ]);
      final measures = <Map<String, dynamic>>[];
      for (var i = 0; i < n; i++) {
        final c = comps[i];
        measures.add(meas(wid, consultIds[i], dates[i], areas[i], c[0], c[1],
            c[2], c[3], dpt[i]));
      }
      await appendRows(Collections.woundMeasurements, measures);
      // Evidencia fotográfica: basal (primera visita) + más reciente (última),
      // para lucir el antes/después en el detalle y el reporte. Se usan las dos
      // imágenes más ligeras para no exceder la cuota de almacenamiento local.
      if (withPhotos) {
        final photoRows = <Map<String, dynamic>>[
          {
            'id': _uuid.v4(),
            'wound_id': wid,
            'consultation_id': consultIds.first,
            'measurement_id': measures.first['id'],
            'storage_path': DemoWoundPhotos.all[0],
            'taken_at': iso(dates.first),
            'is_baseline': true,
            'photo_stage': null,
          },
          if (n > 1)
            {
              'id': _uuid.v4(),
              'wound_id': wid,
              'consultation_id': consultIds.last,
              'measurement_id': measures.last['id'],
              'storage_path': DemoWoundPhotos.all[1],
              'taken_at': iso(dates.last),
              'is_baseline': false,
              'photo_stage': null,
            },
        ];
        await appendRows(Collections.woundPhotos, photoRows);
      }
      if (abiRight != null || abiLeft != null || albumin != null) {
        await appendRows(Collections.perfusionNutrition, [
          {
            'id': _uuid.v4(),
            'consultation_id': consultIds.first,
            'wound_id': wid,
            'abi_right': abiRight,
            'abi_left': abiLeft,
            'is_lower_extremity': isLowerExtremity,
            'albumin_g_dl': albumin,
          }
        ]);
      }
      if (treatmentDescription != null) {
        final tpId = _uuid.v4();
        await appendRows(Collections.treatmentPlans, [
          {
            'id': tpId,
            'consultation_id': consultIds.last,
            'wound_id': wid,
            'used_kura_protocol': false,
            'final_description': treatmentDescription,
          }
        ]);
        await appendRows(Collections.treatmentComponents, [
          for (var i = 0; i < treatmentComponents.length; i++)
            {
              'id': _uuid.v4(),
              'treatment_plan_id': tpId,
              'method': treatmentComponents[i][0],
              'product': treatmentComponents[i][1],
              'origin': 'manual',
              'sort_order': i,
            }
        ]);
      }
      await appendRows(Collections.staffPatientAssignments, [
        {'id': _uuid.v4(), 'staff_id': staffId, 'patient_id': pid},
      ]);
      return {'pid': pid, 'wid': wid, 'consultIds': consultIds};
    }

    // 1. Pie diabético — MEJORANDO. Curva de cierre franca, plan establecido.
    await addClinicalCase(
      name: 'Roberto Sánchez López',
      birth: DateTime(1958, 3, 12),
      sex: 'M',
      siteId: siteClinicaCdmx,
      staffId: staff1Id,
      mobility: 'ambulatorio',
      caregiverName: 'María Sánchez (hija)',
      caregiverPhone: '555-0101',
      ekareId: 'EKARE-PT-88213',
      background: 'Diabetes mellitus tipo 2 de 15 años de evolución. Neuropatía '
          'periférica. Control glucémico en mejora tras educación.',
      etiology: 'pie_diabetico',
      subtype: 'Úlcera neuropática plantar',
      location: 'pie_derecho_planta',
      woundExtra: {'wagner_grade': 'g2'},
      comorbid: [
        ['diabetes_mellitus', 'presente'],
        ['movilidad_reducida', 'no_evaluado'],
      ],
      diagnoses: [
        {
          'code': 'L97X',
          'name': 'ÚLCERA DE MIEMBRO INFERIOR, NO CLASIFICADA EN OTRA PARTE',
          'relation': 'herida',
          'primary': 'true'
        },
        {
          'code': 'E115',
          'name':
              'DIABETES MELLITUS TIPO 2, CON COMPLICACIONES CIRCULATORIAS PERIFÉRICAS',
          'relation': 'causa',
          'primary': 'false'
        },
      ],
      areas: [8.0, 6.6, 5.1, 3.8, 2.4],
      comps: [
        [40, 35, 10, 15],
        [48, 28, 7, 17],
        [57, 20, 4, 19],
        [66, 12, 1, 21],
        [74, 5, 0, 21],
      ],
      glucose: 172,
      abiRight: 0.95,
      abiLeft: 0.92,
      isLowerExtremity: true,
      albumin: 3.6,
      withPhotos: true,
      withFollowUpNotes: true,
      treatmentDescription:
          'Descarga plantar con calzado terapéutico, curación en ambiente '
          'húmedo y control glucémico. Revisión cada 7 días.',
      treatmentComponents: [
        ['Limpieza de la herida', 'Solución salina 0.9%'],
        ['Apósito primario', 'Espuma con borde adhesivo'],
        ['Descarga', 'Calzado/plantilla de descarga'],
      ],
    );

    // 2. Venosa CEAP c6 — MEJORANDO con terapia compresiva.
    await addClinicalCase(
      name: 'Laura Jiménez Ruiz',
      birth: DateTime(1963, 4, 22),
      sex: 'F',
      siteId: siteClinicaGdl,
      staffId: staff2Id,
      mobility: 'ambulatorio',
      background: 'Insuficiencia venosa crónica; buena adherencia a compresión.',
      etiology: 'vascular',
      subtype: 'Úlcera venosa',
      location: 'pierna_derecha_tercio_distal',
      woundExtra: {'ceap_class': 'c6'},
      comorbid: [
        ['obesidad', 'presente'],
        ['diabetes_mellitus', 'negado'],
      ],
      areas: [12.0, 9.6, 7.0, 5.2, 3.6],
      comps: [
        [45, 30, 5, 20],
        [52, 24, 3, 21],
        [60, 17, 1, 22],
        [68, 10, 0, 22],
        [74, 4, 0, 22],
      ],
      abiRight: 1.0,
      abiLeft: 0.98,
      isLowerExtremity: true,
      albumin: 3.8,
      withFollowUpNotes: true,
      followUpSignedBy: 'Lic. Carlos Ramírez',
      followUpSignedLicense: 'K2024-0002',
      treatmentDescription:
          'Terapia compresiva multicapa, curación en ambiente húmedo y '
          'elevación de la extremidad. Revisión semanal.',
      treatmentComponents: [
        ['Compresión', 'Vendaje multicapa'],
        ['Apósito primario', 'Espuma'],
      ],
    );

    // 3. Arterial / isquemia crítica — EMPEORANDO → referencia + evento adverso.
    final fernando = await addClinicalCase(
      name: 'Fernando Castillo Vega',
      birth: DateTime(1952, 11, 20),
      sex: 'M',
      siteId: siteClinicaCdmx,
      staffId: staff1Id,
      mobility: 'ambulatorio',
      background: 'Enfermedad arterial periférica avanzada, tabaquismo activo '
          'intenso. Dolor isquémico en reposo.',
      etiology: 'vascular',
      subtype: 'Úlcera arterial',
      location: 'pie_izquierdo_dorso',
      comorbid: [
        ['enfermedad_arterial_periferica', 'presente'],
        ['tabaquismo_activo', 'presente'],
      ],
      diagnoses: [
        {
          'code': 'I702',
          'name': 'ATEROSCLEROSIS DE LAS ARTERIAS DE LOS MIEMBROS',
          'relation': 'causa',
          'primary': 'true'
        },
      ],
      areas: [3.0, 3.4, 3.9, 4.4, 5.0],
      comps: [
        [15, 30, 45, 10],
        [12, 31, 47, 10],
        [9, 32, 49, 10],
        [6, 33, 51, 10],
        [4, 34, 52, 10],
      ],
      depths: [0.5, 0.6, 0.7, 0.8, 0.9],
      infectionCriteria: ['eritemaPerilesional', 'calorLocal'],
      abiRight: 0.62,
      abiLeft: 0.34, // isquemia crítica en la pierna con la herida
      isLowerExtremity: true,
      albumin: 3.0,
      withPhotos: true,
      withFollowUpNotes: true,
      treatmentDescription:
          'Herida arterial con isquemia crítica: NO desbridar tejido seco; '
          'protección, control del dolor y manejo de la infección mientras se '
          'resuelve la revascularización. Curación conservadora.',
      treatmentComponents: [
        ['Limpieza de la herida', 'Solución salina 0.9% (suave)'],
        ['Protección', 'Apósito no adherente'],
        ['Manejo del dolor', 'Analgesia escalonada'],
      ],
    );
    // Referencia urgente a cirugía vascular.
    await appendRows(Collections.referrals, [
      {
        'id': _uuid.v4(),
        'organization_id': organizationId,
        'patient_id': fernando['pid'],
        'wound_id': fernando['wid'],
        'consultation_id': (fernando['consultIds'] as List).last,
        'staff_id': staff1Id,
        'especialidad': 'Angiología / Cirugía vascular',
        'motivo':
            'Isquemia crítica (ITB 0.34) con úlcera arterial en progresión; se '
            'solicita valoración para revascularización.',
        'adjuntos': {
          'reporte_ekare': true,
          'resumen_clinico': true,
          'itb': true,
        },
        'status': 'enviada',
        'referral_signed_by': 'Dra. Ana Martínez',
        'referral_signed_license': 'K2024-0001',
        'return_doc_ref': null,
        'return_notes': null,
        'returned_at': null,
        'created_at': iso(now.subtract(const Duration(days: 2))),
      }
    ]);
    // Evento adverso (deterioro isquémico).
    await appendRows(Collections.adverseEvents, [
      {
        'id': _uuid.v4(),
        'organization_id': organizationId,
        'patient_id': fernando['pid'],
        'wound_id': fernando['wid'],
        'consultation_id': (fernando['consultIds'] as List).last,
        'staff_id': staff1Id,
        'occurred_at': iso(now.subtract(const Duration(days: 2))),
        'type': 'Deterioro clínico de la herida',
        'severity': 'grave',
        'alarm_signs': {'aumento_necrosis': true, 'dolor_reposo': true},
        'description':
            'Aumento de necrosis y dolor isquémico en reposo pese al manejo.',
        'actions_taken':
            'Referencia urgente a cirugía vascular; ajuste de analgesia.',
        'evolution': 'Pendiente de valoración por especialidad.',
        'reported_at': iso(now.subtract(const Duration(days: 2))),
        'created_at': iso(now.subtract(const Duration(days: 2))),
      }
    ]);

    // 4. Quirúrgica (dehiscencia) — ESTANCADA, con datos de infección local.
    await addClinicalCase(
      name: 'Patricia Núñez Reyes',
      birth: DateTime(1975, 2, 18),
      sex: 'F',
      siteId: siteClinicaGdl,
      staffId: staff2Id,
      mobility: 'ambulatorio',
      background: 'Postquirúrgica de colecistectomía abierta, dehiscencia de '
          'herida en el 10º día postoperatorio.',
      etiology: 'quirurgica',
      subtype: 'Dehiscencia de herida quirúrgica',
      location: 'abdomen_superior',
      woundExtra: {'wuwhs_grade': 'g2'},
      comorbid: [
        ['obesidad', 'presente'],
      ],
      diagnoses: [
        {
          'code': 'T814',
          'name':
              'INFECCIÓN CONSECUTIVA A PROCEDIMIENTO, NO CLASIFICADA EN OTRA PARTE',
          'relation': 'consecuencia',
          'primary': 'true'
        },
      ],
      areas: [12.0, 11.6, 11.3, 11.1, 10.9],
      comps: [
        [30, 35, 10, 25],
        [31, 35, 9, 25],
        [30, 36, 9, 25],
        [31, 36, 8, 25],
        [32, 36, 7, 25],
      ],
      infectionCriteria: ['eritemaPerilesional', 'calorLocal'],
      glucose: 108,
      albumin: 3.4,
      withFollowUpNotes: true,
      followUpSignedBy: 'Lic. Carlos Ramírez',
      followUpSignedLicense: 'K2024-0002',
      treatmentDescription:
          'Herida estancada con datos de infección local: optimizar control de '
          'la carga bacteriana (limpieza + antimicrobiano tópico), valorar '
          'cultivo y reforzar soporte nutricional. Revisión cada 5 días.',
      treatmentComponents: [
        ['Limpieza de la herida', 'Solución salina 0.9%'],
        ['Control de infección', 'Apósito con plata'],
      ],
    );

    // 5. Pie diabético — ESTANCADO (ámbar). Adherencia irregular al descargo.
    await addClinicalCase(
      name: 'José Herrera Campos',
      birth: DateTime(1955, 8, 3),
      sex: 'M',
      siteId: siteClinicaCdmx,
      staffId: staff2Id,
      mobility: 'ambulatorio',
      background: 'DM2 con neuropatía; adherencia irregular al descargo plantar.',
      etiology: 'pie_diabetico',
      subtype: 'Úlcera neuropática plantar',
      location: 'pie_izquierdo_planta',
      woundExtra: {'wagner_grade': 'g2'},
      comorbid: [
        ['diabetes_mellitus', 'presente'],
        ['movilidad_reducida', 'no_evaluado'],
      ],
      areas: [9.0, 8.0, 7.2, 6.5, 5.9],
      comps: [
        [35, 35, 15, 15],
        [37, 34, 14, 15],
        [39, 33, 13, 15],
        [41, 32, 12, 15],
        [43, 31, 11, 15],
      ],
      glucose: 198,
      abiRight: 0.9,
      abiLeft: 0.88,
      isLowerExtremity: true,
      albumin: 3.2,
      withFollowUpNotes: true,
      followUpSignedBy: 'Lic. Carlos Ramírez',
      followUpSignedLicense: 'K2024-0002',
      treatmentDescription:
          'Progreso lento por adherencia irregular a la descarga: reforzar '
          'educación y descarga plantar estricta, curación en ambiente húmedo y '
          'control glucémico. Revisión cada 7 días.',
      treatmentComponents: [
        ['Limpieza de la herida', 'Solución salina 0.9%'],
        ['Apósito primario', 'Hidrofibra'],
        ['Descarga', 'Fieltro de descarga / calzado terapéutico'],
      ],
    );

    // 6. Quirúrgica (cesárea) — CERRADA. Historia de éxito (herida egresada).
    await addClinicalCase(
      name: 'Carmen Solís Vega',
      birth: DateTime(1990, 6, 27),
      sex: 'F',
      siteId: siteClinicaCdmx,
      staffId: adminStaffId,
      mobility: 'ambulatorio',
      background: 'Postoperatorio de cesárea, cierre por segunda intención sin '
          'datos de infección.',
      etiology: 'quirurgica',
      subtype: 'Herida quirúrgica (cierre por 2ª intención)',
      location: 'abdomen_bajo',
      comorbid: [
        ['obesidad', 'presente'],
      ],
      areas: [7.0, 4.6, 2.4, 0.8, 0.1],
      comps: [
        [50, 25, 5, 20],
        [62, 16, 2, 20],
        [74, 8, 0, 18],
        [40, 2, 0, 58],
        [8, 0, 0, 92],
      ],
      depths: [0.5, 0.35, 0.2, 0.1, 0.0],
      baselineDaysAgo: 21,
      closed: true,
      withPhotos: true,
      withFollowUpNotes: true,
      followUpSignedBy: 'Administradora Procomsa',
      followUpSignedLicense: '',
      dischargeNote:
          'Cicatrización completa a las 3 semanas. Alta de la herida; se indican '
          'cuidados de la cicatriz y protección solar.',
      treatmentDescription:
          'Cierre por segunda intención sin datos de infección: curación en '
          'ambiente húmedo y protección de la piel perilesional hasta el cierre.',
      treatmentComponents: [
        ['Limpieza de la herida', 'Solución salina 0.9%'],
        ['Apósito primario', 'Hidrocoloide'],
      ],
    );

    // 7. LPP sacra domiciliaria — MEJORANDO, con EVIDENCIA FOTOGRÁFICA real.
    // 5 visitas (basal → 4 seguimientos) con área decreciente y composición del
    // lecho mejorando, para lucir el antes/después, el % de reducción y la
    // galería en el reporte y el detalle.
    {
      final pid = _uuid.v4();
      final wid = _uuid.v4();
      final folio = 'EXP2026-${expSeq.toString().padLeft(4, '0')}';
      expSeq++;
      final dates =
          [28, 21, 14, 7, 0].map((d) => now.subtract(Duration(days: d))).toList();
      final areas = [24.0, 18.0, 12.0, 7.0, 3.5];
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
      await appendRows(Collections.consents, [
        for (final type in ['privacidad', 'fotografia', 'desbridamiento'])
          {
            'id': _uuid.v4(),
            'patient_id': pid,
            'type': type,
            'granted': true,
            'granted_at': iso(dates.first),
            'signed_by': 'Marta Salinas (hija)',
            'doc_ref': null,
            'created_at': iso(dates.first),
          }
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
      const followUpProc = [
        '',
        'Limpieza con solución salina 0.9%, desbridamiento cortante de esfacelo y colocación de apósito de espuma.',
        'Limpieza, desbridamiento cortante parcial de esfacelo residual y apósito de espuma con plata.',
        'Limpieza, retiro de esfacelo mínimo y colocación de apósito de hidrocoloide.',
        'Limpieza suave y apósito de hidrocoloide fino; protección de piel perilesional con crema barrera.',
      ];
      const followUpMat = [
        '',
        'Solución salina 0.9%, gasas estériles, apósito de espuma (foam), película protectora.',
        'Solución salina 0.9%, apósito de espuma con plata, gasas estériles.',
        'Solución salina 0.9%, apósito de hidrocoloide, crema barrera de óxido de zinc.',
        'Solución salina 0.9%, apósito de hidrocoloide fino, crema barrera.',
      ];
      const followUpEvo = [
        '',
        'Favorable. Lecho de 18.0 cm²; disminución de esfacelo y aparición de tejido de granulación.',
        'Favorable. Lecho de 12.0 cm², predominio de granulación (~65%), exudado moderado en descenso.',
        'Favorable. Lecho de 7.0 cm², granulación >75% e inicio de epitelización en bordes.',
        'Muy favorable. Lecho de 3.5 cm², epitelización activa desde los bordes; sin signos de infección.',
      ];
      final consults = <Map<String, dynamic>>[];
      final measures = <Map<String, dynamic>>[];
      final photos = <Map<String, dynamic>>[];
      for (var i = 0; i < 5; i++) {
        final type = i == 0 ? 'valoracion' : 'seguimiento';
        final row =
            consulta(consultIds[i], pid, staff1Id, siteDomicilioCdmx, type, dates[i]);
        if (type == 'seguimiento') {
          row.addAll({
            'follow_up_care_type': 'Curación avanzada en domicilio',
            'follow_up_procedure_desc': followUpProc[i],
            'follow_up_materials_used': followUpMat[i],
            'follow_up_evolution': followUpEvo[i],
            'follow_up_signed_by': 'Lic. J. Carlos Alejandre',
            'follow_up_signed_license': '10456789',
          });
        }
        consults.add(row);
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
      final ricTpId = _uuid.v4();
      await appendRows(Collections.treatmentPlans, [
        {
          'id': ricTpId,
          'consultation_id': consultIds.last,
          'wound_id': wid,
          'used_kura_protocol': false,
          'final_description':
              'Curación avanzada en ambiente húmedo. Alivio de presión con '
              'cambios posturales cada 2 h y superficie de redistribución. '
              'Optimización nutricional con aporte proteico. Revisión cada 7 días.',
        }
      ]);
      await appendRows(Collections.treatmentComponents, [
        {
          'id': _uuid.v4(),
          'treatment_plan_id': ricTpId,
          'method': 'Limpieza de la herida',
          'product': 'Solución salina 0.9%',
          'origin': 'manual',
          'sort_order': 0,
        },
        {
          'id': _uuid.v4(),
          'treatment_plan_id': ricTpId,
          'method': 'Desbridamiento',
          'product': 'Cortante selectivo de esfacelo',
          'origin': 'manual',
          'sort_order': 1,
        },
        {
          'id': _uuid.v4(),
          'treatment_plan_id': ricTpId,
          'method': 'Apósito primario',
          'product': 'Hidrocoloide / espuma según nivel de exudado',
          'origin': 'manual',
          'sort_order': 2,
        },
        {
          'id': _uuid.v4(),
          'treatment_plan_id': ricTpId,
          'method': 'Manejo de la presión',
          'product': 'Cambios posturales c/2 h + cojín de redistribución',
          'origin': 'manual',
          'sort_order': 3,
        },
      ]);
      await appendRows(Collections.staffPatientAssignments, [
        {'id': _uuid.v4(), 'staff_id': staff1Id, 'patient_id': pid},
      ]);
    }

    // ================================================================
    // ESCENARIO 2 — HOSPITAL (azul): 5 pacientes.
    // Prevención centrada en el paciente: internamiento + Braden (4 bandas) +
    // rondas (tareas SIN dueño, assignee_kind 'staff'; las marca quien está de
    // turno vía done_by). Alimenta el tablero de riesgo y el dashboard del centro.
    // ================================================================
    var hospSeq = 1;

    /// Crea un paciente hospitalizado con internamiento, Braden y tareas de ronda.
    /// [tasks] = lista de {title, actionLabel, ruleId, actionId, hours, status},
    /// donde `hours` es el desfase (en horas) del horario respecto a ahora
    /// (negativo = pasado) y `status` ∈ {pending, done, skipped}.
    Future<void> addHospitalPatient({
      required String name,
      required DateTime birth,
      required String sex,
      required int braden,
      required String bradenNotes,
      required String floor,
      required String area,
      required String bed,
      required List<Map<String, dynamic>> tasks,
      int admittedDaysAgo = 3,
      bool fragile = true,
      // Subescalas de Braden (percepción, humedad, actividad, movilidad,
      // nutrición, fricción). Humedad ≤2 activa la aplicabilidad de GLOBIAD.
      Map<String, int>? bradenSubscores,
    }) async {
      final pid = _uuid.v4();
      final folio = 'HOSP-${hospSeq.toString().padLeft(4, '0')}';
      hospSeq++;
      await appendRows(Collections.patients, [
        {
          'id': pid,
          'organization_id': organizationIdHospital,
          'folio': folio,
          'full_name': name,
          'birth_date': isoDate(birth),
          'sex': sex,
          'mobility': fragile ? 'encamado' : 'ambulatorio',
          'has_identified_caregiver': false,
          'fragile_patient': fragile,
          'background_notes':
              'Paciente hospitalizado. Prevención de LPP centrada en el paciente '
              '(turnos).',
          'is_active': true,
          'created_at': iso(now.subtract(Duration(days: admittedDaysAgo))),
        }
      ]);
      await appendRows(Collections.patientAdmissions, [
        {
          'id': _uuid.v4(),
          'organization_id': organizationIdHospital,
          'patient_id': pid,
          'floor': floor,
          'area': area,
          'bed': bed,
          'admitted_at': iso(now.subtract(Duration(days: admittedDaysAgo))),
          'discharged_at': null,
          'status': 'activo',
          'notes': null,
          'created_at': iso(now.subtract(Duration(days: admittedDaysAgo))),
        }
      ]);
      await appendRows(Collections.riskAssessments, [
        {
          'id': _uuid.v4(),
          'organization_id': organizationIdHospital,
          'patient_id': pid,
          'braden_score': braden,
          'braden_subscores': bradenSubscores,
          'assessed_at': iso(now.subtract(const Duration(days: 1))),
          'assessed_by': enfermeriaProfileId,
          'notes': bradenNotes,
          'created_at': iso(now.subtract(const Duration(days: 1))),
        }
      ]);
      await appendRows(Collections.preventiveTasks, [
        for (final t in tasks)
          {
            'id': _uuid.v4(),
            'organization_id': organizationIdHospital,
            'patient_id': pid,
            'rule_id': t['ruleId'],
            'action_id': t['actionId'],
            'title': t['title'],
            'action_label': t['actionLabel'],
            'scheduled_at': iso(now.add(Duration(hours: t['hours'] as int))),
            'assignee_profile_id': null,
            'assignee_kind': 'staff',
            'status': t['status'],
            if (t['status'] == 'done') 'done_at': iso(now.add(Duration(hours: t['hours'] as int))),
            if (t['status'] == 'done') 'done_by': enfermeriaProfileId,
            'source': 'auto',
            'created_at': iso(now.subtract(const Duration(hours: 12))),
          }
      ]);
    }

    // Tareas típicas de ronda (LPP): plantillas reutilizables.
    Map<String, dynamic> rondaTask(
            String title, String label, int hours, String status,
            {String rule = 'lpp_alto', String action = 'cambios_2h_registro'}) =>
        {
          'title': title,
          'actionLabel': label,
          'ruleId': rule,
          'actionId': action,
          'hours': hours,
          'status': status,
        };

    // Banda MUY ALTO (rojo): encamada, cambios cada 2 h. Una vencida sin marcar.
    await addHospitalPatient(
      name: 'Guadalupe Torres Ibarra',
      birth: DateTime(1943, 7, 5),
      sex: 'F',
      braden: 9,
      bradenNotes: 'Adulto mayor encamado, incontinencia; riesgo muy alto.',
      // Humedad 1 (piel constantemente húmeda por incontinencia) → activa GLOBIAD.
      bradenSubscores: const {
        'percepcion_sensorial': 1,
        'humedad': 1,
        'actividad': 1,
        'movilidad': 1,
        'nutricion': 2,
        'friccion_cizallamiento': 3,
      },
      floor: '3',
      area: 'Medicina Interna',
      bed: '08',
      tasks: [
        rondaTask('Cambio postural', 'Cambios posturales cada 2 h', -3, 'done'),
        rondaTask('Cambio postural', 'Cambios posturales cada 2 h', -1, 'pending'),
        rondaTask('Examen de piel', 'Examen diario de la piel', 2, 'pending',
            action: 'exam_piel_diario'),
        rondaTask('Aplicar AGHO', 'AGHO en zonas de riesgo', 5, 'pending',
            action: 'agho'),
      ],
    );

    // Banda ALTO (ámbar): frágil, cumplimiento parcial.
    await addHospitalPatient(
      name: 'Antonio Ríos Peña',
      birth: DateTime(1940, 1, 9),
      sex: 'M',
      braden: 11,
      bradenNotes: 'Movilidad muy reducida; LPP incipiente en talón derecho.',
      floor: '2',
      area: 'Cirugía',
      bed: '04',
      tasks: [
        rondaTask('Cambio postural', 'Cambios posturales cada 2 h', -2, 'done'),
        rondaTask('Cambio postural', 'Cambios posturales cada 2 h', 1, 'pending'),
        rondaTask('Protección de talones', 'Taloneras de descarga', 4, 'pending',
            action: 'taloneras'),
      ],
    );

    // Banda MEDIO: vigilancia, buen cumplimiento.
    await addHospitalPatient(
      name: 'Héctor Navarro Luna',
      birth: DateTime(1955, 10, 2),
      sex: 'M',
      braden: 15,
      bradenNotes: 'Riesgo medio; deambula con apoyo.',
      floor: '3',
      area: 'Medicina Interna',
      bed: '12',
      fragile: false,
      tasks: [
        rondaTask('Examen de piel', 'Examen diario de la piel', -4, 'done',
            action: 'exam_piel_diario'),
        rondaTask('Movilización', 'Fomentar movilización asistida', 3, 'pending',
            rule: 'lpp_medio', action: 'movilizacion'),
      ],
    );

    // Banda BAJO (verde): control.
    await addHospitalPatient(
      name: 'José Luis Ramírez Ochoa',
      birth: DateTime(1958, 5, 14),
      sex: 'M',
      braden: 19,
      bradenNotes: 'Riesgo bajo; autónomo, sin datos de LPP.',
      floor: '4',
      area: 'Geriatría',
      bed: '02',
      fragile: false,
      tasks: [
        rondaTask('Examen de piel', 'Examen diario de la piel', -2, 'done',
            rule: 'lpp_bajo', action: 'exam_piel_diario'),
      ],
    );

    // Banda MUY ALTO (rojo) #2: postquirúrgica encamada, tarea vencida.
    await addHospitalPatient(
      name: 'María Elena Vega Ortiz',
      birth: DateTime(1946, 12, 1),
      sex: 'F',
      braden: 8,
      bradenNotes: 'Postoperatorio, encamada; riesgo muy alto de LPP.',
      // Humedad 2 (piel muy húmeda) → activa GLOBIAD.
      bradenSubscores: const {
        'percepcion_sensorial': 1,
        'humedad': 2,
        'actividad': 1,
        'movilidad': 1,
        'nutricion': 2,
        'friccion_cizallamiento': 1,
      },
      floor: '2',
      area: 'Cirugía',
      bed: '09',
      admittedDaysAgo: 2,
      tasks: [
        rondaTask('Cambio postural', 'Cambios posturales cada 2 h', -5, 'done'),
        rondaTask('Cambio postural', 'Cambios posturales cada 2 h', -1, 'pending'),
        rondaTask('Superficie de redistribución', 'Colchón de redistribución de presión',
            3, 'pending', action: 'superficie'),
      ],
    );

    // ================================================================
    // ESCENARIO 3 — CUIDADORES (rosa): 3 pacientes a domicilio.
    // El cuidador demo (login por teléfono) monitorea a sus pacientes asignados:
    // tareas con estados variados (hecha / vencida / futura) e indicaciones del
    // centro. Cada paciente muestra el estado de su herida en la vista del cuidador.
    // ================================================================
    var cuiSeq = 1;

    /// Crea un paciente a domicilio del centro de cuidadores, lo asigna al
    /// cuidador demo, y le agrega herida + medición (estado visible en la app del
    /// cuidador), tareas y las indicaciones del centro.
    Future<void> addCaregiverPatient({
      required String name,
      required DateTime birth,
      required String sex,
      required String background,
      required String etiology,
      required String subtype,
      required String location,
      required List<double> areas, // serie basal → actual (evolución en la app del cuidador)
      required List<List<int>> comps, // [gran, slough, necr, epi] por medición
      required String instructions,
      required List<Map<String, dynamic>> tasks,
      Map<String, dynamic> woundExtra = const {},
    }) async {
      final pid = _uuid.v4();
      final wid = _uuid.v4();
      final folio = 'CUI-${cuiSeq.toString().padLeft(4, '0')}';
      cuiSeq++;
      await appendRows(Collections.patients, [
        {
          'id': pid,
          'organization_id': organizationIdCuidadores,
          'folio': folio,
          'full_name': name,
          'birth_date': isoDate(birth),
          'sex': sex,
          'mobility': 'encamado',
          'has_identified_caregiver': true,
          'caregiver_name': 'Cuidador Demo',
          'caregiver_phone': '5512345678',
          'fragile_patient': true,
          'background_notes': background,
          'is_active': true,
          'created_at': iso(now.subtract(const Duration(days: 20))),
        }
      ]);
      await appendRows(Collections.caregiverPatientAssignments, [
        {
          'id': _uuid.v4(),
          'organization_id': organizationIdCuidadores,
          'caregiver_profile_id': cuidadorProfileId,
          'patient_id': pid,
          'assigned_by': adminProfileId,
          'created_at': iso(now.subtract(const Duration(days: 20))),
        }
      ]);
      await appendRows(Collections.wounds, [
        {
          'id': wid,
          'patient_id': pid,
          'etiology': etiology,
          'subtype': subtype,
          'body_location_primary': location,
          'body_location_secondary': null,
          'onset_date': isoDate(now.subtract(const Duration(days: 30))),
          'wagner_grade': woundExtra['wagner_grade'],
          'ceap_class': woundExtra['ceap_class'],
          'wuwhs_grade': woundExtra['wuwhs_grade'],
          'agente_causal': woundExtra['agente_causal'],
          'is_active': true,
          'closed_at': null,
          'created_at': iso(now.subtract(const Duration(days: 20))),
        }
      ]);
      // Mediciones seriadas sin consulta (consultation_id nullable): alimentan
      // la vista de evolución de la herida en la app del cuidador. Se reparten
      // en las últimas ~3 semanas (basal → actual).
      final cuiN = areas.length;
      final cuiDates = List<DateTime>.generate(
          cuiN,
          (i) => now.subtract(
              Duration(days: (21 * (cuiN - 1 - i) / (cuiN - 1)).round())));
      await appendRows(Collections.woundMeasurements, [
        for (var i = 0; i < cuiN; i++)
          meas(wid, null, cuiDates[i], areas[i], comps[i][0], comps[i][1],
              comps[i][2], comps[i][3], 0.5),
      ]);
      await appendRows(Collections.caregiverInstructions, [
        {
          'id': _uuid.v4(),
          'organization_id': organizationIdCuidadores,
          'patient_id': pid,
          'instructions': instructions,
          'updated_by': adminProfileId,
          'updated_at': iso(now.subtract(const Duration(days: 5))),
        }
      ]);
      await appendRows(Collections.preventiveTasks, [
        for (final t in tasks)
          {
            'id': _uuid.v4(),
            'organization_id': organizationIdCuidadores,
            'patient_id': pid,
            'rule_id': t['ruleId'] ?? 'lpp_alto',
            'action_id': t['actionId'] ?? 'cambios_2h_registro',
            'title': t['title'],
            'action_label': t['actionLabel'],
            'scheduled_at': iso(now.add(Duration(hours: t['hours'] as int))),
            'assignee_profile_id': cuidadorProfileId,
            'assignee_kind': 'cuidador',
            'status': t['status'],
            if (t['status'] == 'done')
              'done_at': iso(now.add(Duration(hours: t['hours'] as int))),
            if (t['status'] == 'done') 'done_by': cuidadorProfileId,
            'source': 'auto',
            'created_at': iso(now.subtract(const Duration(hours: 12))),
          }
      ]);
    }

    await addCaregiverPatient(
      name: 'Esperanza Ruiz Molina',
      birth: DateTime(1942, 2, 11),
      sex: 'F',
      background: 'Encamada por secuelas de EVC. LPP sacra en manejo domiciliario.',
      etiology: 'lpp',
      subtype: 'Lesión por presión sacra',
      location: 'sacro',
      woundExtra: {'wuwhs_grade': 'g2'},
      areas: [6.0, 4.6, 3.4],
      comps: [
        [55, 25, 5, 15],
        [62, 16, 2, 20],
        [70, 8, 0, 22],
      ],
      instructions:
          'Cambios de posición cada 2 h (registrar hora). Mantener la piel seca y '
          'limpia; aplicar crema barrera tras cada cambio de pañal. Avisar a la '
          'clínica si aparece enrojecimiento que no cede, mal olor o fiebre.',
      tasks: [
        {
          'title': 'Cambio postural',
          'actionLabel': 'Cambios posturales cada 2 h con registro horario',
          'hours': -4,
          'status': 'done',
        },
        {
          'title': 'Cambio postural',
          'actionLabel': 'Cambios posturales cada 2 h con registro horario',
          'hours': -1,
          'status': 'pending',
        },
        {
          'title': 'Aplicar AGHO',
          'actionLabel': 'Ácidos grasos hiperoxigenados en zonas de riesgo',
          'actionId': 'agho',
          'hours': 2,
          'status': 'pending',
        },
        {
          'title': 'Examen de piel',
          'actionLabel': 'Examen diario de la piel en prominencias',
          'actionId': 'exam_piel_diario',
          'hours': 4,
          'status': 'pending',
        },
      ],
    );

    await addCaregiverPatient(
      name: 'Alberto Mendoza Cruz',
      birth: DateTime(1949, 9, 18),
      sex: 'M',
      background: 'Movilidad reducida por artrosis avanzada. LPP en talón.',
      etiology: 'lpp',
      subtype: 'Lesión por presión en talón',
      location: 'talon_derecho',
      woundExtra: {'wuwhs_grade': 'g2'},
      areas: [4.0, 3.7, 3.4],
      comps: [
        [60, 20, 0, 20],
        [62, 17, 0, 21],
        [64, 14, 0, 22],
      ],
      instructions:
          'Usar taloneras de descarga en todo momento. Movilizar las piernas y '
          'revisar los talones 2 veces al día. Hidratar la piel; no masajear sobre '
          'prominencias óseas.',
      tasks: [
        {
          'title': 'Protección de talones',
          'actionLabel': 'Colocar taloneras de descarga',
          'actionId': 'taloneras',
          'hours': -3,
          'status': 'done',
        },
        {
          'title': 'Examen de piel',
          'actionLabel': 'Revisión de talones 2 veces al día',
          'actionId': 'exam_piel_diario',
          'hours': 3,
          'status': 'pending',
        },
      ],
    );

    await addCaregiverPatient(
      name: 'Refugio Santos Díaz',
      birth: DateTime(1946, 4, 30),
      sex: 'F',
      background: 'Insuficiencia venosa crónica; úlcera venosa en manejo a domicilio.',
      etiology: 'vascular',
      subtype: 'Úlcera venosa',
      location: 'pierna_izquierda_tercio_distal',
      woundExtra: {'ceap_class': 'c6'},
      areas: [5.0, 4.0, 3.0],
      comps: [
        [65, 15, 0, 20],
        [70, 10, 0, 20],
        [75, 5, 0, 20],
      ],
      instructions:
          'Mantener el vendaje de compresión limpio y seco; no retirarlo salvo '
          'indicación. Elevar la pierna varias veces al día. Avisar si el vendaje '
          'aprieta demasiado, cambian el color de los dedos o hay dolor intenso.',
      tasks: [
        {
          'title': 'Terapia compresiva',
          'actionLabel': 'Verificar el vendaje de compresión',
          'actionId': 'compresion',
          'ruleId': 'venosa',
          'hours': -2,
          'status': 'done',
        },
        {
          'title': 'Elevación de la extremidad',
          'actionLabel': 'Elevar la pierna 20-30 min, varias veces al día',
          'actionId': 'elevacion',
          'ruleId': 'venosa',
          'hours': 1,
          'status': 'pending',
        },
        {
          'title': 'Examen de piel',
          'actionLabel': 'Vigilar la piel perilesional y los dedos',
          'actionId': 'exam_piel_diario',
          'hours': 6,
          'status': 'pending',
        },
      ],
    );

    // ---------------- Agenda de la clínica (citas manuales) ----------------
    // Kura+ opera su agenda en modo MANUAL en la demo. Se puebla con citas de
    // seguimiento para los pacientes dados de alta en la clínica, repartidas por
    // la semana (con un par ya realizadas para dar historial). Se asignan a los
    // dos Kuradores (Dra. Ana Martínez / Lic. Carlos Ramírez) por turnos.
    final clinicaPatients = store
        .getAll(Collections.patients)
        .where((p) =>
            p['organization_id'] == organizationId && p['is_active'] == true)
        .toList();
    final kuradorIds = [staff1Id, staff2Id];
    const citaTitulos = [
      'Curación y valoración',
      'Seguimiento de herida',
      'Control de evolución',
      'Revisión de tratamiento',
    ];
    // Franjas [díaRelativoAHoy, hora] para repartir las citas sin encimarlas.
    const franjas = [
      [-4, 10], [-1, 12], // ya realizadas (historial)
      [0, 9], [0, 11], [0, 16], // hoy
      [1, 10], [1, 15], // mañana
      [2, 12], [3, 9], [4, 16], [6, 11], [7, 13], // resto de la semana
    ];
    final citasClinica = <Map<String, dynamic>>[];
    for (var i = 0; i < franjas.length && clinicaPatients.isNotEmpty; i++) {
      final p = clinicaPatients[i % clinicaPatients.length];
      final f = franjas[i];
      final when =
          DateTime(now.year, now.month, now.day + f[0], f[1], 0);
      final past = when.isBefore(now);
      citasClinica.add({
        'id': _uuid.v4(),
        'organization_id': organizationId,
        'staff_id': kuradorIds[i % kuradorIds.length],
        'patient_id': p['id'],
        'title': citaTitulos[i % citaTitulos.length],
        'datetime': iso(when),
        'end_time': iso(when.add(const Duration(minutes: 40))),
        'notes': null,
        'status': past ? 'completed' : 'scheduled',
        'created_at': iso(now.subtract(const Duration(days: 3))),
      });
    }
    await appendRows(Collections.manualAppointments, citasClinica);

    // ---------------- Inventario demo (Insumos Fase 3) ----------------
    // Existencias en el sitio Kura+ CDMX: unos productos EXTERNOS con stock
    // inicial y un artículo bajo de existencia (para mostrar "Reordenar").
    final invSeed = [
      ('Gasa estéril 10x10 (caja 100)', 'Proveedor local', 85.0, 12, 40),
      ('Cinta micropore 2.5cm', 'Farmacia mayorista', 28.0, 30, 60),
      ('Guantes de nitrilo (caja 100)', 'Proveedor local', 210.0, 8, 25),
      ('Suero fisiológico 500 ml', 'Distribuidora médica', 35.0, 20, 3),
    ];
    final invItems = <Map<String, dynamic>>[];
    final invMoves = <Map<String, dynamic>>[];
    for (final row in invSeed) {
      final itemId = _uuid.v4();
      invItems.add({
        'id': itemId,
        'organization_id': organizationId,
        'site_id': siteClinicaCdmx,
        'name': row.$1,
        'is_external': true,
        'shopify_product_id': null,
        'shopify_variant_id': null,
        'image_url': null,
        'unit_cost': row.$3,
        'unit_price': double.parse((row.$3 * 1.3).toStringAsFixed(2)),
        'currency': 'MXN',
        'supplier': row.$2,
        'reorder_threshold': row.$4,
        'notes': null,
        'is_active': true,
        'created_by': staff1Id,
        'created_at': iso(now.subtract(const Duration(days: 20))),
        'updated_at': iso(now.subtract(const Duration(days: 20))),
      });
      invMoves.add({
        'id': _uuid.v4(),
        'organization_id': organizationId,
        'site_id': siteClinicaCdmx,
        'inventory_item_id': itemId,
        'delta': row.$5,
        'reason': 'compra',
        'unit_cost': row.$3,
        'patient_id': null,
        'consultation_id': null,
        'note': 'Existencia inicial (demo)',
        'created_by': staff1Id,
        'created_at': iso(now.subtract(const Duration(days: 20))),
      });
    }
    // Un artículo de la TIENDA Kura+ bajo umbral, para demostrar el reabasto con
    // carrito de Shopify (usa una variante real de la tienda kuramas).
    final storeItemId = _uuid.v4();
    invItems.add({
      'id': storeItemId,
      'organization_id': organizationId,
      'site_id': siteClinicaCdmx,
      'name': 'Prontosan® Solución 350 ml',
      'is_external': false,
      'shopify_product_id': 'gid://shopify/Product/demo-prontosan-350',
      'shopify_variant_id': 'gid://shopify/ProductVariant/31712507002942',
      'image_url':
          'https://cdn.shopify.com/s/files/1/0260/4128/6718/files/Prontosan.png?v=1739829824',
      'unit_cost': 863.0,
      'unit_price': 1121.90,
      'currency': 'MXN',
      'supplier': null,
      'reorder_threshold': 6,
      'notes': null,
      'is_active': true,
      'created_by': staff1Id,
      'created_at': iso(now.subtract(const Duration(days: 20))),
      'updated_at': iso(now.subtract(const Duration(days: 20))),
    });
    invMoves.add({
      'id': _uuid.v4(),
      'organization_id': organizationId,
      'site_id': siteClinicaCdmx,
      'inventory_item_id': storeItemId,
      'delta': 2, // 2 en stock < umbral 6 → aparece en reabasto
      'reason': 'compra',
      'unit_cost': 863.0,
      'patient_id': null,
      'consultation_id': null,
      'note': 'Existencia inicial (demo)',
      'created_by': staff1Id,
      'created_at': iso(now.subtract(const Duration(days: 20))),
    });
    await appendRows(Collections.inventoryItems, invItems);
    await appendRows(Collections.inventoryMovements, invMoves);

    // ---------------- Catálogo de servicios demo (módulo comercial) ----------
    await appendRows(Collections.serviceCatalog, [
      for (final s in const [
        ('Valoración inicial', 800.0),
        ('Consulta de seguimiento', 500.0),
        ('Curación avanzada', 650.0),
      ])
        {
          'id': _uuid.v4(),
          'organization_id': organizationId,
          'name': s.$1,
          'price': s.$2,
          'currency': 'MXN',
          'is_active': true,
          'created_by': staff1Id,
          'created_at': iso(now.subtract(const Duration(days: 20))),
          'updated_at': iso(now.subtract(const Duration(days: 20))),
        },
    ]);

    // ---------------- Datos demo para los dashboards ----------------
    // Consumo (salidas) y cobros de ejemplo, repartidos por mes, para que las
    // gráficas del dashboard de Insumos y Comercial no salgan vacías.
    final demoPatients = store
        .getAll(Collections.patients)
        .where((p) => p['organization_id'] == organizationId && p['is_active'] == true)
        .toList();
    final demoInvItems = store
        .getAll(Collections.inventoryItems)
        .where((it) => it['site_id'] == siteClinicaCdmx)
        .toList();
    if (demoPatients.isNotEmpty && demoInvItems.isNotEmpty) {
      final consumoRows = <Map<String, dynamic>>[];
      // 2 artículos × 3 meses de consumo.
      for (var mi = 0; mi < 3; mi++) {
        final when = DateTime(now.year, now.month - mi, 14);
        for (var k = 0; k < 2 && k < demoInvItems.length; k++) {
          final it = demoInvItems[k];
          final p = demoPatients[(mi + k) % demoPatients.length];
          consumoRows.add({
            'id': _uuid.v4(),
            'organization_id': organizationId,
            'site_id': siteClinicaCdmx,
            'inventory_item_id': it['id'],
            'delta': -(2 + k),
            'reason': 'consumo',
            'unit_cost': it['unit_cost'],
            'patient_id': p['id'],
            'consultation_id': null,
            'note': 'Consumo (demo)',
            'created_by': staff1Id,
            'created_at': iso(when),
          });
        }
      }
      await appendRows(Collections.inventoryMovements, consumoRows);

      // Cobros: 2 pagados (meses distintos, métodos distintos) + 1 pendiente.
      final chargeSeed = [
        (0, 'pagado', 'efectivo', 800.0, 'Valoración inicial'),
        (1, 'pagado', 'transferencia', 500.0, 'Consulta de seguimiento'),
        (0, 'pendiente', null, 650.0, 'Curación avanzada'),
      ];
      final chargeRows = <Map<String, dynamic>>[];
      final chargeItemRows = <Map<String, dynamic>>[];
      for (var ci = 0; ci < chargeSeed.length; ci++) {
        final s = chargeSeed[ci];
        final when = DateTime(now.year, now.month - s.$1, 10);
        final p = demoPatients[ci % demoPatients.length];
        final chargeId = _uuid.v4();
        chargeRows.add({
          'id': chargeId,
          'organization_id': organizationId,
          'patient_id': p['id'],
          'consultation_id': null,
          'site_id': siteClinicaCdmx,
          'subtotal_service': s.$4,
          'subtotal_supplies': 0.0,
          'total': s.$4,
          'currency': 'MXN',
          'status': s.$2,
          'payment_method': s.$3,
          'paid_at': s.$2 == 'pagado' ? iso(when) : null,
          'created_by': staff1Id,
          'created_at': iso(when),
          'updated_at': iso(when),
        });
        chargeItemRows.add({
          'id': _uuid.v4(),
          'charge_id': chargeId,
          'organization_id': organizationId,
          'kind': 'servicio',
          'name': s.$5,
          'quantity': 1,
          'unit_price': s.$4,
          'line_total': s.$4,
          'created_at': iso(when),
        });
      }
      await appendRows(Collections.charges, chargeRows);
      await appendRows(Collections.chargeItems, chargeItemRows);

      // Pagos de terminal (Mercado Pago Point) para la BANDEJA de conciliación:
      // uno que calza con el cobro pendiente ($650) por folio del paciente, y
      // otro suelto (sin referencia) que hay que ligar a mano.
      final pendingPatient = demoPatients[2 % demoPatients.length];
      await appendRows(Collections.pointPayments, [
        {
          'id': _uuid.v4(),
          'organization_id': organizationId,
          'amount': 650.0,
          'currency': 'MXN',
          'status': 'approved',
          'method': 'credit_card',
          'external_reference': pendingPatient['folio'],
          'device_id': 'POINT-SMART-DEMO',
          'description': 'Pago en terminal Point',
          'captured_at': iso(now.subtract(const Duration(hours: 2))),
          'source': 'webhook',
          'created_at': iso(now.subtract(const Duration(hours: 2))),
          'updated_at': iso(now.subtract(const Duration(hours: 2))),
        },
        {
          'id': _uuid.v4(),
          'organization_id': organizationId,
          'amount': 1200.0,
          'currency': 'MXN',
          'status': 'approved',
          'method': 'debit_card',
          'external_reference': null,
          'device_id': 'POINT-SMART-DEMO',
          'description': 'Pago en terminal Point (sin referencia)',
          'captured_at': iso(now.subtract(const Duration(hours: 5))),
          'source': 'webhook',
          'created_at': iso(now.subtract(const Duration(hours: 5))),
          'updated_at': iso(now.subtract(const Duration(hours: 5))),
        },
      ]);
    }
  }
}
