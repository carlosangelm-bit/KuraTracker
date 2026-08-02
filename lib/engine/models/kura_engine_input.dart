import '../params/clinical_params.dart';
import 'kura_engine_enums.dart';

/// Entrada consolidada para el motor "Protocolo Kura+".
///
/// Se construye a partir del expediente clinico capturado en la app
/// (etiologia, medicion seriada, comorbilidades, perfusion, nutricion) y
/// se pasa tal cual al servicio del motor (Dart local o Edge Function),
/// garantizando que ambas implementaciones reciban exactamente los mismos
/// datos y produzcan resultados idénticos.
class KuraEngineInput {
  final Etiologia etiologia;
  final Entorno entorno;

  /// Dimensiones del lecho de la herida.
  final double areaCm2; // largo x ancho, cm2 (o area estimada por foto)
  final double depthCm;
  final double necrosisPct; // 0-100
  final double esfaceloPct; // 0-100
  final double granulacionPct; // 0-100
  final double epitelizacionPct; // 0-100

  /// Comorbilidades con su estado; solo `presente` cuenta para n_comorb_struct.
  final Map<Comorbilidad, ComorbilidadEstado> comorbilidades;

  /// Perfusion: ABI/ITB de ambos pies (solo aplica a extremidad inferior).
  /// Si la herida no es de extremidad inferior, dejar ambos en null.
  final double? abiPieDerecho;
  final double? abiPieIzquierdo;
  final bool esExtremidadInferior;

  /// Nutricion: albumina serica en g/dL. Null = no disponible.
  final double? albuminaGdl;

  /// Datos adicionales usados por el motor de reglas (8.4), no por el
  /// modelo pronostico (8.1).
  final bool tunelizacionOSocavamiento;
  final ExudadoCantidad exudadoCantidad;
  final Set<PielPerilesionalEstado> pielPerilesional;
  final Set<InfeccionCriterioIwii> infeccionCriterios;
  final bool tieneCuidadorIdentificado;
  final bool pacienteFragil;

  // Contexto especifico por etiologia (usado por el motor de reglas 8.4)
  final WagnerGrade? wagnerGrade;
  final CeapClass? ceapClass;
  final WuwhsGrade? wuwhsGrade;
  final AgenteCausal? agenteCausal;

  /// Subtipo de la úlcera vascular (venosa/arterial/mixta). Solo relevante
  /// cuando `etiologia == Etiologia.vascular`. Separa el manejo venoso
  /// (compresión) del arterial/isquémico (terapia seca). `null` = no
  /// clasificado: por compatibilidad histórica se trata como venosa, pero la
  /// UI debe forzar la captura para heridas vasculares.
  final SubtipoVascular? subtipoVascular;

  /// Determinación clínica (Doppler / angiólogo) de que la lesión NO es
  /// revascularizable. Gatilla terapia seca aunque el ITB no sea crítico.
  /// Protocolo "Terapia seca".
  final bool noRevascularizable;

  /// Escala de Braden (6-23) para riesgo de LPP. Determina la modalidad de
  /// tratamiento en LPP (compartido vs a cargo de clínica). Null = no evaluada.
  final int? bradenScore;

  /// LPP recurrente (reaparición en la misma zona / paciente con historial):
  /// gatilla interconsulta a geriatría (Protocolo "Interconsultas").
  final bool lppRecurrente;

  /// Paciente en cuidados paliativos: gatilla interconsulta a geriatría.
  final bool cuidadosPaliativos;

  /// Dolor crónico asociado a la herida: gatilla interconsulta a geriatría.
  final bool dolorCronico;

  /// Longitud del túnel/tunelización en cm (medida con estilete). Un túnel
  /// > 7 cm exige referencia (Protocolo "Interconsultas"). Null = no medido.
  final double? tunnelDepthCm;

  /// La herida compromete/está sobre una articulación: exige referencia
  /// (riesgo de compromiso articular; Protocolo "Interconsultas").
  final bool sobreArticulacion;

