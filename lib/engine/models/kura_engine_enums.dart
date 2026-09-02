/// Enumeraciones de dominio clinico usadas por el motor "Protocolo Kura+".
/// Ver docs/kura_protocol_engine.md para la especificacion completa.
library;

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

extension ExudadoCantidadX on ExudadoCantidad {
  String get label {
    switch (this) {
      case ExudadoCantidad.ninguno:
        return 'Ninguno';
      case ExudadoCantidad.escaso:
        return 'Escaso';
      case ExudadoCantidad.moderado:
        return 'Moderado';
      case ExudadoCantidad.abundante:
        return 'Abundante';
    }
  }
}

enum ExudadoTipo { serohematico, hematico, purulento, seropurulento, otro }

extension ExudadoTipoX on ExudadoTipo {
  String get label {
    switch (this) {
      case ExudadoTipo.serohematico:
        return 'Serohemático';
      case ExudadoTipo.hematico:
        return 'Hemático';
      case ExudadoTipo.purulento:
        return 'Purulento';
      case ExudadoTipo.seropurulento:
        return 'Seropurulento';
      case ExudadoTipo.otro:
        return 'Otro';
    }
  }
}

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

extension PielPerilesionalEstadoX on PielPerilesionalEstado {
  String get label {
    switch (this) {
      case PielPerilesionalEstado.normal:
        return 'Normal';
      case PielPerilesionalEstado.seca:
        return 'Seca';
      case PielPerilesionalEstado.fragil:
        return 'Frágil';
      case PielPerilesionalEstado.macerada:
        return 'Macerada';
      case PielPerilesionalEstado.eritematosa:
        return 'Eritematosa';
      case PielPerilesionalEstado.eccematosa:
        return 'Eccematosa';
      case PielPerilesionalEstado.hiperqueratosica:
        return 'Hiperqueratósica';
      case PielPerilesionalEstado.callosidad:
        return 'Callosidad';
    }
  }
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

extension AgenteCausalLabel on AgenteCausal {
  String get label {
    switch (this) {
      case AgenteCausal.mordedura:
        return 'Mordedura';
      case AgenteCausal.armaFuego:
        return 'Arma de fuego';
      case AgenteCausal.aplastamiento:
        return 'Aplastamiento';
      case AgenteCausal.punzocortante:
        return 'Punzocortante';
      case AgenteCausal.otro:
        return 'Otro';
    }
  }
}

// ===========================================================================
// Clasificaciones/campos por etiología (Prompt 5) — protocolos de las 4
// etiologías. Enums de dominio con etiqueta legible + `dbValue` (== name) para
// persistir en columnas de texto de `wounds` (ver migración 0028).
// ===========================================================================

/// Subtipo clínico del pie diabético (UPD).
enum UpdSubtipo { neuropatica, infecciosa, isquemica, neuroinfecciosa, neuroisquemica }

extension UpdSubtipoLabel on UpdSubtipo {
  String get label {
    switch (this) {
      case UpdSubtipo.neuropatica:
        return 'Neuropática';
      case UpdSubtipo.infecciosa:
        return 'Infecciosa';
      case UpdSubtipo.isquemica:
        return 'Isquémica';
      case UpdSubtipo.neuroinfecciosa:
        return 'Neuroinfecciosa';
      case UpdSubtipo.neuroisquemica:
        return 'Neuroisquémica';
    }
  }
}

/// Clasificación de la Universidad de Texas para UPD: grado (profundidad, 0-III)
/// y estadio (A sin infección/isquemia, B infección, C isquemia, D ambas).
enum TexasGrade { g0, g1, g2, g3 }

extension TexasGradeLabel on TexasGrade {
  String get label {
    switch (this) {
      case TexasGrade.g0:
        return '0 (pre/post-ulcerosa, epitelizada)';
      case TexasGrade.g1:
        return 'I (superficial, sin tendón/cápsula/hueso)';
      case TexasGrade.g2:
        return 'II (penetra a tendón o cápsula)';
      case TexasGrade.g3:
        return 'III (penetra a hueso o articulación)';
    }
  }
}

enum TexasStage { a, b, c, d }

extension TexasStageLabel on TexasStage {
  String get label {
    switch (this) {
      case TexasStage.a:
        return 'A (sin infección ni isquemia)';
      case TexasStage.b:
        return 'B (con infección)';
      case TexasStage.c:
        return 'C (con isquemia)';
      case TexasStage.d:
        return 'D (infección + isquemia)';
    }
  }
}

/// Gravedad de infección del pie diabético (IDSA/IWGDF, grados 1-4).
enum IdsaIwgdf { noInfectada, leve, moderada, grave }

extension IdsaIwgdfLabel on IdsaIwgdf {
  String get label {
    switch (this) {
      case IdsaIwgdf.noInfectada:
        return 'No infectada (grado 1)';
      case IdsaIwgdf.leve:
        return 'Leve (grado 2)';
      case IdsaIwgdf.moderada:
        return 'Moderada (grado 3)';
      case IdsaIwgdf.grave:
        return 'Grave / con SIRS (grado 4)';
    }
  }
}

/// Resultado del monofilamento de 10 g (Semmes-Weinstein) / sensibilidad
/// protectora del pie.
enum SensibilidadProtectora { conservada, disminuida, ausente }

extension SensibilidadProtectoraLabel on SensibilidadProtectora {
  String get label {
    switch (this) {
      case SensibilidadProtectora.conservada:
        return 'Conservada (percibe monofilamento)';
      case SensibilidadProtectora.disminuida:
        return 'Disminuida (parcial)';
      case SensibilidadProtectora.ausente:
        return 'Ausente (no percibe: pie de riesgo)';
    }
  }
}

/// Categoría de Rutherford para isquemia crónica de miembro (0-6). Se captura
/// sobre el subtipo ARTERIAL de la úlcera vascular (Prompt 1).
enum Rutherford { c0, c1, c2, c3, c4, c5, c6 }

extension RutherfordLabel on Rutherford {
  String get label {
    switch (this) {
      case Rutherford.c0:
        return '0 (asintomático)';
      case Rutherford.c1:
        return '1 (claudicación leve)';
      case Rutherford.c2:
        return '2 (claudicación moderada)';
      case Rutherford.c3:
        return '3 (claudicación grave)';
      case Rutherford.c4:
        return '4 (dolor isquémico en reposo)';
      case Rutherford.c5:
        return '5 (pérdida tisular menor)';
      case Rutherford.c6:
        return '6 (pérdida tisular mayor)';
    }
  }
}

/// Estadio NPUAP/EPUAP de la lesión por presión (reemplaza el texto libre).
enum NpuapEstadio {
  i,
  ii,
  iii,
  iv,
  lesionTisularProfunda,
  noClasificable,
}

extension NpuapEstadioLabel on NpuapEstadio {
  String get label {
    switch (this) {
      case NpuapEstadio.i:
        return 'I (eritema no blanqueable)';
      case NpuapEstadio.ii:
        return 'II (pérdida parcial de dermis)';
      case NpuapEstadio.iii:
        return 'III (pérdida total de piel)';
      case NpuapEstadio.iv:
        return 'IV (pérdida total de tejido)';
      case NpuapEstadio.lesionTisularProfunda:
        return 'Lesión tisular profunda';
      case NpuapEstadio.noClasificable:
        return 'No clasificable';
    }
  }
}

/// Clase de contaminación de la herida quirúrgica (CDC).
enum ClaseContaminacion { limpia, limpiaContaminada, contaminada, sucia }

extension ClaseContaminacionLabel on ClaseContaminacion {
  String get label {
    switch (this) {
      case ClaseContaminacion.limpia:
        return 'Limpia';
      case ClaseContaminacion.limpiaContaminada:
        return 'Limpia-contaminada';
      case ClaseContaminacion.contaminada:
        return 'Contaminada';
      case ClaseContaminacion.sucia:
        return 'Sucia / infectada';
    }
  }
}

/// Tipo de cierre de la herida quirúrgica (intención).
enum TipoCierre { primera, segunda, tercera }

extension TipoCierreLabel on TipoCierre {
  String get label {
    switch (this) {
      case TipoCierre.primera:
        return 'Primera intención';
      case TipoCierre.segunda:
        return 'Segunda intención';
      case TipoCierre.tercera:
        return 'Tercera intención (cierre diferido)';
    }
  }
}

/// Tipo de drenaje quirúrgico (catálogo validado por María 2026-07).
enum DrenajeTipo { ninguno, penrose, jackson, blake, pleurovac, hemovac, otro }

extension DrenajeTipoLabel on DrenajeTipo {
  String get label {
    switch (this) {
      case DrenajeTipo.ninguno:
        return 'Sin drenaje';
      case DrenajeTipo.penrose:
        return 'Penrose';
      case DrenajeTipo.jackson:
        return 'Jackson-Pratt';
      case DrenajeTipo.blake:
        return 'Blake';
      case DrenajeTipo.pleurovac:
        return 'Pleurovac';
      case DrenajeTipo.hemovac:
        return 'Hemovac';
      case DrenajeTipo.otro:
        return 'Otro';
    }
  }
}

/// Tipo de sutura/afrontamiento (estructurado). Cierre por primera intención:
/// intradérmica, dérmica, grapas (validado por María 2026-07).
enum SuturaTipo {
  ninguna,
  intradermica,
  dermica,
  puntosSeparados,
  continua,
  colchonero,
  subdermica,
  grapas,
  otra,
}

extension SuturaTipoLabel on SuturaTipo {
  String get label {
    switch (this) {
      case SuturaTipo.ninguna:
        return 'Sin sutura';
      case SuturaTipo.intradermica:
        return 'Intradérmica';
      case SuturaTipo.dermica:
        return 'Dérmica';
      case SuturaTipo.puntosSeparados:
        return 'Puntos separados';
      case SuturaTipo.continua:
        return 'Continua';
      case SuturaTipo.colchonero:
        return 'Colchonero';
      case SuturaTipo.subdermica:
        return 'Subdérmica';
      case SuturaTipo.grapas:
        return 'Grapas';
      case SuturaTipo.otra:
        return 'Otra';
    }
  }
}

/// Motivo de egreso del episodio de la herida (estructurado).
enum MotivoEgreso { cierre, altaVoluntaria, abandono, defuncion }

extension MotivoEgresoLabel on MotivoEgreso {
  String get label {
    switch (this) {
      case MotivoEgreso.cierre:
        return 'Cierre (cicatrización)';
      case MotivoEgreso.altaVoluntaria:
        return 'Alta voluntaria';
      case MotivoEgreso.abandono:
        return 'Abandono';
      case MotivoEgreso.defuncion:
        return 'Defunción';
    }
  }
}

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
