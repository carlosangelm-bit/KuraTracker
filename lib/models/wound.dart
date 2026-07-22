import '../engine/models/kura_engine_enums.dart';

/// Busca un valor de enum por su `name` (o null). Usado para las
/// clasificaciones por etiología persistidas como texto (Prompt 5 / 0028).
T? enumByName<T extends Enum>(List<T> values, Object? name) {
  if (name == null) return null;
  for (final v in values) {
    if (v.name == name) return v;
  }
  return null;
}

extension EtiologiaDb on Etiologia {
  String get dbValue {
    switch (this) {
      case Etiologia.lpp:
        return 'lpp';
      case Etiologia.vascular:
        return 'vascular';
      case Etiologia.quirurgica:
        return 'quirurgica';
      case Etiologia.traumatica:
        return 'traumatica';
      case Etiologia.pieDiabetico:
        return 'pie_diabetico';
      case Etiologia.otra:
        return 'otra';
    }
  }

  static Etiologia fromDb(String s) {
    switch (s) {
      case 'lpp':
        return Etiologia.lpp;
      case 'vascular':
        return Etiologia.vascular;
      case 'quirurgica':
        return Etiologia.quirurgica;
      case 'traumatica':
        return Etiologia.traumatica;
      case 'pie_diabetico':
        return Etiologia.pieDiabetico;
      default:
        return Etiologia.otra;
    }
  }
}

class Wound {
  final String id;
  final String patientId;
  final Etiologia etiology;
  final String? subtype;
  final String bodyLocationPrimary;
  final String? bodyLocationSecondary;
  final DateTime? onsetDate;
  final WagnerGrade? wagnerGrade;
  // WIfI (Wound/Ischemia/foot Infection): 3 subescalas independientes 0-3,
  // capturadas junto a Wagner en pie diabetico.
  final int? wifiWound;
  final int? wifiIschemia;
  final int? wifiInfection;
  final CeapClass? ceapClass;
  final WuwhsGrade? wuwhsGrade;
  final AgenteCausal? agenteCausal;
  // ---- Clasificaciones/campos por etiología (Prompt 5, migración 0028) ----
  // UPD (pie diabético)
  final UpdSubtipo? updSubtipo;
  final TexasGrade? texasGrade;
  final TexasStage? texasStage;
  final IdsaIwgdf? idsaIwgdf;
  final SensibilidadProtectora? sensibilidadProtectora;
  // Vascular arterial (sobre subtipo arterial del Prompt 1)
  final Rutherford? rutherford;
  // LPP (reemplaza el texto libre de estadio)
  final NpuapEstadio? npuapEstadio;
  // Quirúrgica
  final ClaseContaminacion? claseContaminacion;
  final TipoCierre? tipoCierre;
  final DrenajeTipo? drenajeTipo;
  final SuturaTipo? suturaTipo;
  // Nº de drenajes y de puntos/grapas sobre la herida quirúrgica (0038).
  final int? drenajeNum;
  final int? suturaNum;
  // Egreso del episodio (estructurado)
  final MotivoEgreso? motivoEgreso;
  final bool isActive;
  final DateTime? closedAt;
  final DateTime createdAt;

  const Wound({
    required this.id,
    required this.patientId,
    required this.etiology,
    this.subtype,
    required this.bodyLocationPrimary,
    this.bodyLocationSecondary,
    this.onsetDate,
    this.wagnerGrade,
    this.wifiWound,
    this.wifiIschemia,
    this.wifiInfection,
    this.ceapClass,
    this.wuwhsGrade,
    this.agenteCausal,
    this.updSubtipo,
    this.texasGrade,
    this.texasStage,
    this.idsaIwgdf,
    this.sensibilidadProtectora,
    this.rutherford,
    this.npuapEstadio,
    this.claseContaminacion,
    this.tipoCierre,
    this.drenajeTipo,
    this.suturaTipo,
    this.drenajeNum,
    this.suturaNum,
    this.motivoEgreso,
    this.isActive = true,
    this.closedAt,
    required this.createdAt,
  });

