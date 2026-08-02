import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

import '../models/kura_engine_enums.dart';

/// Parámetros clínicos del motor de reglas de tratamiento (8.4), cargados
/// desde `assets/engine/clinical/*.json` en vez de estar embebidos como
/// literales en el código.
///
/// Objetivo (Fase A del refactor "data-driven y auditable"): que todo umbral,
/// mapeo y banda de compresión con relevancia clínica viva en datos con
/// procedencia (source.protocolo/rationale/reviewed_by/reviewed_date), de modo
/// que María pueda auditarlos y ajustarlos sin tocar Dart, y que un cambio de
/// valor sea detectable por los golden.
///
/// Uso: se carga una sola vez al arrancar la app (`ClinicalParams.loadFromAssets()`)
/// y en los tests (`setUpAll`), y luego se consulta vía el singleton
/// `ClinicalParams.instance`. Si se consulta sin haber cargado, lanza para
/// evitar caer silenciosamente en valores por defecto.
class ClinicalParams {
  ClinicalParams._({
    required this.version,
    required this.thresholds,
    required this.compressionBands,
    required this.wagnerDescarga,
    required this.wuwhsManejo,
    required this.compresionProducto,
  });

  final String version;

  /// Umbrales numéricos por clave (ver [_ThresholdKey]).
  final Map<String, num> thresholds;

  /// Bandas de compresión por ITB, ordenadas de menor a mayor.
  final List<CompressionBand> compressionBands;

  /// Mapa grado Wagner (`WagnerGrade.name`) -> dispositivo de descarga.
  final Map<String, String> wagnerDescarga;

  /// Mapa grado WUWHS (`WuwhsGrade.name`) -> manejo de herida quirúrgica.
  final Map<String, String> wuwhsManejo;

  /// Mapa banda de compresión (`ItbCompresionBand.name`) -> producto (mmHg).
  /// Solo cubre las bandas que producen un componente de régimen
  /// (fuerte/precaucion/reducida/na); incompresible/noAplica generan alertas.
  final Map<String, String> compresionProducto;

  // ------------------------------------------------------------------
  // Singleton + carga
  // ------------------------------------------------------------------

  static ClinicalParams? _instance;

  /// Instancia global. Lanza [StateError] si no se ha cargado.
  static ClinicalParams get instance {
    final i = _instance;
    if (i == null) {
      throw StateError(
        'ClinicalParams no cargado. Llama a ClinicalParams.loadFromAssets() '
        'al arrancar la app (o load*() en setUpAll de los tests) antes de usar '
        'el motor de reglas.',
      );
    }
    return i;
  }

  /// Alias corto para el uso interno del motor.
  static ClinicalParams get I => instance;

  static bool get isLoaded => _instance != null;

  /// Reemplaza la instancia global (usado por la carga y por los tests).
  static void register(ClinicalParams params) => _instance = params;

  /// Solo para tests: descarga la instancia global.
  static void resetForTest() => _instance = null;

  /// Carga desde los assets empaquetados (producción / runtime Flutter).
  static Future<ClinicalParams> loadFromAssets() async {
    if (_instance != null) return _instance!;
    final thresholds =
        await rootBundle.loadString('assets/engine/clinical/thresholds.json');
    final archetypes =
        await rootBundle.loadString('assets/engine/clinical/archetypes.json');
    final params = fromJsonStrings(
      thresholdsJson: thresholds,
      archetypesJson: archetypes,
    );
    register(params);
    return params;
  }

  /// Construye (y valida) desde el contenido crudo de ambos JSON. Usado por la
  /// carga de assets y por los tests que leen los archivos con `dart:io`.
  static ClinicalParams fromJsonStrings({
    required String thresholdsJson,
    required String archetypesJson,
  }) {
    final t = jsonDecode(thresholdsJson);
    final a = jsonDecode(archetypesJson);
    if (t is! Map<String, dynamic>) {
      throw const ClinicalParamsException('thresholds.json: raíz no es objeto.');
    }
    if (a is! Map<String, dynamic>) {
      throw const ClinicalParamsException('archetypes.json: raíz no es objeto.');
    }
    return _parseAndValidate(thresholds: t, archetypes: a);
  }

  // ------------------------------------------------------------------
  // Accesores tipados (leídos por el motor y por KuraEngineInput)
  // ------------------------------------------------------------------

  num _t(String key) {
    final v = thresholds[key];
    if (v == null) {
      throw ClinicalParamsException('Umbral faltante: $key');
    }
    return v;
  }

