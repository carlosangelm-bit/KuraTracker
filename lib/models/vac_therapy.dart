// Modelos del módulo Terapia VAC (NPWT). Ver 0064_vac_therapy.sql.
// Fase 1: episodio de terapia + bitácora. Las alarmas/bot son fase posterior.

/// Equipo de terapia de presión negativa.
enum VacEquipment { vacUlta, activac, otro }

extension VacEquipmentX on VacEquipment {
  String get dbValue {
    switch (this) {
      case VacEquipment.vacUlta:
        return 'vac_ulta';
      case VacEquipment.activac:
        return 'activac';
      case VacEquipment.otro:
        return 'otro';
    }
  }

  String get label {
    switch (this) {
      case VacEquipment.vacUlta:
        return 'V.A.C. Ulta (quirófano/hospital)';
      case VacEquipment.activac:
        return 'ActiV.A.C. (portátil/domicilio)';
      case VacEquipment.otro:
        return 'Otro equipo';
    }
  }

  static VacEquipment fromDb(String? s) {
    switch (s) {
      case 'activac':
        return VacEquipment.activac;
      case 'otro':
        return VacEquipment.otro;
      default:
        return VacEquipment.vacUlta;
    }
  }
}

/// Modo de terapia.
enum VacMode { continuo, intermitente, instilacion }

extension VacModeX on VacMode {
  String get dbValue => name;
  String get label {
    switch (this) {
      case VacMode.continuo:
        return 'Continua';
      case VacMode.intermitente:
        return 'Intermitente';
      case VacMode.instilacion:
        return 'Con instilación (Veraflo)';
    }
  }

  static VacMode? fromDb(String? s) {
    for (final m in VacMode.values) {
      if (m.name == s) return m;
    }
    return null;
  }
}

/// Tipo de apósito/interfaz.
enum VacDressing { granufoam, granufoamPlata, whitefoam, otro }

extension VacDressingX on VacDressing {
  String get dbValue {
    switch (this) {
      case VacDressing.granufoam:
        return 'granufoam';
      case VacDressing.granufoamPlata:
        return 'granufoam_plata';
      case VacDressing.whitefoam:
        return 'whitefoam';
      case VacDressing.otro:
        return 'otro';
    }
  }

  String get label {
    switch (this) {
      case VacDressing.granufoam:
        return 'GranuFoam (negra)';
      case VacDressing.granufoamPlata:
        return 'GranuFoam Plata';
      case VacDressing.whitefoam:
        return 'WhiteFoam';
      case VacDressing.otro:
        return 'Otro';
    }
  }

  static VacDressing? fromDb(String? s) {
    switch (s) {
      case 'granufoam':
        return VacDressing.granufoam;
      case 'granufoam_plata':
        return VacDressing.granufoamPlata;
      case 'whitefoam':
        return VacDressing.whitefoam;
      case 'otro':
        return VacDressing.otro;
      default:
        return null;
    }
  }
}

/// Ubicación (dónde está la terapia / dónde se colocó).
enum VacLocation { quirofano, hospital, clinica, domicilio }

extension VacLocationX on VacLocation {
  String get dbValue => name;
  String get label {
    switch (this) {
      case VacLocation.quirofano:
        return 'Quirófano';
      case VacLocation.hospital:
        return 'Hospitalización';
      case VacLocation.clinica:
        return 'Clínica de heridas';
      case VacLocation.domicilio:
        return 'Domicilio';
    }
  }

  static VacLocation? fromDb(String? s) {
    for (final l in VacLocation.values) {
      if (l.name == s) return l;
    }
    return null;
  }
}

/// Estado del episodio de terapia.
enum VacTherapyStatus { activa, pausada, suspendida, finalizada }

extension VacTherapyStatusX on VacTherapyStatus {
  String get dbValue => name;
  String get label {
    switch (this) {
      case VacTherapyStatus.activa:
        return 'Activa';
      case VacTherapyStatus.pausada:
        return 'Pausada';
      case VacTherapyStatus.suspendida:
        return 'Suspendida';
      case VacTherapyStatus.finalizada:
        return 'Finalizada';
    }
  }

  static VacTherapyStatus fromDb(String? s) {
    for (final st in VacTherapyStatus.values) {
      if (st.name == s) return st;
    }
    return VacTherapyStatus.activa;
  }
}

/// Tipo de evento de la bitácora.
enum VacEventType {
  colocacion,
  transferencia,
  cambioEquipo,
  cambioAposito,
  ajuste,
  suspension,
  reinicio,
  egresoDomicilio,
  finalizacion,
  nota,
}

extension VacEventTypeX on VacEventType {
  String get dbValue {
    switch (this) {
      case VacEventType.cambioEquipo:
        return 'cambio_equipo';
      case VacEventType.cambioAposito:
        return 'cambio_aposito';
      case VacEventType.egresoDomicilio:
        return 'egreso_domicilio';
      default:
        return name;
    }
  }

  String get label {
    switch (this) {
      case VacEventType.colocacion:
        return 'Colocación';
      case VacEventType.transferencia:
        return 'Transferencia';
      case VacEventType.cambioEquipo:
        return 'Cambio de equipo';
      case VacEventType.cambioAposito:
        return 'Cambio de apósito';
      case VacEventType.ajuste:
        return 'Ajuste de parámetros';
      case VacEventType.suspension:
        return 'Suspensión';
      case VacEventType.reinicio:
        return 'Reinicio';
      case VacEventType.egresoDomicilio:
        return 'Egreso a domicilio';
      case VacEventType.finalizacion:
        return 'Finalización';
      case VacEventType.nota:
        return 'Nota';
    }
  }

