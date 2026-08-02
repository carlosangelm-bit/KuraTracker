// Laboratorios del paciente (ver 0070_patient_labs.sql). El motor usa los más
// recientes: albúmina (regla existente) + glucosa/O2 (factores, en validación).
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
        notes: j['notes'] as String?,
      );
}