  /// Esfacelo+necrosis mínimo (%) para desbridar.
  double get debridementCompositionMinPct =>
      _t('debridement_composition_min_pct').toDouble();

  /// Necrosis mínima (%) considerada "extensa" (interconsulta a cirugía).
  double get necrosisExtensaMinPct => _t('necrosis_extensa_min_pct').toDouble();

  /// Profundidad mínima (cm) que exige relleno de cavidad.
  double get depthRellenoMinCm => _t('depth_relleno_min_cm').toDouble();

  /// Número mínimo de factores locales para sospecha de infección local.
  int get infeccionLocalMinFactores =>
      _t('infeccion_local_min_factores').toInt();

  /// Longitud mínima de túnel (cm) que exige referencia.
  double get tunelReferenciaMinCm => _t('tunel_referencia_min_cm').toDouble();

  /// Braden máximo (inclusive) para tratamiento a cargo de la clínica.
  int get bradenACargoClinicaMax => _t('braden_a_cargo_clinica_max').toInt();

  /// Braden máximo (inclusive) para la etiqueta "riesgo alto/muy alto".
  int get bradenAltoMuyAltoMax => _t('braden_alto_muy_alto_max').toInt();

  /// ITB por encima del cual las arterias se consideran incompresibles.
  double get abiIncompresibleAbove => _t('abi_incompresible_above').toDouble();

  /// ITB mínimo (inclusive) para perfusión "alta".
  double get abiHighMin => _t('abi_high_min').toDouble();

  /// ITB mínimo (inclusive) para perfusión "moderada" (por debajo = isquemia
  /// crítica).
  double get abiModMin => _t('abi_mod_min').toDouble();

  /// Albúmina (g/dL) mínima para categoría normal.
  double get albuminaNormalMin => _t('albumina_normal_min').toDouble();

  /// Albúmina (g/dL) mínima para déficit leve (por debajo = déficit).
  double get albuminaMildMin => _t('albumina_mild_min').toDouble();

  /// Banda de compresión para un ITB medido [v]. Recorre las bandas de datos.
  ItbCompresionBand itbBandFor(double v) {
    for (final b in compressionBands) {
      if (b.contains(v)) return b.band;
    }
    // Inalcanzable si las bandas cubren el dominio (validado en carga).
    throw ClinicalParamsException('ITB $v sin banda de compresión.');
  }

  /// Dispositivo de descarga para un grado Wagner.
  String descargaFor(WagnerGrade g) {
    final s = wagnerDescarga[g.name];
    if (s == null) {
      throw ClinicalParamsException('Sin descarga para Wagner ${g.name}.');
    }
    return s;
  }

  /// Manejo de herida quirúrgica para un grado WUWHS.
  String manejoFor(WuwhsGrade g) {
    final s = wuwhsManejo[g.name];
    if (s == null) {
      throw ClinicalParamsException('Sin manejo para WUWHS ${g.name}.');
    }
    return s;
  }

  /// Diferencias legibles (valor anterior → nuevo) entre estos parámetros y
  /// [next]. Se usa en la vista previa de una carga antes de aplicarla.
  List<String> diffTo(ClinicalParams next) {
    final out = <String>[];
    for (final k in {...thresholds.keys, ...next.thresholds.keys}) {
      final a = thresholds[k];
      final b = next.thresholds[k];
      if (a != b) out.add('umbral $k: ${a ?? '—'} → ${b ?? '—'}');
    }
    final aB = {for (final x in compressionBands) x.band.name: x.rangeLabel};
    final nB = {for (final x in next.compressionBands) x.band.name: x.rangeLabel};
    for (final k in {...aB.keys, ...nB.keys}) {
      if (aB[k] != nB[k]) out.add('banda $k: ${aB[k] ?? '—'} → ${nB[k] ?? '—'}');
    }
    void diffMap(String label, Map<String, String> a, Map<String, String> b) {
      for (final k in {...a.keys, ...b.keys}) {
        if (a[k] != b[k]) out.add('$label[$k]: ${a[k] ?? '—'} → ${b[k] ?? '—'}');
      }
    }
    diffMap('wagner', wagnerDescarga, next.wagnerDescarga);
    diffMap('wuwhs', wuwhsManejo, next.wuwhsManejo);
    diffMap('compresión', compresionProducto, next.compresionProducto);
    return out;
  }

  /// Producto de compresión (mmHg) para una banda. Lanza si la banda no
  /// produce un componente de régimen (incompresible/noAplica).
  String compresionProductoFor(ItbCompresionBand band) {
    final s = compresionProducto[band.name];
    if (s == null) {
      throw ClinicalParamsException(
        'Sin producto de compresión para la banda ${band.name}.',
      );
    }
    return s;
  }

