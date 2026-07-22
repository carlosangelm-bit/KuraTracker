import 'package:flutter/material.dart';

import '../../core/theme/kura_theme.dart';
import '../../engine/risk/prevention_risk_engine.dart';

/// Color semántico (semáforo clínico) por nivel de riesgo del paciente.
Color riskLevelColor(RiskLevel level) {
  switch (level) {
    case RiskLevel.alto:
      return KuraColors.danger;
    case RiskLevel.medio:
      return KuraColors.warning;
    case RiskLevel.bajo:
      return KuraColors.success;
    case RiskLevel.sinRiesgo:
      return KuraColors.darkText;
  }
}

/// Color por severidad de una alerta individual.
Color riskSeverityColor(RiskSeverity severity) {
  switch (severity) {
    case RiskSeverity.alto:
      return KuraColors.danger;
    case RiskSeverity.medio:
      return KuraColors.warning;
    case RiskSeverity.bajo:
      return KuraColors.infoBlue;
  }
}