  factory Wound.fromJson(Map<String, dynamic> json) => Wound(
        id: json['id'] as String,
        patientId: json['patient_id'] as String,
        etiology: EtiologiaDb.fromDb(json['etiology'] as String),
        subtype: json['subtype'] as String?,
        bodyLocationPrimary: json['body_location_primary'] as String,
        bodyLocationSecondary: json['body_location_secondary'] as String?,
        onsetDate: json['onset_date'] == null
            ? null
            : DateTime.parse(json['onset_date'] as String),
        wagnerGrade: json['wagner_grade'] == null
            ? null
            : WagnerGrade.values.firstWhere((e) => e.name == json['wagner_grade']),
        wifiWound: json['wifi_wound'] as int?,
        wifiIschemia: json['wifi_ischemia'] as int?,
        wifiInfection: json['wifi_infection'] as int?,
        ceapClass: json['ceap_class'] == null
            ? null
            : CeapClass.values.firstWhere((e) => e.name == json['ceap_class']),
        wuwhsGrade: json['wuwhs_grade'] == null
            ? null
            : WuwhsGrade.values.firstWhere((e) => e.name == json['wuwhs_grade']),
        agenteCausal: json['agente_causal'] == null
            ? null
            : AgenteCausal.values.firstWhere((e) => e.name == json['agente_causal']),
        updSubtipo: enumByName(UpdSubtipo.values, json['upd_subtipo']),
        texasGrade: enumByName(TexasGrade.values, json['texas_grade']),
        texasStage: enumByName(TexasStage.values, json['texas_stage']),
        idsaIwgdf: enumByName(IdsaIwgdf.values, json['idsa_iwgdf']),
        sensibilidadProtectora: enumByName(
            SensibilidadProtectora.values, json['sensibilidad_protectora']),
        rutherford: enumByName(Rutherford.values, json['rutherford']),
        npuapEstadio: enumByName(NpuapEstadio.values, json['npuap_estadio']),
        claseContaminacion: enumByName(
            ClaseContaminacion.values, json['clase_contaminacion']),
        tipoCierre: enumByName(TipoCierre.values, json['tipo_cierre']),
        drenajeTipo: enumByName(DrenajeTipo.values, json['drenaje_tipo']),
        suturaTipo: enumByName(SuturaTipo.values, json['sutura_tipo']),
        drenajeNum: (json['drenaje_num'] as num?)?.toInt(),
        suturaNum: (json['sutura_num'] as num?)?.toInt(),
        motivoEgreso: enumByName(MotivoEgreso.values, json['discharge_reason']),
        isActive: json['is_active'] as bool? ?? true,
        closedAt: json['closed_at'] == null
            ? null
            : DateTime.parse(json['closed_at'] as String),
        createdAt: DateTime.parse(json['created_at'] as String),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'patient_id': patientId,
        'etiology': etiology.dbValue,
        'subtype': subtype,
        'body_location_primary': bodyLocationPrimary,
        'body_location_secondary': bodyLocationSecondary,
        'onset_date': onsetDate?.toIso8601String().substring(0, 10),
        'wagner_grade': wagnerGrade?.name,
        'wifi_wound': wifiWound,
        'wifi_ischemia': wifiIschemia,
        'wifi_infection': wifiInfection,
        'ceap_class': ceapClass?.name,
        'wuwhs_grade': wuwhsGrade?.name,
        'agente_causal': agenteCausal?.name,
        'upd_subtipo': updSubtipo?.name,
        'texas_grade': texasGrade?.name,
        'texas_stage': texasStage?.name,
        'idsa_iwgdf': idsaIwgdf?.name,
        'sensibilidad_protectora': sensibilidadProtectora?.name,
        'rutherford': rutherford?.name,
        'npuap_estadio': npuapEstadio?.name,
        'clase_contaminacion': claseContaminacion?.name,
        'tipo_cierre': tipoCierre?.name,
        'drenaje_tipo': drenajeTipo?.name,
        'sutura_tipo': suturaTipo?.name,
        'drenaje_num': drenajeNum,
        'sutura_num': suturaNum,
        'discharge_reason': motivoEgreso?.name,
        'is_active': isActive,
        'closed_at': closedAt?.toIso8601String(),
        'created_at': createdAt.toIso8601String(),
      };
}

/// Medicion seriada de una herida (dimensiones + composicion del lecho).
class WoundMeasurement {
  final String id;
  final String woundId;
  final String? consultationId;
  final DateTime measuredAt;
  final double lengthCm;
  final double widthCm;
  final double areaCm2;
  final double depthCm;
  final bool tunneling;
  final bool undermining;
  final double granulationPct;
  final double sloughPct; // esfacelo
  final double necrosisPct;
  final double epithelializationPct;
  final bool capturedBeforeDebridement;
  // Medicion 3D (heridas profundas): volumen en cm3. NULL si solo se midio
  // en 2D (largo/ancho/area). Protocolo de Fotografias y Medicion (P1/P2).
  // Auto-calculado con la formula de Kundin (V = L x A x P x 0.327,
  // feat/volume-kundin-charts) cuando depthCm > 0; el clinico puede
  // sobrescribirlo (ver volumeManual).
  final double? volumeCm3;
  // true si el valor persistido en volumeCm3 fue editado manualmente por
  // el clinico (difiere del auto-calculo de Kundin al momento de guardar).
  // Migracion 0015 (feat/volume-kundin-charts).
  final bool volumeManual;
  // Nota de medicion manual (hisopo/regla) para socavamiento, tunelizacion,
  // heridas circunferenciales o de geometria irregular.
  final String? manualMeasurementNote;

