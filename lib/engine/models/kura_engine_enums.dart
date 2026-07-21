/// Enumeraciones de dominio clinico usadas por el motor "Protocolo Kura+".
/// Ver docs/kura_protocol_engine.md para la especificacion completa.
library kura_engine_enums;

/// Etiologia de la herida. `pieDiabetico` y `otra` son la categoria base
/// del modelo multinomial (todas las variables one-hot et_* quedan en 0).
enum Etiologia {
  lpp, // Lesion por presion
  vascular, // Ulcera vascular/venosa
  quirurgica, // Herida quirurgica
  traumatica, // Herida traumatica
  pieDiabetico, // Pie diabetico (categoria base)
  otra, // Otra (categoria base)
}

/// Subtipo de una úlcera de etiología vascular. Es un refinamiento DENTRO de
/// `Etiologia.vascular` (no una etiología nueva): el modelo pronóstico
/// (kura_prognosis_model) sigue viendo et_vasc=1 en los tres casos, mientras
/// que el motor de reglas (8.4) usa el subtipo para separar el manejo
/// venoso (compresión) del arterial/isquémico (terapia seca, sin compresión).
///
/// Protocolo "Úlceras MMII": la conflación venosa/arterial es un defecto
/// clínico grave — la compresión venosa aplicada a una úlcera arterial puede
/// agravar la isquemia. `na` = no clasificado (fallback conservador = venosa
/// para compatibilidad histórica, pero la UI debe forzar la captura).
enum SubtipoVascular { venosa, arterial, mixta }

extension SubtipoVascularLabel on SubtipoVascular {
  String get label {
    switch (this) {
      case SubtipoVascular.venosa:
        return 'Venosa';
      case SubtipoVascular.arterial:
        return 'Arterial / isquémica';
      case SubtipoVascular.mixta:
        return 'Mixta (arteriovenosa)';
    }
  }
}

extension EtiologiaLabel on Etiologia {
  String get label {
    switch (this) {
      case Etiologia.lpp:
        return 'Lesion por presion (LPP)';
      case Etiologia.vascular:
        return 'Ulcera vascular/venosa';
      case Etiologia.quirurgica:
        return 'Herida quirurgica';
      case Etiologia.traumatica:
        return 'Herida traumatica';
      case Etiologia.pieDiabetico:
        return 'Pie diabetico';
      case Etiologia.otra:
        return 'Otra';
    }
  }
}

/// Categoria de indice tobillo-brazo (ABI/ITB) usada por el MODELO
/// PRONOSTICO (kura_clinical_adjustments). Solo aplica a heridas de
/// extremidad inferior. `na` = no evaluado / no aplica.
///
/// `incompresible` (ITB > 1.4) es el TECHO SUPERIOR añadido en
/// fix/rules-arterial-dry-therapy: un ITB > 1.4 NO indica buena perfusión
/// sino calcificación arterial / arterias incompresibles (frecuente en
/// diabetes/IRC), por lo que NO debe recibir el bono pronóstico de "buena
/// perfusión" que antes se le asignaba al caer en `high` (>=0.80 sin techo).
/// Protocolo "Úlceras MMII": ITB > 1.4 → medición no interpretable, derivar
/// angiología. Ver `ItbCompresionBand` para la lógica de compresión.
enum AbiCategory { na, incompresible, high, mod, low }

/// Banda de compresión según el índice tobillo-brazo (ITB), calibrada a la
/// tabla del protocolo "Úlceras MMII". Es INDEPENDIENTE de `AbiCategory`
/// (que sirve al modelo pronóstico): aquí los cortes rigen EXCLUSIVAMENTE la
/// terapia compresiva y la derivación a angiología, con umbrales clínicos
/// distintos a los del pronóstico.
///
/// Tabla (protocolo MMII):
/// - `incompresible`  ITB > 1.4     → NO comprimir + derivar angiología.
/// - `fuerte`         0.9 ≤ ITB ≤ 1.4 → compresión fuerte (30-40 mmHg).
/// - `precaucion`     0.8 ≤ ITB < 0.9 → compresión con precaución + derivar.
/// - `reducida`       0.6 ≤ ITB < 0.8 → compresión reducida (máx 20 mmHg) + derivar.
/// - `noAplica`       ITB < 0.6     → NO aplicar compresión.
/// - `na`             sin medición   → confirmar ITB antes de iniciar.
enum ItbCompresionBand { na, incompresible, fuerte, precaucion, reducida, noAplica }

