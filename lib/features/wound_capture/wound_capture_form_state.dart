import '../../core/utils/wound_volume.dart';
import '../../engine/models/kura_engine_enums.dart';
import '../../engine/models/kura_engine_input.dart';

/// Estado mutable del formulario de captura de herida. Se recalcula el
/// pronostico en vivo (seccion 6.1) cada vez que cambia un campo relevante.
class WoundCaptureFormState {
  // ---- Datos generales / localizacion ----
  Etiologia etiologia = Etiologia.otra;
  String? subtype;
  String? bodyLocationPrimary;
  String? bodyLocationSecondary;
  DateTime? onsetDate;
  Map<String, String> vitalSigns = {};

  // ---- Condicionales por etiologia ----
  WagnerGrade? wagnerGrade;
  // WIfI (Wound/Ischemia/foot Infection): 3 subescalas independientes 0-3,
  // capturadas junto a Wagner en pie diabetico (Hoja de Valoracion Kura+).
  int? wifiWound;
  int? wifiIschemia;
  int? wifiInfection;
  CeapClass? ceapClass;
  // Subtipo de úlcera vascular (venosa/arterial/mixta). Separa el manejo
  // venoso (compresión) del arterial/isquémico (terapia seca).
  SubtipoVascular? subtipoVascular;
  // Determinación (Doppler/angiólogo) de lesión no revascularizable: gatilla
  // terapia seca aunque el ITB no sea crítico.
  bool noRevascularizable = false;
  WuwhsGrade? wuwhsGrade;
  AgenteCausal? agenteCausal;
  // Braden (riesgo de LPP), score total 6-23. Obligatorio en UI si la
  // etiologia de la herida es LPP.
  int? bradenScore;

  // ---- Clasificaciones/campos por etiología (Prompt 5) ----
  // UPD (pie diabético)
  UpdSubtipo? updSubtipo;
  TexasGrade? texasGrade;
  TexasStage? texasStage;
  IdsaIwgdf? idsaIwgdf;
  SensibilidadProtectora? sensibilidadProtectora;
  // Vascular arterial
  Rutherford? rutherford;
  // LPP (estadio estructurado en vez de texto libre)
  NpuapEstadio? npuapEstadio;
  // Quirúrgica
  ClaseContaminacion? claseContaminacion;
  TipoCierre? tipoCierre;
  DrenajeTipo? drenajeTipo;
  SuturaTipo? suturaTipo;

  // ---- Evaluacion clinica ----
  double? glucoseMgDl;
  // HbA1c (hemoglobina glucosilada, %) - distinta de glucoseMgDl (glucosa
  // capilar puntual). Se muestra si el paciente es diabetico o la
  // etiologia es pie diabetico.
  double? hba1cPct;
  DateTime? firstAssessmentDate;
  String edema = 'ninguno';
  bool pain = false;
  String? painType;
  String? painDuration;
  int painVas = 0;
  ExudadoTipo exudadoTipo = ExudadoTipo.seroso;
  ExudadoCantidad exudadoCantidad = ExudadoCantidad.escaso;
  Set<InfeccionCriterioIwii> infeccionCriterios = {};
  String odor = 'ninguno';
  String woundEdge = 'definido';
  Set<PielPerilesionalEstado> perilesionalSkin = {};
  // Notas clinicas / observaciones libres de la visita (opcional).
  // No bloquea el guardado si esta vacio (feat/clinical-free-notes).
  String? clinicalNotes;

  // ---- Medicion ----
  double lengthCm = 0;
  double widthCm = 0;
  double depthCm = 0;
  // Volumen (cm3): auto-calculado por Kundin (L x A x P x 0.327) cada vez
  // que cambia largo/ancho/profundidad, pero editable: el clinico puede
  // sobrescribirlo (feat/volume-kundin-charts). null si depthCm es 0
  // (herida superficial, sin medicion 3D).
  // NOTA: no se guarda un flag "volumeManual" mutable aqui; el flag
  // persistido (volume_manual) se deriva en vivo del getter
  // isVolumeManuallyOverridden (comparando volumeCm3 vs autoVolumeCm3) al
  // momento de guardar, ver _continueToTreatment en wound_capture_screen.
  double? volumeCm3;
  bool tunneling = false;
  bool undermining = false;
  double granulacionPct = 100;
  double esfaceloPct = 0;
  double necrosisPct = 0;
  double epitelizacionPct = 0;
  bool capturedBeforeDebridement = true;

