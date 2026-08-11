import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

/// Prioridad con la que una escala se ofrece tras evaluar los factores de riesgo.
enum ScalePriority { obligatoria, sugerida }

/// Una escala que aplica para un paciente, según el motor de aplicabilidad.
class ApplicableScale {
  final String scaleId;
  final String label;
  final ScalePriority priority;
  final bool implemented; // ¿hay captura construida ya?
  final int score; // suma de pesos de los factores de riesgo presentes
  final List<String> matchedFactors; // factores que contribuyeron (ids)
  const ApplicableScale({
    required this.scaleId,
    required this.label,
    required this.priority,
    required this.implemented,
    this.score = 0,
    this.matchedFactors = const [],
  });
}

/// Un grupo del cuestionario de factores de riesgo (para armar la hoja).
class QuestionnaireGroup {
  final String group;
  final List<String> factors; // ids de factor
  const QuestionnaireGroup(this.group, this.factors);
}

/// Factor con peso dentro de la regla de una escala.
class _WeightedFactor {
  final String factor;
  final int weight;
  const _WeightedFactor(this.factor, this.weight);
  factory _WeightedFactor.fromJson(Map<String, dynamic> j) =>
      _WeightedFactor(j['factor'] as String, (j['weight'] as num?)?.toInt() ?? 0);
}

/// Regla declarativa de aplicabilidad POR PESO (asset scale_applicability.json v0.2).
class _ScaleRule {
  final String scaleId;
  final String label;
  final bool implemented;
  final List<String> gateAny; // al menos uno presente para considerar la escala
  final List<String> trigger; // cualquiera presente => obligatoria
  final List<_WeightedFactor> factors;
  final int sugeridaMin;
  final int obligatoriaMin;
  const _ScaleRule({
    required this.scaleId,
    required this.label,
    required this.implemented,
    required this.gateAny,
    required this.trigger,
    required this.factors,
    required this.sugeridaMin,
    required this.obligatoriaMin,
  });

  factory _ScaleRule.fromJson(Map<String, dynamic> j) {
    final th = (j['thresholds'] as Map?)?.cast<String, dynamic>() ?? const {};
    List<String> strs(dynamic v) =>
        ((v as List?) ?? const []).map((e) => e.toString()).toList();
    return _ScaleRule(
      scaleId: j['scale_id'] as String,
      label: (j['label'] as String?) ?? j['scale_id'] as String,
      implemented: j['implemented'] as bool? ?? false,
      gateAny: strs(j['gate_any']),
      trigger: strs(j['trigger']),
      factors: ((j['factors'] as List?) ?? const [])
          .map((e) => _WeightedFactor.fromJson((e as Map).cast<String, dynamic>()))
          .toList(),
      sugeridaMin: (th['sugerida'] as num?)?.toInt() ?? 1,
      obligatoriaMin: (th['obligatoria'] as num?)?.toInt() ?? 1,
    );
  }
}

/// Contexto del paciente para evaluar aplicabilidad: datos del expediente [R]
/// (comorbilidades, heridas, Braden, edad, estancia, unidad) + las respuestas
/// del CUESTIONARIO inicial [Q] (factores observables que llena enfermería). El
/// motor normaliza todo a un set plano de "factores de riesgo" y con eso puntúa.
class ScaleEvalContext {
  final Set<String> comorbilidades; // enum.name en minúsculas (status presente)
  final Set<String> woundEtiologies; // etiologías de heridas activas (enum.name)
  final bool hasActiveWound;
  final int? braden; // total de la última valoración
  final int? bradenHumedad; // subescala humedad
  final Map<String, bool> triage; // factor Q → bool
  final String? unit; // servicio/unidad del internamiento
  final int? age; // edad del paciente
  final int? admissionDays; // días de estancia (desde el internamiento activo)

  const ScaleEvalContext({
    this.comorbilidades = const {},
    this.woundEtiologies = const {},
    this.hasActiveWound = false,
    this.braden,
    this.bradenHumedad,
    this.triage = const {},
    this.unit,
    this.age,
    this.admissionDays,
  });
}

/// Motor de aplicabilidad de escalas POR FACTORES DE RIESGO: a partir de los
/// factores del paciente (expediente + cuestionario) puntúa cada escala y decide
/// cuáles se deben realizar (obligatoria/sugerida). Routing declarativo y
/// parametrizable (asset); pesos y umbrales son BORRADOR pendiente de validación
/// clínica de María.
class ScaleApplicabilityCatalog {
  final String version;
  final List<_ScaleRule> _rules;
  final Map<String, String> factorLabels;
  final List<QuestionnaireGroup> questionnaire;
  const ScaleApplicabilityCatalog._(
      this.version, this._rules, this.factorLabels, this.questionnaire);

