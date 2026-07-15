import '../engine/models/kura_engine_enums.dart';

class Patient {
  final String id;
  final String folio; // EXP2025-0001 / PA2026-0001
  final String fullName;
  final DateTime? birthDate;
  final String? sex;
  final String? primarySiteId;
  final String? mobility;
  final bool hasIdentifiedCaregiver;
  final String? caregiverName;
  final String? caregiverPhone;
  final bool fragilePatient;
  final String? backgroundNotes;
  final String? ekareExternalId;
  final bool isActive;
  final DateTime createdAt;
  // Centro (organizacion) dueno del expediente. Ver 0011_organizations.sql:
  // patients.organization_id (not null) -- aisla el expediente entre
  // centros distintos (RLS: un admin solo ve pacientes de SU organizacion).
  final String? organizationId;

  const Patient({
    required this.id,
    required this.folio,
    required this.fullName,
    this.birthDate,
    this.sex,
    this.primarySiteId,
    this.mobility,
    this.hasIdentifiedCaregiver = false,
    this.caregiverName,
    this.caregiverPhone,
    this.fragilePatient = false,
    this.backgroundNotes,
    this.ekareExternalId,
    this.isActive = true,
    required this.createdAt,
    this.organizationId,
  });

  int? get age {
    if (birthDate == null) return null;
    final now = DateTime.now();
    var age = now.year - birthDate!.year;
    if (now.month < birthDate!.month ||
        (now.month == birthDate!.month && now.day < birthDate!.day)) {
      age--;
    }
    return age;
  }

  factory Patient.fromJson(Map<String, dynamic> json) => Patient(
        id: json['id'] as String,
        folio: json['folio'] as String,
        fullName: json['full_name'] as String,
        birthDate: json['birth_date'] == null
            ? null
            : DateTime.parse(json['birth_date'] as String),
        sex: json['sex'] as String?,
        primarySiteId: json['primary_site_id'] as String?,
        mobility: json['mobility'] as String?,
        hasIdentifiedCaregiver: json['has_identified_caregiver'] as bool? ?? false,
        caregiverName: json['caregiver_name'] as String?,
        caregiverPhone: json['caregiver_phone'] as String?,
        fragilePatient: json['fragile_patient'] as bool? ?? false,
        backgroundNotes: json['background_notes'] as String?,
        ekareExternalId: json['ekare_external_id'] as String?,
        isActive: json['is_active'] as bool? ?? true,
        createdAt: DateTime.parse(json['created_at'] as String),
        organizationId: json['organization_id'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
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
        'ekare_external_id': ekareExternalId,
        'is_active': isActive,
        'created_at': createdAt.toIso8601String(),
        'organization_id': organizationId,
      };
}

class PatientComorbidity {
  final String id;
  final String patientId;
  final Comorbilidad code;
  final ComorbilidadEstado status;

  const PatientComorbidity({
    required this.id,
    required this.patientId,
    required this.code,
    required this.status,
  });

  factory PatientComorbidity.fromJson(Map<String, dynamic> json) =>
      PatientComorbidity(
        id: json['id'] as String,
        patientId: json['patient_id'] as String,
        code: _codeFromDb(json['code'] as String),
        status: _statusFromDb(json['status'] as String),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'patient_id': patientId,
        'code': _codeToDb(code),
        'status': _statusToDb(status),
      };

  static Comorbilidad _codeFromDb(String s) {
    switch (s) {
      case 'diabetes_mellitus':
        return Comorbilidad.diabetesMellitus;
      case 'enfermedad_arterial_periferica':
        return Comorbilidad.enfermedadArterialPeriferica;
      case 'insuficiencia_venosa_cronica':
        return Comorbilidad.insuficienciaVenosaCronica;
      case 'insuficiencia_renal_cronica':
        return Comorbilidad.insuficienciaRenalCronica;
      case 'enfermedad_cardiovascular':
        return Comorbilidad.enfermedadCardiovascular;
      case 'inmunosupresion':
        return Comorbilidad.inmunosupresion;
      case 'obesidad':
        return Comorbilidad.obesidad;
      case 'tabaquismo_activo':
        return Comorbilidad.tabaquismoActivo;
      case 'malnutricion':
        return Comorbilidad.malnutricion;
      case 'movilidad_reducida':
        return Comorbilidad.movilidadReducida;
      default:
        throw ArgumentError('Comorbilidad desconocida: $s');
    }
  }

  static String _codeToDb(Comorbilidad c) {
    switch (c) {
      case Comorbilidad.diabetesMellitus:
        return 'diabetes_mellitus';
      case Comorbilidad.enfermedadArterialPeriferica:
        return 'enfermedad_arterial_periferica';
      case Comorbilidad.insuficienciaVenosaCronica:
        return 'insuficiencia_venosa_cronica';
      case Comorbilidad.insuficienciaRenalCronica:
        return 'insuficiencia_renal_cronica';
      case Comorbilidad.enfermedadCardiovascular:
        return 'enfermedad_cardiovascular';
      case Comorbilidad.inmunosupresion:
        return 'inmunosupresion';
      case Comorbilidad.obesidad:
        return 'obesidad';
      case Comorbilidad.tabaquismoActivo:
        return 'tabaquismo_activo';
      case Comorbilidad.malnutricion:
        return 'malnutricion';
      case Comorbilidad.movilidadReducida:
        return 'movilidad_reducida';
    }
  }

  static ComorbilidadEstado _statusFromDb(String s) {
    switch (s) {
      case 'presente':
        return ComorbilidadEstado.presente;
      case 'negado':
        return ComorbilidadEstado.negado;
      default:
        return ComorbilidadEstado.noEvaluado;
    }
  }

  static String _statusToDb(ComorbilidadEstado s) {
    switch (s) {
      case ComorbilidadEstado.presente:
        return 'presente';
      case ComorbilidadEstado.negado:
        return 'negado';
      case ComorbilidadEstado.noEvaluado:
        return 'no_evaluado';
    }
  }
}