  // ------------------------------------------------------------------
  // Parseo + validación de esquema/consistencia
  // ------------------------------------------------------------------

  static ClinicalParams _parseAndValidate({
    required Map<String, dynamic> thresholds,
    required Map<String, dynamic> archetypes,
  }) {
    final version = thresholds['version'];
    if (version is! String || version.isEmpty) {
      throw const ClinicalParamsException('thresholds.json: falta "version".');
    }

    // --- Umbrales: valor numérico + procedencia completa por entrada ---
    final rawThresholds = thresholds['thresholds'];
    if (rawThresholds is! Map<String, dynamic>) {
      throw const ClinicalParamsException(
        'thresholds.json: falta el objeto "thresholds".',
      );
    }
    final values = <String, num>{};
    rawThresholds.forEach((key, entry) {
      if (entry is! Map<String, dynamic>) {
        throw ClinicalParamsException('Umbral "$key" no es objeto.');
      }
      final v = entry['value'];
      if (v is! num) {
        throw ClinicalParamsException('Umbral "$key" sin "value" numérico.');
      }
      _validateSource(entry['source'], 'umbral "$key"');
      values[key] = v;
    });

    // Todos los umbrales requeridos presentes.
    for (final key in _requiredThresholdKeys) {
      if (!values.containsKey(key)) {
        throw ClinicalParamsException('Umbral requerido faltante: $key');
      }
    }

    // Cortes ordenados (consistencia): mod < high < incompresible; mild < normal.
    _requireAscending(values, [
      'abi_mod_min',
      'abi_high_min',
      'abi_incompresible_above',
    ]);
    _requireAscending(values, ['albumina_mild_min', 'albumina_normal_min']);

    // --- Bandas de compresión: contiguas, sin huecos ni traslapes ---
    final rawBands = thresholds['compression_bands'];
    if (rawBands is! Map<String, dynamic>) {
      throw const ClinicalParamsException(
        'thresholds.json: falta "compression_bands".',
      );
    }
    _validateSource(rawBands['source'], 'compression_bands');
    final bandsList = rawBands['bands'];
    if (bandsList is! List || bandsList.isEmpty) {
      throw const ClinicalParamsException(
        'compression_bands.bands vacío o ausente.',
      );
    }
    final bands = bandsList
        .map((e) => CompressionBand.fromJson(e as Map<String, dynamic>))
        .toList();
    _validateBandContinuity(bands);

    // --- Arquetipos (mapeos) + procedencia por mapa ---
    final maps = archetypes['maps'];
    if (maps is! Map<String, dynamic>) {
      throw const ClinicalParamsException('archetypes.json: falta "maps".');
    }
    final wagner = _parseMap(maps, 'wagner_descarga');
    final wuwhs = _parseMap(maps, 'wuwhs_manejo');
    final compresion = _parseMap(maps, 'compresion_producto');

    // Sin refs colgantes: cada grado/banda que el motor consulta existe.
    _requireKeys(wagner, WagnerGrade.values.map((e) => e.name), 'wagner_descarga');
    _requireKeys(wuwhs, WuwhsGrade.values.map((e) => e.name), 'wuwhs_manejo');
    _requireKeys(
      compresion,
      const ['fuerte', 'precaucion', 'reducida', 'na'],
      'compresion_producto',
    );

    return ClinicalParams._(
      version: version,
      thresholds: values,
      compressionBands: bands,
      wagnerDescarga: wagner,
      wuwhsManejo: wuwhs,
      compresionProducto: compresion,
    );
  }

  static const List<String> _requiredThresholdKeys = [
    'debridement_composition_min_pct',
    'necrosis_extensa_min_pct',
    'depth_relleno_min_cm',
    'infeccion_local_min_factores',
    'tunel_referencia_min_cm',
    'braden_a_cargo_clinica_max',
    'braden_alto_muy_alto_max',
    'abi_incompresible_above',
    'abi_high_min',
    'abi_mod_min',
    'albumina_normal_min',
    'albumina_mild_min',
  ];

  static void _validateSource(dynamic source, String ctx) {
    if (source is! Map<String, dynamic>) {
      throw ClinicalParamsException('$ctx: falta "source" (procedencia).');
    }
    for (final field in ['protocolo', 'rationale', 'reviewed_by', 'reviewed_date']) {
      final v = source[field];
      if (v is! String || v.trim().isEmpty) {
        throw ClinicalParamsException('$ctx: source.$field vacío o ausente.');
      }
    }
  }

