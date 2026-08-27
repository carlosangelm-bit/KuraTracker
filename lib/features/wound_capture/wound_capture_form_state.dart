import 'dart:typed_data';

import '../../core/utils/wound_volume.dart';
import '../../engine/models/kura_engine_enums.dart';
import '../../engine/models/kura_engine_input.dart';
import '../../models/wound.dart' show enumByName;

/// Estado mutable del formulario de captura de herida. Se recalcula el
/// pronostico en vivo (seccion 6.1) cada vez que cambia un campo relevante.
class WoundCaptureFormState {
  // ---- Datos generales / localizacion ----
  Etiologia etiologia = Etiologia.otra;
  String? subtype;
  String? bodyLocationPrimary;
  String? bodyLocationSecondary;
  DateTime? onsetDate;
  // Fecha de la VISITA (consulta), editable: la clínica puede capturar la
  // valoración un día después de ver al paciente. Distinta de onsetDate (inicio
  // de la herida). Viaja en la instantánea del borrador para no reescribirse.
  DateTime visitDate = DateTime.now();
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
  // Subescalas de Braden elegidas con la escala completa (id -> puntaje). Null
  // si el total se fijó "a ojo" con el slider. Se persiste en el perfil del
  // paciente (risk_assessments.braden_subscores).
  Map<String, int>? bradenSubscores;

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
  int? drenajeNum; // nº de drenajes
  int? suturaNum; // nº de puntos / grapas

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
  ExudadoTipo exudadoTipo = ExudadoTipo.serohematico;
  ExudadoCantidad exudadoCantidad = ExudadoCantidad.escaso;
  Set<InfeccionCriterioIwii> infeccionCriterios = {};
  String odor = 'ninguno';
  String woundEdge = 'definido';
  Set<PielPerilesionalEstado> perilesionalSkin = {};
  // Notas clinicas / observaciones libres de la visita (opcional).
  // No bloquea el guardado si esta vacio (feat/clinical-free-notes).
  String? clinicalNotes;

  // Exploracion de miembros inferiores (vascular) y pie diabetico (0087):
  // TEXTO LIBRE por visita. Distinto del ITB NUMERICO (abiRight/abiLeft) que
  // alimenta el motor; aqui el clinico describe lo observado.
  String? itbTexto;
  String? pruebasSensibilidad;
  String? llenadoCapilar;

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
  // Bytes de cada foto capturada, indexados por su ruta/URL local, para
  // poder SUBIRLOS a Supabase Storage al guardar la valoración (antes solo se
  // guardaba la ruta local y la foto se perdía; ver fix/valoracion-photo-upload).
  Map<String, Uint8List> photoBytesByPath = {};

  // NOTA (Prompt 6, medición oficial): el área 2D se calcula como
  // largo × ancho (estimado manual rectangular), NO con la fórmula de elipse
  // (0.785). La MEDICIÓN CUANTITATIVA OFICIAL del seguimiento es el VOLUMEN por
  // la fórmula de Kundin (V = L × A × P × 0.327, ver core/utils/wound_volume.dart),
  // capturado en valoración y seguimiento; la planimetría de eKare es la fuente
  // de área trazada cuando el dato proviene de eKare.
  // Área 2D estimada por la elipse (L × A × 0.785), validada por María 2026-07.
  // Alimenta el modelo pronóstico (logarea); las predicciones se corren hasta
  // recalibrar (decisión aceptada). Ver core/utils/wound_volume.dart.
  double get areaCm2 => WoundVolumeCalculator.ellipseArea(lengthCm, widthCm);

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