  const WoundMeasurement({
    required this.id,
    required this.woundId,
    this.consultationId,
    required this.measuredAt,
    required this.lengthCm,
    required this.widthCm,
    required this.areaCm2,
    this.depthCm = 0,
    this.tunneling = false,
    this.undermining = false,
    this.granulationPct = 0,
    this.sloughPct = 0,
    this.necrosisPct = 0,
    this.epithelializationPct = 0,
    this.capturedBeforeDebridement = true,
    this.volumeCm3,
    this.volumeManual = false,
    this.manualMeasurementNote,
  });

  double get bedCompositionSum =>
      granulationPct + sloughPct + necrosisPct + epithelializationPct;

  factory WoundMeasurement.fromJson(Map<String, dynamic> json) => WoundMeasurement(
        id: json['id'] as String,
        woundId: json['wound_id'] as String,
        consultationId: json['consultation_id'] as String?,
        measuredAt: DateTime.parse(json['measured_at'] as String),
        lengthCm: (json['length_cm'] as num).toDouble(),
        widthCm: (json['width_cm'] as num).toDouble(),
        areaCm2: (json['area_cm2'] as num).toDouble(),
        depthCm: (json['depth_cm'] as num?)?.toDouble() ?? 0,
        tunneling: json['tunneling'] as bool? ?? false,
        undermining: json['undermining'] as bool? ?? false,
        granulationPct: (json['granulation_pct'] as num?)?.toDouble() ?? 0,
        sloughPct: (json['slough_pct'] as num?)?.toDouble() ?? 0,
        necrosisPct: (json['necrosis_pct'] as num?)?.toDouble() ?? 0,
        epithelializationPct: (json['epithelialization_pct'] as num?)?.toDouble() ?? 0,
        capturedBeforeDebridement: json['captured_before_debridement'] as bool? ?? true,
        volumeCm3: (json['volume_cm3'] as num?)?.toDouble(),
        volumeManual: json['volume_manual'] as bool? ?? false,
        manualMeasurementNote: json['manual_measurement_note'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'wound_id': woundId,
        'consultation_id': consultationId,
        'measured_at': measuredAt.toIso8601String().substring(0, 10),
        'length_cm': lengthCm,
        'width_cm': widthCm,
        'area_cm2': areaCm2,
        'depth_cm': depthCm,
        'tunneling': tunneling,
        'undermining': undermining,
        'granulation_pct': granulationPct,
        'slough_pct': sloughPct,
        'necrosis_pct': necrosisPct,
        'epithelialization_pct': epithelializationPct,
        'captured_before_debridement': capturedBeforeDebridement,
        'volume_cm3': volumeCm3,
        'volume_manual': volumeManual,
        'manual_measurement_note': manualMeasurementNote,
      };
}

/// Evaluacion clinica (paso de valoracion) asociada a una consulta+herida.
class WoundAssessment {
  final String id;
  final String consultationId;
  final String woundId;
  final double? glucoseMgDl;
  // HbA1c (hemoglobina glucosilada, %) - distinta de glucoseMgDl.
  final double? hba1cPct;
  // Escala de Braden (riesgo de LPP), score total 6-23.
  final int? bradenScore;
  final DateTime? firstAssessmentDate;
  final String? edema;
  final bool? pain;
  final String? painType;
  final String? painDuration;
  final int? painVas;
  final ExudadoTipo? exudateType;
  final ExudadoCantidad exudateAmount;
  final Set<InfeccionCriterioIwii> infectionCriteria;
  final String? odor;
  final String? woundEdge;
  final Set<PielPerilesionalEstado> perilesionalSkin;
  // Baja adherencia al tratamiento indicado desde la visita anterior
  // (reportado por el clinico en visitas de seguimiento). Alimenta el
  // parametro bajaAdherencia de KuraSheehanCheckpoint.evaluate().
  final bool lowAdherence;
  // Notas clinicas / observaciones libres de la visita (opcional).
  // Complementa los campos estructurados de arriba; aplica tanto a
  // valoracion como a seguimiento (feat/clinical-free-notes).
  final String? clinicalNotes;