  /// Umbral (días) para considerar la estancia hospitalaria "prolongada".
  /// BORRADOR (pendiente de validación clínica).
  static const int estanciaProlongadaDias = 14;

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
    final labels = ((json['factor_labels'] as Map?) ?? const {})
        .map((k, v) => MapEntry(k.toString(), v.toString()));
    final groups = ((json['questionnaire'] as List?) ?? const [])
        .map((e) {
          final m = (e as Map).cast<String, dynamic>();
          return QuestionnaireGroup(
            (m['group'] as String?) ?? '',
            ((m['factors'] as List?) ?? const [])
                .map((f) => f.toString())
                .toList(),
          );
        })
        .toList();
    final catalog = ScaleApplicabilityCatalog._(
        (json['version'] as String?) ?? '', rules, labels, groups);
    _cached = catalog;
    return catalog;
  }

  /// Todas las escalas del catálogo (id + etiqueta), para configurarlas (p. ej.
  /// el admin elige cuáles habilitar en su centro).
  List<({String scaleId, String label})> get scales =>
      _rules.map((r) => (scaleId: r.scaleId, label: r.label)).toList();

  /// Etiqueta legible de un factor de riesgo (o el id si no hay etiqueta).
  String factorLabel(String id) => factorLabels[id] ?? id;

  /// Normaliza el contexto del paciente a un set plano de FACTORES DE RIESGO
  /// (expediente [R] + cuestionario [Q]). Público para reutilizarlo en el plan
  /// de cuidados (pre-marcado) y para explicar "por qué" aplica una escala.
  Set<String> factorsFor(ScaleEvalContext c) {
    final f = <String>{};

    // --- Cuestionario [Q]: cada respuesta true es un factor ---
    c.triage.forEach((k, v) {
      if (v) f.add(k);
    });

    // --- Comorbilidades [R] (enum.name en minúsculas → id de factor) ---
    const comorbToFactor = <String, String>{
      'diabetesmellitus': 'diabetes_mellitus',
      'enfermedadarterialperiferica': 'evp',
      'insuficienciavenosacronica': 'ivc',
      'insuficienciarenalcronica': 'irc',
      'enfermedadcardiovascular': 'enf_cardiovascular',
      'inmunosupresion': 'inmunosupresion',
      'obesidad': 'obesidad',
      'tabaquismoactivo': 'tabaquismo',
      'malnutricion': 'malnutricion',
      'movilidadreducida': 'movilidad_reducida',
    };
    for (final c0 in c.comorbilidades) {
      final id = comorbToFactor[c0];
      if (id != null) f.add(id);
    }

    // --- Heridas activas [R] ---
    if (c.hasActiveWound) f.add('has_active_wound');
    const etioToFactor = <String, String>{
      'lpp': 'etio_lpp',
      'vascular': 'etio_vascular',
      'quirurgica': 'etio_quirurgica',
      'pieDiabetico': 'etio_pie_diabetico',
    };
    for (final e in c.woundEtiologies) {
      final id = etioToFactor[e];
      if (id != null) f.add(id);
    }

    // --- Edad [R] ---
    final age = c.age;
    if (age != null) {
      if (age >= 65) f.add('edad_avanzada');
      if (age >= 80) f.add('edad_muy_avanzada');
      if (age < 6) f.add('edad_pediatrica');
    }

    // --- Braden [R] ---
    final b = c.braden;
    if (b != null) {
      if (b <= 17) f.add('braden_riesgo');
      if (b <= 12) f.add('braden_bajo');
    }
    final hum = c.bradenHumedad;
    if (hum != null && hum <= 2) f.add('incontinencia');

    // --- Estancia / unidad [R] ---
    if (c.admissionDays != null &&
        c.admissionDays! >= estanciaProlongadaDias) {
      f.add('estancia_prolongada');
    }
    final u = c.unit?.toLowerCase() ?? '';
    if (u.contains('uci') || u.contains('terapia intensiva')) {
      f.add('unit_uci');
    }

    return f;
  }

  /// Escalas aplicables para el contexto dado (obligatorias primero, luego por
  /// puntaje descendente).
  List<ApplicableScale> evaluate(ScaleEvalContext c) {
    final present = factorsFor(c);
    final out = <ApplicableScale>[];
    for (final r in _rules) {
      // Gate: si hay precondición y ningún factor de gate está presente, ni se
      // considera la escala.
      if (r.gateAny.isNotEmpty && !r.gateAny.any(present.contains)) continue;

      final triggered = r.trigger.any(present.contains);
      var score = 0;
      final matched = <String>[];
      for (final wf in r.factors) {
        if (present.contains(wf.factor)) {
          score += wf.weight;
          matched.add(wf.factor);
        }
      }
      // Los factores de trigger presentes también se listan como "por qué".
      for (final t in r.trigger) {
        if (present.contains(t) && !matched.contains(t)) matched.add(t);
      }

      ScalePriority? priority;
      if (triggered || score >= r.obligatoriaMin) {
        priority = ScalePriority.obligatoria;
      } else if (score >= r.sugeridaMin) {
        priority = ScalePriority.sugerida;
      }
      if (priority == null) continue;

      out.add(ApplicableScale(
        scaleId: r.scaleId,
        label: r.label,
        priority: priority,
        implemented: r.implemented,
        score: score,
        matchedFactors: matched,
      ));
    }
    out.sort((a, b) {
      final p = a.priority.index.compareTo(b.priority.index);
      if (p != 0) return p;
      return b.score.compareTo(a.score);
    });
    return out;
  }
}
