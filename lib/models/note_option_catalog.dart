/// Campo de la nota de seguimiento al que pertenece un concepto del
/// catalogo (`note_option_catalog`, ver 0010_note_option_catalog.sql).
enum NoteOptionField { careType, procedureDesc, materialsUsed, evolution }

extension NoteOptionFieldDb on NoteOptionField {
  String get dbValue {
    switch (this) {
      case NoteOptionField.careType:
        return 'care_type';
      case NoteOptionField.procedureDesc:
        return 'procedure_desc';
      case NoteOptionField.materialsUsed:
        return 'materials_used';
      case NoteOptionField.evolution:
        return 'evolution';
    }
  }

  /// Etiqueta legible del campo (para la pantalla de Configuracion).
  String get label {
    switch (this) {
      case NoteOptionField.careType:
        return 'Tipo de atención';
      case NoteOptionField.procedureDesc:
        return 'Descripción del procedimiento';
      case NoteOptionField.materialsUsed:
        return 'Material utilizado';
      case NoteOptionField.evolution:
        return 'Evolución';
    }
  }

  static NoteOptionField? fromDb(String? s) {
    switch (s) {
      case 'care_type':
        return NoteOptionField.careType;
      case 'procedure_desc':
        return NoteOptionField.procedureDesc;
      case 'materials_used':
        return NoteOptionField.materialsUsed;
      case 'evolution':
        return NoteOptionField.evolution;
      default:
        return null;
    }
  }
}

/// Concepto configurable por el centro (admin) para uno de los campos de
/// la nota de seguimiento obligatoria. Ver 0010_note_option_catalog.sql.
class NoteOptionCatalogItem {
  final String id;
  final NoteOptionField field;
  final String label;
  final bool isActive;
  final String? createdBy;

  const NoteOptionCatalogItem({
    required this.id,
    required this.field,
    required this.label,
    this.isActive = true,
    this.createdBy,
  });

  factory NoteOptionCatalogItem.fromJson(Map<String, dynamic> json) =>
      NoteOptionCatalogItem(
        id: json['id'] as String,
        field: NoteOptionFieldDb.fromDb(json['field'] as String?) ??
            NoteOptionField.careType,
        label: json['label'] as String,
        isActive: json['is_active'] as bool? ?? true,
        createdBy: json['created_by'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'field': field.dbValue,
        'label': label,
        'is_active': isActive,
        'created_by': createdBy,
      };
}
