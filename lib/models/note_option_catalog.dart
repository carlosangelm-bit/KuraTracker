/// Campo de la nota de seguimiento al que pertenece un concepto del
/// catalogo (`note_option_catalog`, ver 0010_note_option_catalog.sql).
enum NoteOptionField { careType, procedureDesc, materialsUsed, evolution }

/// Etiqueta de mapeo entre un concepto libre del catalogo del centro y
/// una categoria de metodo del motor "Protocolo Kura+" (kura_rules_v2,
/// ver 0013_note_option_catalog_kura_tag.sql). Es el puente que permite
/// pre-seleccionar (nunca forzar) conceptos del catalogo cuando un
/// usuario premium activa el toggle "Utilizar protocolo Kura+" en la
/// nota de seguimiento: cada componente del regimen sugerido por el
/// motor (`RegimenComponente.metodo`) se mapea a uno de estos valores
/// (ver `kKuraMethodToTag` en follow_up_capture_screen.dart), y solo los
/// conceptos del catalogo cuyo `kuraTag` coincida se pre-marcan.
enum KuraTag {
  limpieza,
  desbridamiento,
  rellenoCavidad,
  aposito,
  proteccionPiel,
  antimicrobiano,
  compresion,
  descarga,
  educacion,
}

extension KuraTagDb on KuraTag {
  String get dbValue {
    switch (this) {
      case KuraTag.limpieza:
        return 'limpieza';
      case KuraTag.desbridamiento:
        return 'desbridamiento';
      case KuraTag.rellenoCavidad:
        return 'relleno_cavidad';
      case KuraTag.aposito:
        return 'aposito';
      case KuraTag.proteccionPiel:
        return 'proteccion_piel';
      case KuraTag.antimicrobiano:
        return 'antimicrobiano';
      case KuraTag.compresion:
        return 'compresion';
      case KuraTag.descarga:
        return 'descarga';
      case KuraTag.educacion:
        return 'educacion';
    }
  }

  /// Etiqueta legible (dropdown de NoteCatalogTab en Administracion).
  String get label {
    switch (this) {
      case KuraTag.limpieza:
        return 'Limpieza';
      case KuraTag.desbridamiento:
        return 'Desbridamiento';
      case KuraTag.rellenoCavidad:
        return 'Relleno de cavidad';
      case KuraTag.aposito:
        return 'Apósito';
      case KuraTag.proteccionPiel:
        return 'Protección de la piel';
      case KuraTag.antimicrobiano:
        return 'Antimicrobiano';
      case KuraTag.compresion:
        return 'Compresión';
      case KuraTag.descarga:
        return 'Descarga (dispositivo)';
      case KuraTag.educacion:
        return 'Educación';
    }
  }

  /// Resuelve un [KuraTag] desde el valor de columna `kura_tag`. Devuelve
  /// `null` para NULL/vacio/valor no reconocido (concepto "Sin etiqueta"),
  /// nunca lanza -- un valor desconocido en la fila (p.ej. una etiqueta
  /// vieja renombrada) simplemente se trata como sin etiqueta, jamas
  /// tumba el listado ni auto-selecciona nada por error.
  static KuraTag? fromDb(String? s) {
    if (s == null || s.isEmpty) return null;
    for (final t in KuraTag.values) {
      if (t.dbValue == s) return t;
    }
    return null;
  }
}

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
  // Etiqueta de mapeo al motor Protocolo Kura+ (ver
  // 0013_note_option_catalog_kura_tag.sql). Null = "Sin etiqueta" (nunca
  // se auto-selecciona al activar el toggle premium).
  final KuraTag? kuraTag;

  const NoteOptionCatalogItem({
    required this.id,
    required this.field,
    required this.label,
    this.isActive = true,
    this.createdBy,
    this.organizationId,
    this.kuraTag,
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
        kuraTag: KuraTagDb.fromDb(json['kura_tag'] as String?),
      );

  /// Variante tolerante a filas malformadas (`id`/`label` nulos o de tipo
  /// inesperado). Devuelve `null` en vez de lanzar, para que un listado
  /// que mezcla muchas filas (p.ej. `DataRepository.listAllNoteOptions()`,
  /// leido SIN try/catch desde `build()`) pueda descartar la fila
  /// invalida sin tumbar toda la pantalla.
  ///
  /// Bug corregido (2026-07-15, "pantalla en blanco al crear concepto de
  /// catalogo"): una fila de `note_option_catalog` con `id` o `label` nulo
  /// -ya presente en cache antes del alta nueva, no necesariamente la fila
  /// recien insertada- hacia que `fromJson()` lanzara un TypeError de cast
  /// no capturado durante el rebuild post-`setState()` de
  /// `_NoteCatalogTabState._addOption()`, es decir FUERA del try/catch que
  /// solo envuelve el `await createNoteOption(...)`. En Flutter Web
  /// release eso se traducia en una pantalla en blanco sin SnackBar (el
  /// ErrorWidget por defecto es casi invisible), exactamente el sintoma
  /// reportado. Ver tambien `main.dart` (ErrorWidget.builder global) para
  /// que, si volviera a ocurrir un caso no cubierto por esta funcion, se
  /// muestre un mensaje de diagnostico en vez de pantalla en blanco.
  static NoteOptionCatalogItem? fromJsonOrNull(Map<String, dynamic> json) {
    final id = json['id'];
    final label = json['label'];
    final field = json['field'];
    final createdBy = json['created_by'];
    final organizationId = json['organization_id'];
    final isActive = json['is_active'];
    final kuraTagRaw = json['kura_tag'];
    // Cada campo se valida por tipo real (`is`) en vez de forzar un cast
    // (`as`), precisamente porque un cast fallido es lo que causaba el
    // TypeError no capturado que este metodo existe para evitar.
    if (id is! String || id.isEmpty) return null;
    if (label is! String) return null;
    if (field != null && field is! String) return null;
    if (createdBy != null && createdBy is! String) return null;
    if (organizationId != null && organizationId is! String) return null;
    if (isActive != null && isActive is! bool) return null;
    if (kuraTagRaw != null && kuraTagRaw is! String) return null;
    return NoteOptionCatalogItem(
      id: id,
      field: NoteOptionFieldDb.fromDb(field as String?) ??
          NoteOptionField.careType,
      label: label,
      isActive: isActive as bool? ?? true,
      createdBy: createdBy as String?,
      organizationId: organizationId as String?,
      kuraTag: KuraTagDb.fromDb(kuraTagRaw as String?),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'field': field.dbValue,
        'label': label,
        'is_active': isActive,
        'created_by': createdBy,
        'organization_id': organizationId,
        'kura_tag': kuraTag?.dbValue,
      };
}