/// Categoria de albumina serica. `na` = no disponible.
enum AlbCategory { na, normal, mild, low }

/// Modalidad de tratamiento de una LPP según el riesgo de Braden (Protocolo
/// "Interconsultas"/LPP): a mayor riesgo, más control clínico.
enum ModalidadTratamiento { compartido, aCargoClinica }

extension ModalidadTratamientoLabel on ModalidadTratamiento {
  String get label {
    switch (this) {
      case ModalidadTratamiento.compartido:
        return 'Tratamiento compartido (clínica + cuidador)';
      case ModalidadTratamiento.aCargoClinica:
        return 'Tratamiento a cargo de la clínica';
    }
  }
}

/// Entorno donde se realiza el tratamiento; afecta el metodo de
/// desbridamiento sugerido y la educacion al cuidador.
enum Entorno { clinica, domicilio }

enum ExudadoCantidad { ninguno, escaso, moderado, abundante }

enum ExudadoTipo { seroso, sanguinolento, serosanguinolento, purulento, otro }

/// Estados posibles de piel perilesional (multiseleccion en la UI).
enum PielPerilesionalEstado {
  normal,
  seca,
  fragil,
  macerada,
  eritematosa,
  eccematosa,
  hiperqueratosica,
  callosidad,
}

/// Estado de una comorbilidad individual dentro del expediente.
enum ComorbilidadEstado { presente, negado, noEvaluado }

/// Catalogo estandar de comorbilidades relevantes para cicatrizacion.
/// NOTA DE DISENO: la especificacion no enumera el catalogo exacto de
/// comorbilidades; se define aqui un catalogo clinico estandar. Solo las
/// marcadas como `presente` cuentan para n_comorb_struct (las `noEvaluado`
/// NO se cuentan, tal como indica la especificacion 8.1).
enum Comorbilidad {
  diabetesMellitus,
  enfermedadArterialPeriferica,
  insuficienciaVenosaCronica,
  insuficienciaRenalCronica,
  enfermedadCardiovascular,
  inmunosupresion,
  obesidad,
  tabaquismoActivo,
  malnutricion,
  movilidadReducida,
}

extension ComorbilidadLabel on Comorbilidad {
  String get label {
    switch (this) {
      case Comorbilidad.diabetesMellitus:
        return 'Diabetes mellitus';
      case Comorbilidad.enfermedadArterialPeriferica:
        return 'Enfermedad arterial periferica';
      case Comorbilidad.insuficienciaVenosaCronica:
        return 'Insuficiencia venosa cronica';
      case Comorbilidad.insuficienciaRenalCronica:
        return 'Insuficiencia renal cronica';
      case Comorbilidad.enfermedadCardiovascular:
        return 'Enfermedad cardiovascular';
      case Comorbilidad.inmunosupresion:
        return 'Inmunosupresion';
      case Comorbilidad.obesidad:
        return 'Obesidad';
      case Comorbilidad.tabaquismoActivo:
        return 'Tabaquismo activo';
      case Comorbilidad.malnutricion:
        return 'Malnutricion';
      case Comorbilidad.movilidadReducida:
        return 'Movilidad reducida';
    }
  }
}

/// Escenario de pronostico de evolucion (salida del modelo multinomial).
enum KuraScenario { a, b, c }

extension KuraScenarioLabel on KuraScenario {
  String get code {
    switch (this) {
      case KuraScenario.a:
        return 'A';
      case KuraScenario.b:
        return 'B';
      case KuraScenario.c:
        return 'C';
    }
  }

  String get title {
    switch (this) {
      case KuraScenario.a:
        return 'Cierre rapido';
      case KuraScenario.b:
        return 'Cierre asistido prolongado';
      case KuraScenario.c:
        return 'No cierre / mantenimiento';
    }
  }

