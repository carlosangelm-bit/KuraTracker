enum ComponentOrigin { manual, kuraSuggested, kuraEdited }

extension ComponentOriginDb on ComponentOrigin {
  String get dbValue {
    switch (this) {
      case ComponentOrigin.manual:
        return 'manual';
      case ComponentOrigin.kuraSuggested:
        return 'kura_suggested';
      case ComponentOrigin.kuraEdited:
        return 'kura_edited';
    }
  }

  static ComponentOrigin fromDb(String s) {
    switch (s) {
      case 'kura_suggested':
        return ComponentOrigin.kuraSuggested;
      case 'kura_edited':
        return ComponentOrigin.kuraEdited;
      default:
        return ComponentOrigin.manual;
    }
  }
}

class TreatmentComponentRecord {
  final String id;
  final String treatmentPlanId;
  final String method;
  final String product;
  final ComponentOrigin origin;
  final int sortOrder;

  const TreatmentComponentRecord({
    required this.id,
    required this.treatmentPlanId,
    required this.method,
    required this.product,
    this.origin = ComponentOrigin.manual,
    this.sortOrder = 0,
  });

  factory TreatmentComponentRecord.fromJson(Map<String, dynamic> json) =>
      TreatmentComponentRecord(
        id: json['id'] as String,
        treatmentPlanId: json['treatment_plan_id'] as String,
        method: json['method'] as String,
        product: json['product'] as String,
        origin: ComponentOriginDb.fromDb(json['origin'] as String? ?? 'manual'),
        sortOrder: json['sort_order'] as int? ?? 0,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'treatment_plan_id': treatmentPlanId,
        'method': method,
        'product': product,
        'origin': origin.dbValue,
        'sort_order': sortOrder,
      };
}

class TreatmentPlan {
  final String id;
  final String consultationId;
  final String woundId;
  final bool usedKuraProtocol;
  final String? finalDescription;
  final List<TreatmentComponentRecord> components;

  const TreatmentPlan({
    required this.id,
    required this.consultationId,
    required this.woundId,
    this.usedKuraProtocol = false,
    this.finalDescription,
    this.components = const [],
  });

  factory TreatmentPlan.fromJson(
    Map<String, dynamic> json, {
    List<TreatmentComponentRecord> components = const [],
  }) =>
      TreatmentPlan(
        id: json['id'] as String,
        consultationId: json['consultation_id'] as String,
        woundId: json['wound_id'] as String,
        usedKuraProtocol: json['used_kura_protocol'] as bool? ?? false,
        finalDescription: json['final_description'] as String?,
        components: components,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'consultation_id': consultationId,
        'wound_id': woundId,
        'used_kura_protocol': usedKuraProtocol,
        'final_description': finalDescription,
      };
}

/// Etapa de la secuencia fotografica (Protocolo de Fotografias SS1.2).
enum PhotoStage { antesLimpiar, despuesLimpiar, conMedicion, cierre }

extension PhotoStageDb on PhotoStage {
  String get dbValue {
    switch (this) {
      case PhotoStage.antesLimpiar:
        return 'antes_limpiar';
      case PhotoStage.despuesLimpiar:
        return 'despues_limpiar';
      case PhotoStage.conMedicion:
        return 'con_medicion';
      case PhotoStage.cierre:
        return 'cierre';
    }
  }

  String get label {
    switch (this) {
      case PhotoStage.antesLimpiar:
        return 'Antes de limpiar';
      case PhotoStage.despuesLimpiar:
        return 'Despues de limpiar (sin medicion)';
      case PhotoStage.conMedicion:
        return 'Con medicion';
      case PhotoStage.cierre:
        return 'Cierre (herida cicatrizada)';
    }
  }

  static PhotoStage? fromDb(String? s) {
    switch (s) {
      case 'antes_limpiar':
        return PhotoStage.antesLimpiar;
      case 'despues_limpiar':
        return PhotoStage.despuesLimpiar;
      case 'con_medicion':
        return PhotoStage.conMedicion;
      case 'cierre':
        return PhotoStage.cierre;
      default:
        return null;
    }
  }
}

class WoundPhoto {
  final String id;
  final String woundId;
  final String? consultationId;
  final String? measurementId;
  final String storagePath;
  final DateTime takenAt;
  final bool isBaseline;
  final int? sizeBytes;
  // Etapa de la secuencia fotografica segun protocolo. NULL permitido para
  // fotos historicas/importadas (p.ej. desde eKare) sin clasificar.
  final PhotoStage? photoStage;

  const WoundPhoto({
    required this.id,
    required this.woundId,
    this.consultationId,
    this.measurementId,
    required this.storagePath,
    required this.takenAt,
    this.isBaseline = false,
    this.sizeBytes,
    this.photoStage,
  });

  factory WoundPhoto.fromJson(Map<String, dynamic> json) => WoundPhoto(
        id: json['id'] as String,
        woundId: json['wound_id'] as String,
        consultationId: json['consultation_id'] as String?,
        measurementId: json['measurement_id'] as String?,
        storagePath: json['storage_path'] as String,
        takenAt: DateTime.parse(json['taken_at'] as String),
        isBaseline: json['is_baseline'] as bool? ?? false,
        sizeBytes: json['size_bytes'] as int?,
        photoStage: PhotoStageDb.fromDb(json['photo_stage'] as String?),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'wound_id': woundId,
        'consultation_id': consultationId,
        'measurement_id': measurementId,
        'storage_path': storagePath,
        'taken_at': takenAt.toIso8601String(),
        'is_baseline': isBaseline,
        'size_bytes': sizeBytes,
        'photo_stage': photoStage?.dbValue,
      };
}
