// Laboratorios del paciente (ver 0070_patient_labs.sql + 0073 dominio clínico).
// El motor usa los más recientes: albúmina (regla existente) + glucosa/O2
// (factores, en validación). Los demás parámetros alimentan el PUNTAJE 0–3 del
// dominio clínico (ver lib/engine/labs/lab_domain_scoring.dart), que hoy es
// informativo (banderas de severidad), no entra al motor.
class PatientLab {
  final String id;
  final String organizationId;
  final String patientId;
  final DateTime takenAt;
  final double? glucoseMgDl;
  final double? hba1cPct;
  final double? albuminGdl;
  final double? hemoglobinGdl;
  final double? o2SaturationPct;
  // Dominio clínico ampliado (0073)
  final double? prealbuminMgDl;
  final double? totalProteinGdl;
  final double? crpMgL;
  final double? ptSeconds;
  final double? hematocritPct;
  final double? plateletsUl;
  final double? pttSeconds;
  final String? notes;

  const PatientLab({
    required this.id,
    required this.organizationId,
    required this.patientId,
    required this.takenAt,
    this.glucoseMgDl,
    this.hba1cPct,
    this.albuminGdl,
    this.hemoglobinGdl,
    this.o2SaturationPct,
    this.prealbuminMgDl,
    this.totalProteinGdl,
    this.crpMgL,
    this.ptSeconds,
    this.hematocritPct,
    this.plateletsUl,
    this.pttSeconds,
    this.notes,
  });

  factory PatientLab.fromJson(Map<String, dynamic> j) => PatientLab(
        id: j['id'] as String,
        organizationId: j['organization_id'] as String,
        patientId: j['patient_id'] as String,
        takenAt: DateTime.parse(j['taken_at'] as String),
        glucoseMgDl: (j['glucose_mg_dl'] as num?)?.toDouble(),
        hba1cPct: (j['hba1c_pct'] as num?)?.toDouble(),
        albuminGdl: (j['albumin_g_dl'] as num?)?.toDouble(),
        hemoglobinGdl: (j['hemoglobin_g_dl'] as num?)?.toDouble(),
        o2SaturationPct: (j['o2_saturation_pct'] as num?)?.toDouble(),
        prealbuminMgDl: (j['prealbumin_mg_dl'] as num?)?.toDouble(),
        totalProteinGdl: (j['total_protein_g_dl'] as num?)?.toDouble(),
        crpMgL: (j['crp_mg_l'] as num?)?.toDouble(),
        ptSeconds: (j['pt_seconds'] as num?)?.toDouble(),
        hematocritPct: (j['hematocrit_pct'] as num?)?.toDouble(),
        plateletsUl: (j['platelets_ul'] as num?)?.toDouble(),
        pttSeconds: (j['ptt_seconds'] as num?)?.toDouble(),
        notes: j['notes'] as String?,
      );
}