  const KuraEngineInput({
    required this.etiologia,
    required this.entorno,
    required this.areaCm2,
    required this.depthCm,
    required this.necrosisPct,
    required this.esfaceloPct,
    required this.granulacionPct,
    required this.epitelizacionPct,
    required this.comorbilidades,
    this.abiPieDerecho,
    this.abiPieIzquierdo,
    this.esExtremidadInferior = false,
    this.albuminaGdl,
    this.tunelizacionOSocavamiento = false,
    this.exudadoCantidad = ExudadoCantidad.escaso,
    this.pielPerilesional = const {},
    this.infeccionCriterios = const {},
    this.tieneCuidadorIdentificado = false,
    this.pacienteFragil = false,
    this.wagnerGrade,
    this.ceapClass,
    this.wuwhsGrade,
    this.agenteCausal,
    this.subtipoVascular,
    this.noRevascularizable = false,
    this.bradenScore,
    this.lppRecurrente = false,
    this.cuidadosPaliativos = false,
    this.dolorCronico = false,
    this.tunnelDepthCm,
    this.sobreArticulacion = false,
  });

  /// Numero de comorbilidades confirmadas presentes (excluye no evaluadas
  /// y negadas), segun especificacion 8.1.
  int get nComorbStruct =>
      comorbilidades.values.where((s) => s == ComorbilidadEstado.presente).length;

  /// Minimo ABI entre ambos pies (isquemia critica si <0.5). Null si no
  /// hay datos o la herida no es de extremidad inferior.
  double? get abiMinimo {
    if (!esExtremidadInferior) return null;
    final values = [abiPieDerecho, abiPieIzquierdo].whereType<double>().toList();
    if (values.isEmpty) return null;
    return values.reduce((a, b) => a < b ? a : b);
  }

  AbiCategory get abiCategory {
    final v = abiMinimo;
    if (v == null) return AbiCategory.na;
    // Techo superior (Protocolo MMII): ITB > abi_incompresible_above = arterias
    // incompresibles / calcificación, NO buena perfusión. Antes caía en `high`
    // (sin techo) y recibía el bono pronóstico de buena perfusión, algo
    // clínicamente incorrecto. Cortes en assets/engine/clinical/thresholds.json.
    final p = ClinicalParams.I;
    if (v > p.abiIncompresibleAbove) return AbiCategory.incompresible;
    if (v >= p.abiHighMin) return AbiCategory.high;
    if (v >= p.abiModMin) return AbiCategory.mod;
    return AbiCategory.low;
  }

  /// Banda de compresión según ITB, calibrada a la tabla del protocolo
  /// "Úlceras MMII". Independiente de `abiCategory` (que sirve al modelo
  /// pronóstico). Cortes/bandas en assets/engine/clinical/thresholds.json.
  ItbCompresionBand get itbCompresionBand {
    final v = abiMinimo;
    if (v == null) return ItbCompresionBand.na;
    return ClinicalParams.I.itbBandFor(v);
  }

  /// Derivación a angiología por perfusión anómala (Protocolo MMII): todo ITB
  /// medido fuera de la banda `fuerte` (incompresible, precaución, reducida o
  /// perfusión insuficiente). `na` (sin medición) no requiere derivación por
  /// este criterio.
  bool get requiereDerivacionAngiologiaPorItb {
    final v = abiMinimo;
    if (v == null) return false;
    return itbCompresionBand != ItbCompresionBand.fuerte;
  }

  /// Úlcera de manejo con TERAPIA SECA (Protocolo "Terapia seca"): úlcera
  /// arterial/isquémica, no revascularizable, o cualquier isquemia crítica
  /// (ITB < 0.5). En estos casos se suprime la cura húmeda por defecto, se
  /// contraindica la compresión y el desbridamiento cortante, y se protege
  /// la escara seca estable.
  bool get requiereTerapiaSeca =>
      isquemiaCritica ||
      (etiologia == Etiologia.vascular &&
          (subtipoVascular == SubtipoVascular.arterial || noRevascularizable));

  AlbCategory get albCategory {
    final v = albuminaGdl;
    if (v == null) return AlbCategory.na;
    final p = ClinicalParams.I;
    if (v >= p.albuminaNormalMin) return AlbCategory.normal;
    if (v >= p.albuminaMildMin) return AlbCategory.mild;
    return AlbCategory.low;
  }

  /// Factores locales significativos de infeccion (kura_rules_v2), segun
  /// criterios finales clinicos. NOTA: "aumento de exudado" (exudadoAumentado)
  /// NO es un factor local valido por si mismo y queda excluido a proposito.
  static const Set<InfeccionCriterioIwii> _factoresLocalesSignificativos = {
    InfeccionCriterioIwii.exudadoPurulento, // exudado purulento/seropurulento
    InfeccionCriterioIwii.eritemaPerilesional, // eritema local (<=2 cm)
    InfeccionCriterioIwii.calorLocal, // aumento de temperatura / calor local
    InfeccionCriterioIwii.tejidoFriable, // tejido friable
    InfeccionCriterioIwii.induracion, // induracion
    InfeccionCriterioIwii.dolorAumentado, // sensibilidad/dolor aumentado
    InfeccionCriterioIwii.olorAumentado, // olor
  };

