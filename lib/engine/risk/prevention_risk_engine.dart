import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;

import '../models/kura_engine_enums.dart';
import '../../models/patient.dart';
import '../../models/wound.dart';

/// Frente de la alerta preventiva.
enum RiskDimension { lpp, complicacion }

extension RiskDimensionX on RiskDimension {
  String get label => switch (this) {
        RiskDimension.lpp => 'Riesgo de lesión por presión',
        RiskDimension.complicacion => 'Riesgo de complicación',
      };

  static RiskDimension fromDb(String s) => RiskDimension.values.firstWhere(
        (e) => e.name == s,
        orElse: () => RiskDimension.complicacion,
      );
}

/// Severidad de una alerta individual.
enum RiskSeverity { alto, medio, bajo }

extension RiskSeverityX on RiskSeverity {
  String get label => switch (this) {
        RiskSeverity.alto => 'Alto',
        RiskSeverity.medio => 'Medio',
        RiskSeverity.bajo => 'Bajo',
      };

  int get weight => switch (this) {
        RiskSeverity.alto => 3,
        RiskSeverity.medio => 2,
        RiskSeverity.bajo => 1,
      };

  static RiskSeverity fromDb(String s) => RiskSeverity.values.firstWhere(
        (e) => e.name == s,
        orElse: () => RiskSeverity.bajo,
      );
}

/// Nivel de riesgo global del paciente (derivado de sus alertas).
enum RiskLevel { alto, medio, bajo, sinRiesgo }

extension RiskLevelX on RiskLevel {
  String get label => switch (this) {
        RiskLevel.alto => 'Riesgo alto',
        RiskLevel.medio => 'Riesgo medio',
        RiskLevel.bajo => 'Riesgo bajo',
        RiskLevel.sinRiesgo => 'Sin riesgo detectado',
      };
}

/// Una acción preventiva concreta sugerida por una regla (registrable con
/// fecha/autor en preventive_action_log). `id` es estable dentro de la regla.
class PreventiveAction {
  final String id;
  final String label;
  const PreventiveAction({required this.id, required this.label});

  factory PreventiveAction.fromJson(Map<String, dynamic> j) => PreventiveAction(
        id: j['id'] as String,
        label: j['label'] as String,
      );
}

/// Una alerta preventiva disparada por una regla del catálogo. Incluye la guía
/// para el profesional: `questions` (qué preguntarse) y `actions` (qué hacer).
class PreventionAlert {
  final String id; // = rule id
  final RiskDimension dimension;
  final RiskSeverity severity;
  final String message;
  final List<String> questions;
  final List<PreventiveAction> actions;

  const PreventionAlert({
    required this.id,
    required this.dimension,
    required this.severity,
    required this.message,
    this.questions = const [],
    this.actions = const [],
  });
}

/// Resultado de evaluar el riesgo de un paciente: nivel global + alertas.
class PreventionRiskResult {
  final RiskLevel level;
  final List<PreventionAlert> alerts;

  const PreventionRiskResult({required this.level, required this.alerts});

  static const empty =
      PreventionRiskResult(level: RiskLevel.sinRiesgo, alerts: []);

  List<PreventionAlert> get lpp =>
      alerts.where((a) => a.dimension == RiskDimension.lpp).toList();
  List<PreventionAlert> get complicacion =>
      alerts.where((a) => a.dimension == RiskDimension.complicacion).toList();

  bool get hasAlerts => alerts.isNotEmpty;
}

/// Regla declarativa del asset `prevention_rules.json`.
class _Rule {
  final String id;
  final RiskDimension dimension;
  final RiskSeverity severity;
  final String message;
  final List<String> questions;
  final List<PreventiveAction> actions;
  final Map<String, dynamic> when;

  const _Rule({
    required this.id,
    required this.dimension,
    required this.severity,
    required this.message,
    required this.questions,
    required this.actions,
    required this.when,
  });

  factory _Rule.fromJson(Map<String, dynamic> j) => _Rule(
        id: j['id'] as String,
        dimension: RiskDimensionX.fromDb(j['dimension'] as String),
        severity: RiskSeverityX.fromDb(j['severity'] as String),
        message: j['message'] as String,
        questions: ((j['questions'] as List?) ?? const [])
            .map((e) => e.toString())
            .toList(),
        actions: ((j['actions'] as List?) ?? const [])
            .map((e) => PreventiveAction.fromJson((e as Map).cast<String, dynamic>()))
            .toList(),
        when: (j['when'] as Map?)?.cast<String, dynamic>() ?? const {},
      );
}

