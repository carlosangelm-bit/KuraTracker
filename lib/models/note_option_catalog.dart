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

  /// Identificador de columna "seccion" usado en la plantilla CSV de
  /// importacion/exportacion del catalogo (pantalla de Configuracion).
  /// Deliberadamente DISTINTO de [dbValue]: el CSV esta pensado para que
  /// lo edite el admin del centro en Excel/Sheets, con nombres en espanol
  /// mas cortos y legibles que los identificadores de columna SQL.
  String get csvSeccion {
    switch (this) {
      case NoteOptionField.careType:
        return 'tipo_atencion';
      case NoteOptionField.procedureDesc:
        return 'descripcion';
      case NoteOptionField.materialsUsed:
        return 'material';
      case NoteOptionField.evolution:
        return 'evolucion';
    }
  }

  /// Resuelve un [NoteOptionField] a partir del valor de la columna
  /// "seccion" de un CSV cargado por el admin. Acepta el valor tal cual
  /// (case/espacios-insensitive) y retorna null si no coincide con
  /// ninguna de las 4 secciones validas (fila a rechazar en la
  /// validacion de importacion).
  static NoteOptionField? fromCsvSeccion(String? s) {
    final normalized = s?.trim().toLowerCase();
    for (final f in NoteOptionField.values) {
      if (f.csvSeccion == normalized) return f;
    }
    return null;
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
  // Centro (organizacion) dueno de este concepto. Ver 0011_organizations.sql:
  // note_option_catalog.organization_id (not null). El catalogo es
  // configurable por centro: dos organizaciones pueden tener conceptos con
  // el mismo texto sin colisionar (unicidad ahora es por
  // (organization_id, field, label)).
  final String? organizationId;

  const NoteOptionCatalogItem({
    required this.id,
    required this.field,
    required this.label,
    this.isActive = true,
    this.createdBy,
    this.organizationId,
  });

  factory NoteOptionCatalogItem.fromJson(Map<String, dynamic> json) =>
      NoteOptionCatalogItem(
        id: json['id'] as String,
        field: NoteOptionFieldDb.fromDb(json['field'] as String?) ??
            NoteOptionField.careType,
        label: json['label'] as String,
        isActive: json['is_active'] as bool? ?? true,
        createdBy: json['created_by'] as String?,
        organizationId: json['organization_id'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'field': field.dbValue,
        'label': label,
        'is_active': isActive,
        'created_by': createdBy,
        'organization_id': organizationId,
      };
}