  /// Numero de factores locales significativos presentes.
  int get nFactoresLocalesInfeccion =>
      infeccionCriterios.intersection(_factoresLocalesSignificativos).length;

  /// Sospecha de infeccion LOCAL (kura_rules_v2): dos o mas factores locales
  /// significativos presentes. Reemplaza al antiguo
  /// `hayInfeccion = infeccionCriterios.isNotEmpty`.
  bool get sospechaInfeccionLocal =>
      nFactoresLocalesInfeccion >= ClinicalParams.I.infeccionLocalMinFactores;

  /// Infeccion PROPAGADA (kura_rules_v2): cualquier signo sistemico o de
  /// extension mas alla del lecho/borde local.
  bool get infeccionPropagada =>
      infeccionCriterios.contains(InfeccionCriterioIwii.eritemaMayor2cm) ||
      infeccionCriterios.contains(InfeccionCriterioIwii.celulitis) ||
      infeccionCriterios.contains(InfeccionCriterioIwii.fiebre) ||
      infeccionCriterios.contains(InfeccionCriterioIwii.malestarGeneral);

  /// Infeccion SISTEMICA (kura_rules_v2): subconjunto de infeccionPropagada
  /// confirmado clinicamente (celulitis incluida). Rige EXCLUSIVAMENTE la
  /// suspension de la compresion venosa graduada; NO se usa para el
  /// tratamiento topico-vs-sistemico (eso sigue usando infeccionPropagada
  /// completo, que incluye eritemaMayor2cm).
  bool get infeccionSistemica =>
      infeccionCriterios.contains(InfeccionCriterioIwii.celulitis) ||
      infeccionCriterios.contains(InfeccionCriterioIwii.fiebre) ||
      infeccionCriterios.contains(InfeccionCriterioIwii.malestarGeneral);

  bool get isquemiaCritica => abiCategory == AbiCategory.low;

  /// Modalidad de tratamiento sugerida por el rango de Braden (Protocolo LPP,
  /// bandas validadas por María 2026-07): riesgo bajo (18–23) -> tratamiento
  /// COMPARTIDO; riesgo medio (13–17), alto (10–12) y muy alto (≤9) -> A CARGO
  /// DE LA CLÍNICA (en el medio, al menos el primer mes + evaluar
  /// tunelizaciones/socavamientos). Null si no se capturó Braden.
  ModalidadTratamiento? get bradenModalidad {
    final b = bradenScore;
    if (b == null) return null;
    return b <= ClinicalParams.I.bradenACargoClinicaMax
        ? ModalidadTratamiento.aCargoClinica
        : ModalidadTratamiento.compartido;
  }

  /// Referencia obligatoria por túnel profundo (> tunel_referencia_min_cm) —
  /// Protocolo "Interconsultas".
  bool get requiereReferenciaPorTunel =>
      (tunnelDepthCm ?? 0) > ClinicalParams.I.tunelReferenciaMinCm;

  /// Referencia obligatoria por compromiso articular — Protocolo
  /// "Interconsultas".
  bool get requiereReferenciaPorArticulacion => sobreArticulacion;

  Map<String, dynamic> toJson() => {
        'etiologia': etiologia.name,
        'entorno': entorno.name,
        'area_cm2': areaCm2,
        'depth_cm': depthCm,
        'necrosis_pct': necrosisPct,
        'esfacelo_pct': esfaceloPct,
        'granulacion_pct': granulacionPct,
        'epitelizacion_pct': epitelizacionPct,
        'comorbilidades': comorbilidades.map((k, v) => MapEntry(k.name, v.name)),
        'abi_pie_derecho': abiPieDerecho,
        'abi_pie_izquierdo': abiPieIzquierdo,
        'es_extremidad_inferior': esExtremidadInferior,
        'albumina_gdl': albuminaGdl,
        'tunelizacion_o_socavamiento': tunelizacionOSocavamiento,
        'exudado_cantidad': exudadoCantidad.name,
        'piel_perilesional': pielPerilesional.map((e) => e.name).toList(),
        'infeccion_criterios': infeccionCriterios.map((e) => e.name).toList(),
        'tiene_cuidador_identificado': tieneCuidadorIdentificado,
        'paciente_fragil': pacienteFragil,
        'wagner_grade': wagnerGrade?.name,
        'ceap_class': ceapClass?.name,
        'wuwhs_grade': wuwhsGrade?.name,
        'agente_causal': agenteCausal?.name,
        'subtipo_vascular': subtipoVascular?.name,
        'no_revascularizable': noRevascularizable,
        'braden_score': bradenScore,
        'lpp_recurrente': lppRecurrente,
        'cuidados_paliativos': cuidadosPaliativos,
        'dolor_cronico': dolorCronico,
        'tunnel_depth_cm': tunnelDepthCm,
        'sobre_articulacion': sobreArticulacion,
      };