  static VacEventType fromDb(String? s) {
    switch (s) {
      case 'cambio_equipo':
        return VacEventType.cambioEquipo;
      case 'cambio_aposito':
        return VacEventType.cambioAposito;
      case 'egreso_domicilio':
        return VacEventType.egresoDomicilio;
      default:
        for (final e in VacEventType.values) {
          if (e.name == s) return e;
        }
        return VacEventType.nota;
    }
  }
}

/// Episodio de terapia VAC de un paciente.
class VacTherapy {
  final String id;
  final String organizationId;
  final String patientId;
  final String? woundId;
  final VacEquipment equipment;
  final String? deviceSerial;
  final VacMode? mode;
  final int? targetPressureMmhg;
  final bool instillation;
  final String? instillSolution;
  final int? instillDwellMin;
  final VacDressing? dressing;
  final int? changeIntervalHours;
  final DateTime? placedAt;
  final String? placedBy;
  final VacLocation? placedLocation;
  final VacLocation? currentLocation;
  final VacTherapyStatus status;
  final String? caregiverInstructions;
  final String? notes;
  final DateTime startedAt;
  final DateTime? endedAt;

  const VacTherapy({
    required this.id,
    required this.organizationId,
    required this.patientId,
    this.woundId,
    this.equipment = VacEquipment.vacUlta,
    this.deviceSerial,
    this.mode,
    this.targetPressureMmhg,
    this.instillation = false,
    this.instillSolution,
    this.instillDwellMin,
    this.dressing,
    this.changeIntervalHours,
    this.placedAt,
    this.placedBy,
    this.placedLocation,
    this.currentLocation,
    this.status = VacTherapyStatus.activa,
    this.caregiverInstructions,
    this.notes,
    required this.startedAt,
    this.endedAt,
  });

  bool get isActive => status == VacTherapyStatus.activa;

  /// Resumen corto de parámetros: "-125 mmHg · Continua · GranuFoam".
  String get settingsLabel {
    final parts = <String>[
      if (targetPressureMmhg != null) '-$targetPressureMmhg mmHg',
      if (mode != null) mode!.label,
      if (dressing != null) dressing!.label,
    ];
    return parts.join(' · ');
  }

  factory VacTherapy.fromJson(Map<String, dynamic> j) => VacTherapy(
        id: j['id'] as String,
        organizationId: j['organization_id'] as String,
        patientId: j['patient_id'] as String,
        woundId: j['wound_id'] as String?,
        equipment: VacEquipmentX.fromDb(j['equipment_type'] as String?),
        deviceSerial: j['device_serial'] as String?,
        mode: VacModeX.fromDb(j['mode'] as String?),
        targetPressureMmhg: (j['target_pressure_mmhg'] as num?)?.toInt(),
        instillation: j['instillation'] as bool? ?? false,
        instillSolution: j['instill_solution'] as String?,
        instillDwellMin: (j['instill_dwell_min'] as num?)?.toInt(),
        dressing: VacDressingX.fromDb(j['dressing_type'] as String?),
        changeIntervalHours: (j['change_interval_hours'] as num?)?.toInt(),
        placedAt: j['placed_at'] == null
            ? null
            : DateTime.parse(j['placed_at'] as String),
        placedBy: j['placed_by'] as String?,
        placedLocation: VacLocationX.fromDb(j['placed_location'] as String?),
        currentLocation: VacLocationX.fromDb(j['current_location'] as String?),
        status: VacTherapyStatusX.fromDb(j['status'] as String?),
        caregiverInstructions: j['caregiver_instructions'] as String?,
        notes: j['notes'] as String?,
        startedAt: j['started_at'] == null
            ? DateTime.now()
            : DateTime.parse(j['started_at'] as String),
        endedAt: j['ended_at'] == null
            ? null
            : DateTime.parse(j['ended_at'] as String),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'organization_id': organizationId,
        'patient_id': patientId,
        'wound_id': woundId,
        'equipment_type': equipment.dbValue,
        'device_serial': deviceSerial,
        'mode': mode?.dbValue,
        'target_pressure_mmhg': targetPressureMmhg,
        'instillation': instillation,
        'instill_solution': instillSolution,
        'instill_dwell_min': instillDwellMin,
        'dressing_type': dressing?.dbValue,
        'change_interval_hours': changeIntervalHours,
        'placed_at': placedAt?.toIso8601String(),
        'placed_by': placedBy,
        'placed_location': placedLocation?.dbValue,
        'current_location': currentLocation?.dbValue,
        'status': status.dbValue,
        'caregiver_instructions': caregiverInstructions,
        'notes': notes,
        'started_at': startedAt.toIso8601String(),
        'ended_at': endedAt?.toIso8601String(),
      };
}

/// Evento de la bitácora de una terapia VAC.
class VacEvent {
  final String id;
  final String organizationId;
  final String therapyId;
  final String patientId;
  final VacEventType type;
  final DateTime at;
  final String? byProfile;
  final VacLocation? location;
  final String? note;

  const VacEvent({
    required this.id,
    required this.organizationId,
    required this.therapyId,
    required this.patientId,
    required this.type,
    required this.at,
    this.byProfile,
    this.location,
    this.note,
  });

  factory VacEvent.fromJson(Map<String, dynamic> j) => VacEvent(
        id: j['id'] as String,
        organizationId: j['organization_id'] as String,
        therapyId: j['therapy_id'] as String,
        patientId: j['patient_id'] as String,
        type: VacEventTypeX.fromDb(j['event_type'] as String?),
        at: j['at'] == null ? DateTime.now() : DateTime.parse(j['at'] as String),
        byProfile: j['by_profile'] as String?,
        location: VacLocationX.fromDb(j['location'] as String?),
        note: j['note'] as String?,
      );
}