  // ---- Perfusion / nutricion ----
  bool esExtremidadInferior = false;
  double? abiRight;
  double? abiLeft;
  double? albuminaGdl;

  // ---- Comorbilidades (referencia del paciente, cargadas al iniciar) ----
  Map<Comorbilidad, ComorbilidadEstado> comorbilidades = {};

  // ---- Contexto ----
  Entorno entorno = Entorno.clinica;
  bool tieneCuidadorIdentificado = false;
  bool pacienteFragil = false;

  // ---- Evidencia fotografica (rutas locales temporales / bytes) ----
  List<String> photoPaths = [];

  double get areaCm2 => lengthCm * widthCm;

  /// Volumen auto-calculado por Kundin a partir de las medidas actuales
  /// (largo/ancho/profundidad). null si la herida es superficial
  /// (depthCm <= 0): el volumen 3D no aplica.
  double? get autoVolumeCm3 =>
      WoundVolumeCalculator.kundin(lengthCm: lengthCm, widthCm: widthCm, depthCm: depthCm);

  /// true si el valor actualmente en volumeCm3 difiere del auto-calculo de
  /// Kundin para las medidas actuales (el clinico lo sobrescribio a mano).
  bool get isVolumeManuallyOverridden => WoundVolumeCalculator.isManualOverride(
        storedVolumeCm3: volumeCm3,
        autoCalculatedCm3: autoVolumeCm3,
      );

  /// Herida profunda (mismo umbral que follow_up_capture_screen): a mayor
  /// profundidad se activa el bloque de medicion 3D (volumen) ademas del 2D.
  bool get isDeepWound => depthCm >= 0.5;

  bool get isLowerExtremityLocation {
    final loc = bodyLocationPrimary ?? '';
    return loc.contains('pie') ||
        loc.contains('pierna') ||
        loc.contains('pantorrilla') ||
        loc.contains('talon') ||
        loc.contains('rodilla');
  }

  /// Paciente diabetico: por comorbilidad marcada como presente o por
  /// etiologia de pie diabetico (gatea HbA1c y, junto a la etiologia, WIfI).
  bool get isDiabeticPatient =>
      comorbilidades[Comorbilidad.diabetesMellitus] == ComorbilidadEstado.presente ||
      etiologia == Etiologia.pieDiabetico;

  /// LPP (lesion por presion): gatea el campo obligatorio de Braden.
  bool get isLpp => etiologia == Etiologia.lpp;

  KuraEngineInput toEngineInput() {
    return KuraEngineInput(
      etiologia: etiologia,
      entorno: entorno,
      areaCm2: areaCm2,
      depthCm: depthCm,
      necrosisPct: necrosisPct,
      esfaceloPct: esfaceloPct,
      granulacionPct: granulacionPct,
      epitelizacionPct: epitelizacionPct,
      comorbilidades: comorbilidades,
      abiPieDerecho: abiRight,
      abiPieIzquierdo: abiLeft,
      esExtremidadInferior: esExtremidadInferior,
      albuminaGdl: albuminaGdl,
      tunelizacionOSocavamiento: tunneling || undermining,
      exudadoCantidad: exudadoCantidad,
      pielPerilesional: perilesionalSkin,
      infeccionCriterios: infeccionCriterios,
      tieneCuidadorIdentificado: tieneCuidadorIdentificado,
      pacienteFragil: pacienteFragil,
      wagnerGrade: wagnerGrade,
      ceapClass: ceapClass,
      wuwhsGrade: wuwhsGrade,
      agenteCausal: agenteCausal,
      subtipoVascular: subtipoVascular,
      noRevascularizable: noRevascularizable,
    );
  }

  /// Valida que los campos minimos esten completos para calcular pronostico.
  bool get hasMinimumDataForPrognosis => lengthCm > 0 && widthCm > 0;
}
