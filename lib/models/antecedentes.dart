/// Antecedentes de la historia clínica (NOM-004, Fase 3).
///
/// - Heredo-familiares (AHF): enfermedades relevantes en familiares directos.
/// - Personales no patológicos (APNP): tabaquismo, alcoholismo, actividad física.
///
/// NOTA: el tabaquismo/malnutrición como COMORBILIDAD (que cuenta para el
/// arquetipo del motor) se captura aparte en comorbilidades; aquí el APNP es la
/// descripción clínica del hábito (p.ej. exfumador), más rica que el flag.

/// Antecedente heredo-familiar (multiselección).
enum AntecedenteHeredoFamiliar {
  diabetes,
  hipertension,
  cardiopatia,
  cancer,
  enfermedadRenal,
  enfermedadVascular,
  obesidad,
  otro,
}

extension AntecedenteHeredoFamiliarX on AntecedenteHeredoFamiliar {
  String get label {
    switch (this) {
      case AntecedenteHeredoFamiliar.diabetes:
        return 'Diabetes';
      case AntecedenteHeredoFamiliar.hipertension:
        return 'Hipertensión';
      case AntecedenteHeredoFamiliar.cardiopatia:
        return 'Cardiopatía';
      case AntecedenteHeredoFamiliar.cancer:
        return 'Cáncer';
      case AntecedenteHeredoFamiliar.enfermedadRenal:
        return 'Enfermedad renal';
      case AntecedenteHeredoFamiliar.enfermedadVascular:
        return 'Enfermedad vascular';
      case AntecedenteHeredoFamiliar.obesidad:
        return 'Obesidad';
      case AntecedenteHeredoFamiliar.otro:
        return 'Otro';
    }
  }

  String get dbValue => name;

  static AntecedenteHeredoFamiliar? fromDb(String s) {
    for (final v in AntecedenteHeredoFamiliar.values) {
      if (v.name == s) return v;
    }
    return null;
  }
}

/// Tabaquismo (APNP).
enum TabaquismoEstado { nunca, exfumador, activo }

extension TabaquismoEstadoX on TabaquismoEstado {
  String get label {
    switch (this) {
      case TabaquismoEstado.nunca:
        return 'Nunca';
      case TabaquismoEstado.exfumador:
        return 'Exfumador';
      case TabaquismoEstado.activo:
        return 'Activo';
    }
  }

  String get dbValue => name;

  static TabaquismoEstado? fromDb(String? s) {
    if (s == null) return null;
    for (final v in TabaquismoEstado.values) {
      if (v.name == s) return v;
    }
    return null;
  }
}

/// Consumo de alcohol (APNP).
enum ConsumoAlcohol { nunca, ocasional, frecuente }

extension ConsumoAlcoholX on ConsumoAlcohol {
  String get label {
    switch (this) {
      case ConsumoAlcohol.nunca:
        return 'Nunca';
      case ConsumoAlcohol.ocasional:
        return 'Ocasional';
      case ConsumoAlcohol.frecuente:
        return 'Frecuente';
    }
  }

  String get dbValue => name;

  static ConsumoAlcohol? fromDb(String? s) {
    if (s == null) return null;
    for (final v in ConsumoAlcohol.values) {
      if (v.name == s) return v;
    }
    return null;
  }
}

/// Actividad física (APNP).
enum ActividadFisica { sedentario, ligera, moderada, intensa }

extension ActividadFisicaX on ActividadFisica {
  String get label {
    switch (this) {
      case ActividadFisica.sedentario:
        return 'Sedentario';
      case ActividadFisica.ligera:
        return 'Ligera';
      case ActividadFisica.moderada:
        return 'Moderada';
      case ActividadFisica.intensa:
        return 'Intensa';
    }
  }

  String get dbValue => name;

  static ActividadFisica? fromDb(String? s) {
    if (s == null) return null;
    for (final v in ActividadFisica.values) {
      if (v.name == s) return v;
    }
    return null;
  }
}