/// Motor de prevención/riesgo (capa DOCUMENTAL/asesor): aplica el catálogo de
/// reglas configurable a las características del paciente y devuelve las alertas
/// preventivas + el nivel de riesgo. NO altera el motor de tratamiento.
///
/// Reglas cargadas desde el asset (borrador PENDIENTE de validación de María).
/// Patrón de carga igual que [KuraPrognosisModel]/[KuraClinicalAdjustments].
class PreventionRulesCatalog {
  final String version;
  final List<_Rule> _rules;

  const PreventionRulesCatalog._(this.version, this._rules);

  static PreventionRulesCatalog? _cached;

  static Future<PreventionRulesCatalog> load({
    String assetPath = 'assets/engine/prevention_rules.json',
  }) async {
    if (_cached != null) return _cached!;
    final raw = await rootBundle.loadString(assetPath);
    final json = jsonDecode(raw) as Map<String, dynamic>;
    final rules = ((json['rules'] as List?) ?? const [])
        .map((e) => _Rule.fromJson((e as Map).cast<String, dynamic>()))
        .toList();
    final catalog =
        PreventionRulesCatalog._((json['version'] as String?) ?? '', rules);
    _cached = catalog;
    return catalog;
  }

  /// Evalúa el riesgo de un paciente. `comorbilidadesPresentes` son solo las
  /// marcadas "presente"; `latestBraden` es la última valoración (o null);
  /// `activeWounds` sus heridas activas; `deterioration` si alguna herida
  /// muestra deterioro objetivo respecto a la valoración previa.
  PreventionRiskResult evaluate({
    required Patient patient,
    required Set<Comorbilidad> comorbilidadesPresentes,
    int? latestBraden,
    required List<Wound> activeWounds,
    bool deterioration = false,
  }) {
    final comorb = comorbilidadesPresentes.map((c) => c.name).toSet();
    final etiologias = activeWounds.map((w) => w.etiology.name).toSet();
    final hasWound = activeWounds.isNotEmpty;

    final alerts = <PreventionAlert>[];
    for (final r in _rules) {
      if (_matches(r.when, patient, comorb, latestBraden, hasWound, etiologias,
          deterioration)) {
        alerts.add(PreventionAlert(
          id: r.id,
          dimension: r.dimension,
          severity: r.severity,
          message: r.message,
          questions: r.questions,
          actions: r.actions,
        ));
      }
    }
    return PreventionRiskResult(level: _levelFrom(alerts), alerts: alerts);
  }

  /// Una regla dispara si TODAS las condiciones presentes en `when` se cumplen.
  /// Condiciones desconocidas se ignoran (el asset documenta las soportadas).
  bool _matches(
    Map<String, dynamic> when,
    Patient patient,
    Set<String> comorb,
    int? braden,
    bool hasWound,
    Set<String> etiologias,
    bool deterioration,
  ) {
    if (when.containsKey('bradenMin')) {
      if (braden == null || braden < (when['bradenMin'] as num).toInt()) {
        return false;
      }
    }
    if (when.containsKey('bradenMax')) {
      if (braden == null || braden > (when['bradenMax'] as num).toInt()) {
        return false;
      }
    }
    if (when.containsKey('comorbilidad')) {
      if (!comorb.contains(when['comorbilidad'] as String)) return false;
    }
    if (when.containsKey('hasActiveWound')) {
      if (hasWound != (when['hasActiveWound'] as bool)) return false;
    }
    if (when.containsKey('mobilityIn')) {
      final list = (when['mobilityIn'] as List).map((e) => e.toString());
      if (patient.mobility == null || !list.contains(patient.mobility)) {
        return false;
      }
    }
    if (when.containsKey('fragile')) {
      if (patient.fragilePatient != (when['fragile'] as bool)) return false;
    }
    if (when.containsKey('bmiMax')) {
      final bmi = patient.bmi;
      if (bmi == null || bmi > (when['bmiMax'] as num).toDouble()) return false;
    }
    if (when.containsKey('woundEtiology')) {
      if (!etiologias.contains(when['woundEtiology'] as String)) return false;
    }
    if (when.containsKey('deterioration')) {
      if (deterioration != (when['deterioration'] as bool)) return false;
    }
    return true;
  }

  RiskLevel _levelFrom(List<PreventionAlert> alerts) {
    if (alerts.isEmpty) return RiskLevel.sinRiesgo;
    final maxWeight =
        alerts.map((a) => a.severity.weight).reduce((a, b) => a > b ? a : b);
    return switch (maxWeight) {
      3 => RiskLevel.alto,
      2 => RiskLevel.medio,
      _ => RiskLevel.bajo,
    };
  }
}
