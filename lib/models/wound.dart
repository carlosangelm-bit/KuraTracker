import '../engine/models/kura_engine_enums.dart';

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
        'exudate_amount': exudateAmount.name,
        'infection_criteria': infectionCriteria.map((e) => e.name).toList(),
        'odor': odor,
        'wound_edge': woundEdge,
        'perilesional_skin': perilesionalSkin.map((e) => e.name).toList(),
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
