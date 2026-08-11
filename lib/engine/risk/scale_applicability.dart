import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

/// Prioridad con la que una escala se ofrece tras el triage.
enum ScalePriority { obligatoria, sugerida }

ScalePriority _priorityFromDb(String? s) =>
    s == 'obligatoria' ? ScalePriority.obligatoria : ScalePriority.sugerida;

/// Una escala que aplica para un paciente, según el motor de aplicabilidad.
class ApplicableScale {
  final String scaleId;
  final String label;
  final ScalePriority priority;
  final bool implemented; // ¿hay captura construida ya?
  const ApplicableScale({
    required this.scaleId,
    required this.label,
    required this.priority,
    required this.implemented,
  });
}

/// Regla declarativa de aplicabilidad de una escala (asset scale_applicability.json).
class _ScaleRule {
  final String scaleId;
  final String label;
  final ScalePriority priority;
  final bool implemented;
  final Map<String, dynamic> when;
  const _ScaleRule(
      this.scaleId, this.label, this.priority, this.implemented, this.when);

  factory _ScaleRule.fromJson(Map<String, dynamic> j) => _ScaleRule(
        j['scale_id'] as String,
        (j['label'] as String?) ?? j['scale_id'] as String,
        _priorityFromDb(j['priority'] as String?),
        j['implemented'] as bool? ?? false,
        (j['when'] as Map?)?.cast<String, dynamic>() ?? const {},
      );
}

/// Señales del paciente que evalúan las reglas de aplicabilidad. Se arman con
/// datos del expediente (comorbilidades, heridas, Braden, internamiento) + las
/// respuestas del TRIAGE (booleanos que no se derivan del expediente).
class ScaleEvalContext {
  final Set<String> comorbilidades; // códigos presentes (minúsculas)
  final Set<String> woundEtiologies; // etiologías de heridas activas (enum.name)
  final bool hasActiveWound;
  final int? braden; // total de la última valoración
  final int? bradenHumedad; // subescala humedad
  final Map<String, bool> triage; // señal → bool
  final String? unit; // servicio/unidad del internamiento

  const ScaleEvalContext({
    this.comorbilidades = const {},
    this.woundEtiologies = const {},
    this.hasActiveWound = false,
    this.braden,
    this.bradenHumedad,
    this.triage = const {},
    this.unit,
  });
}

/// Motor de aplicabilidad de escalas: a partir de las señales del paciente
/// (triage + expediente) decide QUÉ escalas se deben realizar. Es routing puro,
/// declarativo y parametrizable (asset), en paralelo al motor de riesgo de
/// Braden. Núcleo LCRD (GLOBIAD/ISTAP/STAR/PUSH/RESVECH) cuelga de Braden; las
/// complementarias (Wagner/CEAP/…) se disparan por etiología/comorbilidad.
class ScaleApplicabilityCatalog {
  final String version;
  final List<_ScaleRule> _rules;
  const ScaleApplicabilityCatalog._(this.version, this._rules);

  static ScaleApplicabilityCatalog? _cached;

  static Future<ScaleApplicabilityCatalog> load({
    String assetPath = 'assets/engine/scale_applicability.json',
  }) async {
    if (_cached != null) return _cached!;
    final raw = await rootBundle.loadString(assetPath);
    final json = jsonDecode(raw) as Map<String, dynamic>;
    final rules = ((json['scales'] as List?) ?? const [])
        .map((e) => _ScaleRule.fromJson((e as Map).cast<String, dynamic>()))
        .toList();
    final catalog = ScaleApplicabilityCatalog._(
        (json['version'] as String?) ?? '', rules);
    _cached = catalog;
    return catalog;
  }

  /// Escalas aplicables para el contexto dado (obligatorias primero).
  List<ApplicableScale> evaluate(ScaleEvalContext c) {
    final out = <ApplicableScale>[];
    for (final r in _rules) {
      if (_matches(r.when, c)) {
        out.add(ApplicableScale(
          scaleId: r.scaleId,
          label: r.label,
          priority: r.priority,
          implemented: r.implemented,
        ));
      }
    }
    out.sort((a, b) => a.priority.index.compareTo(b.priority.index));
    return out;
  }

  bool _matches(Map<String, dynamic> when, ScaleEvalContext c) {
    for (final e in when.entries) {
      if (!_predicate(e.key, e.value, c)) return false;
    }
    return true;
  }

  bool _predicate(String key, dynamic val, ScaleEvalContext c) {
    switch (key) {
      case 'comorbilidad':
        return c.comorbilidades.contains((val as String).toLowerCase());
      case 'woundEtiology':
        return c.woundEtiologies.contains(val as String);
      case 'hasActiveWound':
        return c.hasActiveWound == (val as bool);
      case 'bradenMax':
        return c.braden != null && c.braden! <= (val as num).toInt();
      case 'bradenHumedadMax':
        return c.bradenHumedad != null &&
            c.bradenHumedad! <= (val as num).toInt();
      case 'triage':
        return c.triage[val as String] == true;
      case 'unitIn':
        return c.unit != null &&
            (val as List).map((e) => e.toString()).contains(c.unit);
      case 'any':
        return (val as List)
            .any((sub) => _matches((sub as Map).cast<String, dynamic>(), c));
      default:
        return true; // predicado desconocido → permisivo
    }
  }
}