  String get clinicalMeaning {
    switch (this) {
      case KuraScenario.a:
        return 'Cierre esperado en ~2-3 meses (~11 sesiones)';
      case KuraScenario.b:
        return 'Cierre en 4-6+ meses si se completa el plan de tratamiento';
      case KuraScenario.c:
        return 'Cierre no esperado; enfoque de confort y prevencion de complicaciones';
    }
  }

  String get treatmentPhenotype {
    switch (this) {
      case KuraScenario.a:
        return 'Intermedio (curacion)';
      case KuraScenario.b:
        return 'Integral (alta intensidad)';
      case KuraScenario.c:
        return 'Confort / prevencion';
    }
  }

  String get commercialPhenotype {
    switch (this) {
      case KuraScenario.a:
        return 'A1 - Cierre Activo';
      case KuraScenario.b:
        return 'A2/A3 - Integral';
      case KuraScenario.c:
        return 'A4 - Confort';
    }
  }
}

/// Grado de Wagner para pie diabetico (0 a 5).
enum WagnerGrade { g0, g1, g2, g3, g4, g5 }

/// Clasificacion CEAP simplificada para enfermedad venosa (C0-C6).
enum CeapClass { c0, c1, c2, c3, c4, c5, c6 }

/// Grado WUWHS para heridas quirurgicas (severidad de dehiscencia/infeccion).
enum WuwhsGrade { g1, g2, g3, g4 }

/// Agente causal para heridas traumaticas.
enum AgenteCausal { mordedura, armaFuego, aplastamiento, punzocortante, otro }

/// Criterios IWII de infeccion (multiseleccion).
///
/// `eritemaPerilesional` se entiende como eritema LOCAL (<=2 cm). Si el
/// eritema se propaga mas alla de ese margen, se debe marcar en su lugar
/// (o ademas) `eritemaMayor2cm`, que es un criterio de infeccion PROPAGADA
/// (ver kura_rules_v2 / KuraEngineInput.infeccionPropagada).
///
/// `induracion` se agrega como factor local significativo (kura_rules_v2)
/// para completar el listado clinico de "criterios finales" de infeccion
/// local; no existia representacion previa de este signo en el modelo.
enum InfeccionCriterioIwii {
  dolorAumentado,
  eritemaPerilesional,
  edemaLocal,
  calorLocal,
  exudadoPurulento,
  exudadoAumentado,
  olorAumentado,
  tejidoFriable,
  induracion,
  retrasoDeCicatrizacion,
  socavamiento,
  dehiscencia,
  celulitis,
  fiebre,
  malestarGeneral,
  eritemaMayor2cm,
}

extension InfeccionCriterioIwiiLabel on InfeccionCriterioIwii {
  String get label {
    switch (this) {
      case InfeccionCriterioIwii.dolorAumentado:
        return 'Dolor / sensibilidad aumentado';
      case InfeccionCriterioIwii.eritemaPerilesional:
        return 'Eritema perilesional (<=2 cm, local)';
      case InfeccionCriterioIwii.edemaLocal:
        return 'Edema local';
      case InfeccionCriterioIwii.calorLocal:
        return 'Aumento de temperatura / calor local';
      case InfeccionCriterioIwii.exudadoPurulento:
        return 'Exudado purulento / seropurulento';
      case InfeccionCriterioIwii.exudadoAumentado:
        return 'Aumento de exudado';
      case InfeccionCriterioIwii.olorAumentado:
        return 'Olor';
      case InfeccionCriterioIwii.tejidoFriable:
        return 'Tejido friable';
      case InfeccionCriterioIwii.induracion:
        return 'Induracion';
      case InfeccionCriterioIwii.retrasoDeCicatrizacion:
        return 'Retraso de cicatrizacion';
      case InfeccionCriterioIwii.socavamiento:
        return 'Socavamiento';
      case InfeccionCriterioIwii.dehiscencia:
        return 'Dehiscencia';
      case InfeccionCriterioIwii.celulitis:
        return 'Celulitis (propagacion)';
      case InfeccionCriterioIwii.fiebre:
        return 'Fiebre (propagacion)';
      case InfeccionCriterioIwii.malestarGeneral:
        return 'Malestar general (propagacion)';
      case InfeccionCriterioIwii.eritemaMayor2cm:
        return 'Eritema >2 cm (propagación)';
    }
  }
}