  /// Muestra la exploracion de miembros inferiores (ITB/sensibilidad/llenado
  /// capilar, texto libre): ulcera vascular (miembros inferiores) o pie
  /// diabetico.
  bool get showLowerLimbExam =>
      etiologia == Etiologia.vascular || etiologia == Etiologia.pieDiabetico;

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
      // Braden ya se captura en LPP; se pasa al motor para sugerir la
      // modalidad de tratamiento (Prompt 4). Los demás campos nuevos del
      // motor (lppRecurrente, cuidadosPaliativos, dolorCronico, tunnelDepthCm,
      // sobreArticulacion) quedan pendientes de captura en el formulario.
      bradenScore: bradenScore,
    );
  }

  /// Valida que los campos minimos esten completos para calcular pronostico.
  bool get hasMinimumDataForPrognosis => lengthCm > 0 && widthCm > 0;

  /// Instantánea de los CAMPOS del formulario (no incluye fotos ni las
  /// comorbilidades, que se recargan del paciente). Se guarda en un borrador de
  /// valoración (consultations.draft_form_state) para reabrirlo editable.
  Map<String, dynamic> toJson() => {
        'etiologia': etiologia.name,
        'subtype': subtype,
        'bodyLocationPrimary': bodyLocationPrimary,
        'bodyLocationSecondary': bodyLocationSecondary,
        'onsetDate': onsetDate?.toIso8601String(),
        'visitDate': visitDate.toIso8601String(),
        'wagnerGrade': wagnerGrade?.name,
        'wifiWound': wifiWound,
        'wifiIschemia': wifiIschemia,
        'wifiInfection': wifiInfection,
        'ceapClass': ceapClass?.name,
        'subtipoVascular': subtipoVascular?.name,
        'noRevascularizable': noRevascularizable,
        'wuwhsGrade': wuwhsGrade?.name,
        'agenteCausal': agenteCausal?.name,
        'bradenScore': bradenScore,
        'bradenSubscores': bradenSubscores,
        'updSubtipo': updSubtipo?.name,
        'texasGrade': texasGrade?.name,
        'texasStage': texasStage?.name,
        'idsaIwgdf': idsaIwgdf?.name,
        'sensibilidadProtectora': sensibilidadProtectora?.name,
        'rutherford': rutherford?.name,
        'npuapEstadio': npuapEstadio?.name,
        'claseContaminacion': claseContaminacion?.name,
        'tipoCierre': tipoCierre?.name,
        'drenajeTipo': drenajeTipo?.name,
        'suturaTipo': suturaTipo?.name,
        'drenajeNum': drenajeNum,
        'suturaNum': suturaNum,
        'glucoseMgDl': glucoseMgDl,
        'hba1cPct': hba1cPct,
        'firstAssessmentDate': firstAssessmentDate?.toIso8601String(),
        'edema': edema,
        'pain': pain,
        'painType': painType,
        'painDuration': painDuration,
        'painVas': painVas,
        'exudadoTipo': exudadoTipo.name,
        'exudadoCantidad': exudadoCantidad.name,
        'infeccionCriterios': infeccionCriterios.map((e) => e.name).toList(),
        'odor': odor,
        'woundEdge': woundEdge,
        'perilesionalSkin': perilesionalSkin.map((e) => e.name).toList(),
        'clinicalNotes': clinicalNotes,
        'itbTexto': itbTexto,
        'pruebasSensibilidad': pruebasSensibilidad,
        'llenadoCapilar': llenadoCapilar,
        'lengthCm': lengthCm,
        'widthCm': widthCm,
        'depthCm': depthCm,
        'volumeCm3': volumeCm3,
        'tunneling': tunneling,
        'undermining': undermining,
        'granulacionPct': granulacionPct,
        'esfaceloPct': esfaceloPct,
        'necrosisPct': necrosisPct,
        'epitelizacionPct': epitelizacionPct,
        'capturedBeforeDebridement': capturedBeforeDebridement,
        'esExtremidadInferior': esExtremidadInferior,
        'abiRight': abiRight,
        'abiLeft': abiLeft,
        'albuminaGdl': albuminaGdl,
        'entorno': entorno.name,
      };

  /// Rehidrata los campos desde una instantánea [j] (ver [toJson]). No toca
  /// fotos ni comorbilidades. Tolerante: lo ausente conserva el valor actual.
  void applyJson(Map<String, dynamic> j) {
    double? d(Object? v) => (v as num?)?.toDouble();
    int? i(Object? v) => (v as num?)?.toInt();
    DateTime? dt(Object? v) => v == null ? null : DateTime.parse(v as String);
    Set<T> setOf<T extends Enum>(List<T> values, Object? v) =>
        ((v as List?) ?? const [])
            .map((e) => enumByName(values, e))
            .whereType<T>()
            .toSet();

    etiologia = enumByName(Etiologia.values, j['etiologia']) ?? etiologia;
    subtype = j['subtype'] as String?;
    bodyLocationPrimary = j['bodyLocationPrimary'] as String?;
    bodyLocationSecondary = j['bodyLocationSecondary'] as String?;
    onsetDate = dt(j['onsetDate']);
    visitDate = dt(j['visitDate']) ?? visitDate;
    wagnerGrade = enumByName(WagnerGrade.values, j['wagnerGrade']);
    wifiWound = i(j['wifiWound']);
    wifiIschemia = i(j['wifiIschemia']);
    wifiInfection = i(j['wifiInfection']);
    ceapClass = enumByName(CeapClass.values, j['ceapClass']);
    subtipoVascular = enumByName(SubtipoVascular.values, j['subtipoVascular']);
    noRevascularizable = j['noRevascularizable'] as bool? ?? false;
    wuwhsGrade = enumByName(WuwhsGrade.values, j['wuwhsGrade']);
    agenteCausal = enumByName(AgenteCausal.values, j['agenteCausal']);
    bradenScore = i(j['bradenScore']);
    bradenSubscores = (j['bradenSubscores'] as Map?)
        ?.map((k, v) => MapEntry(k.toString(), (v as num).toInt()));
    updSubtipo = enumByName(UpdSubtipo.values, j['updSubtipo']);
    texasGrade = enumByName(TexasGrade.values, j['texasGrade']);
    texasStage = enumByName(TexasStage.values, j['texasStage']);
    idsaIwgdf = enumByName(IdsaIwgdf.values, j['idsaIwgdf']);
    sensibilidadProtectora =
        enumByName(SensibilidadProtectora.values, j['sensibilidadProtectora']);
    rutherford = enumByName(Rutherford.values, j['rutherford']);
    npuapEstadio = enumByName(NpuapEstadio.values, j['npuapEstadio']);
    claseContaminacion =
        enumByName(ClaseContaminacion.values, j['claseContaminacion']);
    tipoCierre = enumByName(TipoCierre.values, j['tipoCierre']);
    drenajeTipo = enumByName(DrenajeTipo.values, j['drenajeTipo']);
    suturaTipo = enumByName(SuturaTipo.values, j['suturaTipo']);
    drenajeNum = i(j['drenajeNum']);
    suturaNum = i(j['suturaNum']);
    glucoseMgDl = d(j['glucoseMgDl']);
    hba1cPct = d(j['hba1cPct']);
    firstAssessmentDate = dt(j['firstAssessmentDate']);
    edema = j['edema'] as String? ?? edema;
    pain = j['pain'] as bool? ?? pain;
    painType = j['painType'] as String?;
    painDuration = j['painDuration'] as String?;
    painVas = i(j['painVas']) ?? painVas;
    exudadoTipo = enumByName(ExudadoTipo.values, j['exudadoTipo']) ?? exudadoTipo;
    exudadoCantidad =
        enumByName(ExudadoCantidad.values, j['exudadoCantidad']) ?? exudadoCantidad;
    infeccionCriterios =
        setOf(InfeccionCriterioIwii.values, j['infeccionCriterios']);
    odor = j['odor'] as String? ?? odor;
    woundEdge = j['woundEdge'] as String? ?? woundEdge;
    perilesionalSkin =
        setOf(PielPerilesionalEstado.values, j['perilesionalSkin']);
    clinicalNotes = j['clinicalNotes'] as String?;
    itbTexto = j['itbTexto'] as String?;
    pruebasSensibilidad = j['pruebasSensibilidad'] as String?;
    llenadoCapilar = j['llenadoCapilar'] as String?;
    lengthCm = d(j['lengthCm']) ?? lengthCm;
    widthCm = d(j['widthCm']) ?? widthCm;
    depthCm = d(j['depthCm']) ?? depthCm;
    volumeCm3 = d(j['volumeCm3']);
    tunneling = j['tunneling'] as bool? ?? tunneling;
    undermining = j['undermining'] as bool? ?? undermining;
    granulacionPct = d(j['granulacionPct']) ?? granulacionPct;
    esfaceloPct = d(j['esfaceloPct']) ?? esfaceloPct;
    necrosisPct = d(j['necrosisPct']) ?? necrosisPct;
    epitelizacionPct = d(j['epitelizacionPct']) ?? epitelizacionPct;
    capturedBeforeDebridement =
        j['capturedBeforeDebridement'] as bool? ?? capturedBeforeDebridement;
    esExtremidadInferior =
        j['esExtremidadInferior'] as bool? ?? esExtremidadInferior;
    abiRight = d(j['abiRight']);
    abiLeft = d(j['abiLeft']);
    albuminaGdl = d(j['albuminaGdl']);
    entorno = enumByName(Entorno.values, j['entorno']) ?? entorno;
  }
}