  static void _requireAscending(Map<String, num> values, List<String> keys) {
    for (var i = 0; i < keys.length - 1; i++) {
      if (!(values[keys[i]]! < values[keys[i + 1]]!)) {
        throw ClinicalParamsException(
          'Cortes fuera de orden: ${keys[i]} (${values[keys[i]]}) debe ser '
          '< ${keys[i + 1]} (${values[keys[i + 1]]}).',
        );
      }
    }
  }

  static void _validateBandContinuity(List<CompressionBand> bands) {
    // La primera banda no tiene cota inferior; la última no tiene cota superior.
    if (bands.first.from != null) {
      throw const ClinicalParamsException(
        'La primera banda de compresión debe tener "from": null.',
      );
    }
    if (bands.last.to != null) {
      throw const ClinicalParamsException(
        'La última banda de compresión debe tener "to": null.',
      );
    }
    for (var i = 0; i < bands.length - 1; i++) {
      final cur = bands[i];
      final next = bands[i + 1];
      // Contigüidad: el techo de una == el piso de la siguiente.
      if (cur.to != next.from) {
        throw ClinicalParamsException(
          'Hueco/traslape en bandas de compresión entre ${cur.band.name} '
          '(to=${cur.to}) y ${next.band.name} (from=${next.from}).',
        );
      }
      // Inclusividad complementaria en la frontera: exactamente uno inclusivo.
      if (cur.toInclusive == next.fromInclusive) {
        throw ClinicalParamsException(
          'Frontera ambigua entre ${cur.band.name} y ${next.band.name}: '
          'exactamente uno de los extremos debe ser inclusivo.',
        );
      }
    }
  }

  static Map<String, String> _parseMap(Map<String, dynamic> maps, String key) {
    final node = maps[key];
    if (node is! Map<String, dynamic>) {
      throw ClinicalParamsException('archetypes.json: falta el mapa "$key".');
    }
    _validateSource(node['source'], 'mapa "$key"');
    final map = node['map'];
    if (map is! Map<String, dynamic>) {
      throw ClinicalParamsException('archetypes.json: "$key" sin "map".');
    }
    final out = <String, String>{};
    map.forEach((k, v) {
      if (v is! String || v.isEmpty) {
        throw ClinicalParamsException('archetypes.json: "$key.$k" no es texto.');
      }
      out[k] = v;
    });
    return out;
  }

  static void _requireKeys(
    Map<String, String> map,
    Iterable<String> required,
    String ctx,
  ) {
    for (final k in required) {
      if (!map.containsKey(k)) {
        throw ClinicalParamsException('$ctx: falta la clave "$k" (ref colgante).');
      }
    }
  }
}

/// Una banda de compresión por ITB. `from`/`to` null representan -inf/+inf.
class CompressionBand {
  const CompressionBand({
    required this.band,
    required this.from,
    required this.fromInclusive,
    required this.to,
    required this.toInclusive,
  });

  final ItbCompresionBand band;
  final double? from;
  final bool fromInclusive;
  final double? to;
  final bool toInclusive;

  bool contains(double v) {
    if (from != null) {
      if (fromInclusive ? v < from! : v <= from!) return false;
    }
    if (to != null) {
      if (toInclusive ? v > to! : v >= to!) return false;
    }
    return true;
  }

  /// Rango legible, mismo formato que el CSV (ej. `[0.9, 1.4]`, `(-inf, 0.6)`).
  String get rangeLabel {
    final lo = from == null ? '-inf' : '$from';
    final hi = to == null ? '+inf' : '$to';
    final lb = from == null ? '(' : (fromInclusive ? '[' : '(');
    final rb = to == null ? ')' : (toInclusive ? ']' : ')');
    return '$lb$lo, $hi$rb';
  }

  factory CompressionBand.fromJson(Map<String, dynamic> json) {
    final name = json['band'];
    final band = ItbCompresionBand.values.where((e) => e.name == name).firstOrNull;
    if (band == null) {
      throw ClinicalParamsException('Banda de compresión desconocida: $name');
    }
    return CompressionBand(
      band: band,
      from: (json['from'] as num?)?.toDouble(),
      fromInclusive: json['from_inclusive'] as bool? ?? false,
      to: (json['to'] as num?)?.toDouble(),
      toInclusive: json['to_inclusive'] as bool? ?? false,
    );
  }
}

/// Error de carga/validación de los parámetros clínicos.
class ClinicalParamsException implements Exception {
  const ClinicalParamsException(this.message);
  final String message;
  @override
  String toString() => 'ClinicalParamsException: $message';
}

extension _FirstOrNullExt<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