  factory KuraEngineInput.fromJson(Map<String, dynamic> json) {
    Comorbilidad? com(String s) =>
        Comorbilidad.values.where((e) => e.name == s).firstOrNull;
    ComorbilidadEstado? est(String s) =>
        ComorbilidadEstado.values.where((e) => e.name == s).firstOrNull;

    final comorbMap = <Comorbilidad, ComorbilidadEstado>{};
    final rawComorb = (json['comorbilidades'] as Map?) ?? {};
    rawComorb.forEach((k, v) {
      final c = com(k as String);
      final e = est(v as String);
      if (c != null && e != null) comorbMap[c] = e;
    });

    return KuraEngineInput(
      etiologia: Etiologia.values.firstWhere((e) => e.name == json['etiologia']),
      entorno: Entorno.values.firstWhere((e) => e.name == json['entorno']),
      areaCm2: (json['area_cm2'] as num).toDouble(),
      depthCm: (json['depth_cm'] as num).toDouble(),
      necrosisPct: (json['necrosis_pct'] as num).toDouble(),
      esfaceloPct: (json['esfacelo_pct'] as num).toDouble(),
      granulacionPct: (json['granulacion_pct'] as num).toDouble(),
      epitelizacionPct: (json['epitelizacion_pct'] as num).toDouble(),
      comorbilidades: comorbMap,
      abiPieDerecho: (json['abi_pie_derecho'] as num?)?.toDouble(),
      abiPieIzquierdo: (json['abi_pie_izquierdo'] as num?)?.toDouble(),
      esExtremidadInferior: json['es_extremidad_inferior'] as bool? ?? false,
      albuminaGdl: (json['albumina_gdl'] as num?)?.toDouble(),
      tunelizacionOSocavamiento: json['tunelizacion_o_socavamiento'] as bool? ?? false,
      exudadoCantidad: ExudadoCantidad.values
          .firstWhere((e) => e.name == (json['exudado_cantidad'] ?? 'escaso')),
      pielPerilesional: ((json['piel_perilesional'] as List?) ?? [])
          .map((s) => PielPerilesionalEstado.values.firstWhere((e) => e.name == s))
          .toSet(),
      infeccionCriterios: ((json['infeccion_criterios'] as List?) ?? [])
          .map((s) => InfeccionCriterioIwii.values.firstWhere((e) => e.name == s))
          .toSet(),
      tieneCuidadorIdentificado: json['tiene_cuidador_identificado'] as bool? ?? false,
      pacienteFragil: json['paciente_fragil'] as bool? ?? false,
      wagnerGrade: json['wagner_grade'] == null
          ? null
          : WagnerGrade.values.firstWhere((e) => e.name == json['wagner_grade']),
      ceapClass: json['ceap_class'] == null
          ? null
          : CeapClass.values.firstWhere((e) => e.name == json['ceap_class']),
      wuwhsGrade: json['wuwhs_grade'] == null
          ? null
          : WuwhsGrade.values.firstWhere((e) => e.name == json['wuwhs_grade']),
      agenteCausal: json['agente_causal'] == null
          ? null
          : AgenteCausal.values.firstWhere((e) => e.name == json['agente_causal']),
      subtipoVascular: json['subtipo_vascular'] == null
          ? null
          : SubtipoVascular.values
              .firstWhere((e) => e.name == json['subtipo_vascular']),
      noRevascularizable: json['no_revascularizable'] as bool? ?? false,
      bradenScore: (json['braden_score'] as num?)?.toInt(),
      lppRecurrente: json['lpp_recurrente'] as bool? ?? false,
      cuidadosPaliativos: json['cuidados_paliativos'] as bool? ?? false,
      dolorCronico: json['dolor_cronico'] as bool? ?? false,
      tunnelDepthCm: (json['tunnel_depth_cm'] as num?)?.toDouble(),
      sobreArticulacion: json['sobre_articulacion'] as bool? ?? false,
    );
  }
}

extension _FirstOrNullExt<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
