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
  CeapClass? ceapClass;
  WuwhsGrade? wuwhsGrade;
  AgenteCausal? agenteCausal;

  // ---- Evaluacion clinica ----
  double? glucoseMgDl;
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

  // ---- Medicion ----
  double lengthCm = 0;
  double widthCm = 0;
  double depthCm = 0;
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

  bool get isLowerExtremityLocation {
    final loc = bodyLocationPrimary ?? '';
    return loc.contains('pie') ||
        loc.contains('pierna') ||
        loc.contains('pantorrilla') ||
        loc.contains('talon') ||
        loc.contains('rodilla');
  }

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
    );
  }

  /// Valida que los campos minimos esten completos para calcular pronostico.
  bool get hasMinimumDataForPrognosis => lengthCm > 0 && widthCm > 0;
}
