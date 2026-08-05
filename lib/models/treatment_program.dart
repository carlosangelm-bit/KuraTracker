// Plan de tratamiento MENSUAL (ver 0075_treatment_programs.sql). Capa intermedia
// entre la valoración y los seguimientos: insumos por procedimiento (cantidad
// por sesión) + sesiones del mes (fecha+hora). Al aceptarse detona la agenda y
// pre-carga cada seguimiento.

enum ProgramStatus { borrador, aceptado, cancelado, completado }

ProgramStatus programStatusFromDb(String? s) => switch (s) {
      'aceptado' => ProgramStatus.aceptado,
      'cancelado' => ProgramStatus.cancelado,
      'completado' => ProgramStatus.completado,
      _ => ProgramStatus.borrador,
    };

extension ProgramStatusX on ProgramStatus {
  String get dbValue => name;
  String get label => switch (this) {
        ProgramStatus.borrador => 'Borrador',
        ProgramStatus.aceptado => 'Aceptado',
        ProgramStatus.cancelado => 'Cancelado',
        ProgramStatus.completado => 'Completado',
      };
}

class TreatmentProgram {
  final String id;
  final String organizationId;
  final String patientId;
  final String woundId;
  final String? consultationId;
  final String? siteId;
  final String? staffId;
  final int weeks;
  final ProgramStatus status;
  final String? notes;
  final DateTime? acceptedAt;
  final DateTime createdAt;

  const TreatmentProgram({
    required this.id,
    required this.organizationId,
    required this.patientId,
    required this.woundId,
    this.consultationId,
    this.siteId,
    this.staffId,
    this.weeks = 4,
    this.status = ProgramStatus.borrador,
    this.notes,
    this.acceptedAt,
    required this.createdAt,
  });

  factory TreatmentProgram.fromJson(Map<String, dynamic> j) => TreatmentProgram(
        id: j['id'] as String,
        organizationId: j['organization_id'] as String,
        patientId: j['patient_id'] as String,
        woundId: j['wound_id'] as String,
        consultationId: j['consultation_id'] as String?,
        siteId: j['site_id'] as String?,
        staffId: j['staff_id'] as String?,
        weeks: (j['weeks'] as num?)?.toInt() ?? 4,
        status: programStatusFromDb(j['status'] as String?),
        notes: j['notes'] as String?,
        acceptedAt: j['accepted_at'] == null
            ? null
            : DateTime.parse(j['accepted_at'] as String),
        createdAt: j['created_at'] == null
            ? DateTime.now()
            : DateTime.parse(j['created_at'] as String),
      );
}

/// Insumo del plan (por procedimiento). La cantidad se interpreta según
/// [isMonthly]: si es false (default), es cantidad POR SESIÓN (mensual = ×
/// sesiones); si es true, es cantidad MENSUAL directa (producto multidosis que
/// se compra 1–2 veces al mes, sin multiplicar por sesiones).
class TreatmentProgramSupply {
  final String id;
  final String programId;
  final String organizationId;
  final String method; // procedimiento
  final String? product; // genérico
  final String? inventoryItemId;
  final String name;
  final double quantityPerSession;
  final bool isMonthly; // true = la cantidad ya es la del mes (multidosis)
  final double? unitCost;
  final double? unitPrice;
  final String? currency;
  final int sortOrder;

  const TreatmentProgramSupply({
    required this.id,
    required this.programId,
    required this.organizationId,
    required this.method,
    this.product,
    this.inventoryItemId,
    required this.name,
    this.quantityPerSession = 1,
    this.isMonthly = false,
    this.unitCost,
    this.unitPrice,
    this.currency,
    this.sortOrder = 0,
  });

  double get unitAmount => unitPrice ?? unitCost ?? 0;

  factory TreatmentProgramSupply.fromJson(Map<String, dynamic> j) =>
      TreatmentProgramSupply(
        id: j['id'] as String,
        programId: j['program_id'] as String,
        organizationId: j['organization_id'] as String,
        method: j['method'] as String? ?? '',
        product: j['product'] as String?,
        inventoryItemId: j['inventory_item_id'] as String?,
        name: j['name'] as String? ?? '',
        quantityPerSession:
            (j['quantity_per_session'] as num?)?.toDouble() ?? 1,
        isMonthly: (j['is_monthly'] as bool?) ?? false,
        unitCost: (j['unit_cost'] as num?)?.toDouble(),
        unitPrice: (j['unit_price'] as num?)?.toDouble(),
        currency: j['currency'] as String?,
        sortOrder: (j['sort_order'] as num?)?.toInt() ?? 0,
      );
}

enum SessionStatus { planeada, agendada, realizada, cancelada }

SessionStatus sessionStatusFromDb(String? s) => switch (s) {
      'agendada' => SessionStatus.agendada,
      'realizada' => SessionStatus.realizada,
      'cancelada' => SessionStatus.cancelada,
      _ => SessionStatus.planeada,
    };

extension SessionStatusX on SessionStatus {
  String get dbValue => name;
  String get label => switch (this) {
        SessionStatus.planeada => 'Planeada',
        SessionStatus.agendada => 'Agendada',
        SessionStatus.realizada => 'Realizada',
        SessionStatus.cancelada => 'Cancelada',
      };
}

/// Sesión del mes (fecha+hora) del programa.
class TreatmentProgramSession {
  final String id;
  final String programId;
  final String organizationId;
  final String patientId;
  final String? staffId;
  final DateTime scheduledAt;
  final DateTime? endAt;
  final SessionStatus status;
  final String? appointmentRef;
  final String? consultationId;
  final int sortIndex;

  const TreatmentProgramSession({
    required this.id,
    required this.programId,
    required this.organizationId,
    required this.patientId,
    this.staffId,
    required this.scheduledAt,
    this.endAt,
    this.status = SessionStatus.planeada,
    this.appointmentRef,
    this.consultationId,
    this.sortIndex = 0,
  });

  factory TreatmentProgramSession.fromJson(Map<String, dynamic> j) =>
      TreatmentProgramSession(
        id: j['id'] as String,
        programId: j['program_id'] as String,
        organizationId: j['organization_id'] as String,
        patientId: j['patient_id'] as String,
        staffId: j['staff_id'] as String?,
        scheduledAt: DateTime.parse(j['scheduled_at'] as String),
        endAt: j['end_at'] == null
            ? null
            : DateTime.parse(j['end_at'] as String),
        status: sessionStatusFromDb(j['status'] as String?),
        appointmentRef: j['appointment_ref'] as String?,
        consultationId: j['consultation_id'] as String?,
        sortIndex: (j['sort_index'] as num?)?.toInt() ?? 0,
      );
}