  const WoundAssessment({
    required this.id,
    required this.consultationId,
    required this.woundId,
    this.glucoseMgDl,
    this.hba1cPct,
    this.bradenScore,
    this.firstAssessmentDate,
    this.edema,
    this.pain,
    this.painType,
    this.painDuration,
    this.painVas,
    this.exudateType,
    this.exudateAmount = ExudadoCantidad.escaso,
    this.infectionCriteria = const {},
    this.odor,
    this.woundEdge,
    this.perilesionalSkin = const {},
    this.lowAdherence = false,
    this.clinicalNotes,
  });

  factory WoundAssessment.fromJson(Map<String, dynamic> json) => WoundAssessment(
        id: json['id'] as String,
        consultationId: json['consultation_id'] as String,
        woundId: json['wound_id'] as String,
        glucoseMgDl: (json['glucose_mg_dl'] as num?)?.toDouble(),
        hba1cPct: (json['hba1c_pct'] as num?)?.toDouble(),
        bradenScore: json['braden_score'] as int?,
        firstAssessmentDate: json['first_assessment_date'] == null
            ? null
            : DateTime.parse(json['first_assessment_date'] as String),
        edema: json['edema'] as String?,
        pain: json['pain'] as bool?,
        painType: json['pain_type'] as String?,
        painDuration: json['pain_duration'] as String?,
        painVas: json['pain_vas'] as int?,
        odor: json['odor'] as String?,
        woundEdge: json['wound_edge'] as String?,
        exudateType: json['exudate_type'] == null
            ? null
            : ExudadoTipo.values.firstWhere(
                (e) => e.name == json['exudate_type'],
                orElse: () => ExudadoTipo.otro,
              ),
        exudateAmount: ExudadoCantidad.values.firstWhere(
          (e) => e.name == (json['exudate_amount'] ?? 'escaso'),
          orElse: () => ExudadoCantidad.escaso,
        ),
        infectionCriteria: ((json['infection_criteria'] as List?) ?? [])
            .map((s) => InfeccionCriterioIwii.values.firstWhere((e) => e.name == s))
            .toSet(),
        perilesionalSkin: ((json['perilesional_skin'] as List?) ?? [])
            .map((s) => PielPerilesionalEstado.values.firstWhere((e) => e.name == s))
            .toSet(),
        lowAdherence: json['low_adherence'] as bool? ?? false,
        clinicalNotes: json['clinical_notes'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'consultation_id': consultationId,
        'wound_id': woundId,
        'glucose_mg_dl': glucoseMgDl,
        'hba1c_pct': hba1cPct,
        'braden_score': bradenScore,
        'first_assessment_date': firstAssessmentDate?.toIso8601String().substring(0, 10),
        'edema': edema,
        'pain': pain,
        'pain_type': painType,
        'pain_duration': painDuration,
        'pain_vas': painVas,
        'exudate_type': exudateType?.name,
        'exudate_amount': exudateAmount.name,
        'infection_criteria': infectionCriteria.map((e) => e.name).toList(),
        'odor': odor,
        'wound_edge': woundEdge,
        'perilesional_skin': perilesionalSkin.map((e) => e.name).toList(),
        'low_adherence': lowAdherence,
        'clinical_notes': clinicalNotes,
      };
}

/// Perfusion (ABI/ITB) y nutricion (albumina) — usado por ajustes clinicos (8.2).
class PerfusionNutritionData {
  final String id;
  final String consultationId;
  final String woundId;
  final double? abiRight;
  final double? abiLeft;
  final bool isLowerExtremity;
  final double? albuminGdl;

  const PerfusionNutritionData({
    required this.id,
    required this.consultationId,
    required this.woundId,
    this.abiRight,
    this.abiLeft,
    this.isLowerExtremity = false,
    this.albuminGdl,
  });

  factory PerfusionNutritionData.fromJson(Map<String, dynamic> json) =>
      PerfusionNutritionData(
        id: json['id'] as String,
        consultationId: json['consultation_id'] as String,
        woundId: json['wound_id'] as String,
        abiRight: (json['abi_right'] as num?)?.toDouble(),
        abiLeft: (json['abi_left'] as num?)?.toDouble(),
        isLowerExtremity: json['is_lower_extremity'] as bool? ?? false,
        albuminGdl: (json['albumin_g_dl'] as num?)?.toDouble(),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'consultation_id': consultationId,
        'wound_id': woundId,
        'abi_right': abiRight,
        'abi_left': abiLeft,
        'is_lower_extremity': isLowerExtremity,
        'albumin_g_dl': albuminGdl,
      };
}
