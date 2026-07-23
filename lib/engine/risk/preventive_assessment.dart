import 'prevention_risk_engine.dart' show PreventionRulesCatalog, ScheduledActionSpec;

/// Nivel de movilidad (pregunta 1 del cuestionario unificado). Determina la
/// frecuencia de cambios posturales cuando no hay una banda de Braden vigente.
enum Movilidad { independiente, conAyuda, sillaRuedas, encamado }

extension MovilidadX on Movilidad {
  String get label {
    switch (this) {
      case Movilidad.independiente:
        return 'Se mueve solo (independiente)';
      case Movilidad.conAyuda:
        return 'Camina o se mueve con ayuda';
      case Movilidad.sillaRuedas:
        return 'En silla de ruedas';
      case Movilidad.encamado:
        return 'Encamado';
    }
  }
}

/// Respuestas del cuestionario preventivo unificado (autónomo, adaptativo).
class PreventiveAnswers {
  Movilidad? mobility;
  bool? moisture; // piel húmeda por incontinencia/sudoración
  bool? eatsWell; // come bien (>50%)
  bool? nonBlanchingRedness; // eritema que NO blanquea en zonas de apoyo
  bool? hasWound;
  bool? infectionSigns; // solo aplica si hasWound == true

  PreventiveAnswers();

  /// El cuestionario está completo cuando movilidad + las 4 preguntas base están
  /// respondidas (y, si hay herida, sus signos de infección).
  bool get isComplete =>
      mobility != null &&
      moisture != null &&
      eatsWell != null &&
      nonBlanchingRedness != null &&
      hasWound != null &&
      (hasWound == false || infectionSigns != null);
}

/// Plan preventivo resultante: actividades AGENDABLES (con su cadencia) +
/// "signos a vigilar / recomendaciones" (no agendables).
class PreventivePlan {
  final List<ScheduledActionSpec> activities;
  final List<String> watchSigns;
  const PreventivePlan({required this.activities, required this.watchSigns});

  bool get isEmpty => activities.isEmpty && watchSigns.isEmpty;
}

/// Construye el plan preventivo concreto a partir de las respuestas del
/// cuestionario. `braden` (opcional) REFINA la frecuencia de cambios posturales
/// si hay una valoración vigente; si no, se deriva de la movilidad. Las
/// cadencias (título + cada-cuántas-horas por id de acción) se toman del asset
/// vía `catalog` (fuente de verdad; María las calibra sin recompilar).
PreventivePlan buildPreventivePlan(
  PreventiveAnswers a, {
  int? braden,
  required PreventionRulesCatalog catalog,
}) {
  final activities = <ScheduledActionSpec>[];
  final watch = <String>[];

  ScheduledActionSpec? spec(String id) {
    final c = catalog.cadenceFor(id);
    if (c == null) return null;
    return ScheduledActionSpec(
      ruleId: 'assessment',
      actionId: id,
      actionLabel: c.title,
      title: c.title,
      everyHours: c.everyHours,
    );
  }

  // 1) Frecuencia de cambios posturales + nivel muy alto.
  String? posturalId;
  var veryHigh = false;
  if (braden != null) {
    // La banda de Braden manda si hay valoración vigente.
    if (braden <= 12) {
      posturalId = 'cambios_2h_registro';
      veryHigh = braden <= 9;
    } else if (braden <= 17) {
      posturalId = 'cambios_2_3h';
    } else {
      posturalId = null; // 18–23: sin cambios programados (solo observación)
    }
  } else {
    switch (a.mobility) {
      case Movilidad.encamado:
        posturalId = 'cambios_2h_registro';
        veryHigh = true;
        break;
      case Movilidad.sillaRuedas:
        posturalId = 'cambios_2h_registro';
        break;
      case Movilidad.conAyuda:
        posturalId = 'cambios_2_3h';
        break;
      case Movilidad.independiente:
      case null:
        posturalId = null;
        break;
    }
  }

  final hasLppRisk =
      posturalId != null || a.moisture == true || a.nonBlanchingRedness == true;

  if (posturalId != null) {
    final s = spec(posturalId);
    if (s != null) activities.add(s);
  }
  if (hasLppRisk) {
    for (final id in const ['agho', 'aposito_preventivo', 'exam_piel_diario']) {
      final s = spec(id);
      if (s != null) activities.add(s);
    }
    if (veryHigh) {
      final s = spec('valoracion_piel_completa_diaria');
      if (s != null) activities.add(s);
    }
  }
  if (a.moisture == true) {
    final s = spec('control_humedad');
    if (s != null) activities.add(s);
  }

  // 2) Signos a vigilar / recomendaciones (no agendables).
  if (a.eatsWell == false) {
    watch.add(
        'Nutrición: valoración nutricional (MNA), ajuste proteico 1.25–1.5 g/kg/día '
        'y valorar interconsulta a nutrición.');
  }
  if (a.nonBlanchingRedness == true) {
    watch.add(
        'Posible lesión por presión (eritema que NO blanquea): valorar y estadificar '
        'la piel, y notificar al responsable del caso.');
  }
  if (a.hasWound == true && a.infectionSigns == true) {
    watch.add(
        'Signos de infección de la herida (continuo IWII 2022): escalar el manejo, '
        'valorar cultivo/antibiótico y considerar reporte como evento adverso.');
  }

  return PreventivePlan(activities: activities, watchSigns: watch);
}
