import '../models/kura_engine_enums.dart';
import '../models/kura_engine_input.dart';
import '../models/kura_engine_output.dart';

/// Motor de reglas de tratamiento determinístico — sección 8.4.
///
/// A partir del escenario pronosticado (A/B/C), la etiología y las
/// condiciones clínicas capturadas, genera la lista de componentes del
/// régimen de tratamiento, interconsultas automáticas y alertas de
/// seguridad. Es puramente determinístico (sin aleatoriedad ni ML), por lo
/// que es trivial de testear y auditar.
///
/// SEGURIDAD CRÍTICA: si ABI < 0.5 (isquemia crítica), el motor NUNCA
/// sugiere desbridamiento; en su lugar genera una alerta y una
/// interconsulta urgente a angiología. Esta regla se aplica sin
/// excepciones, independientemente del escenario pronosticado.
class KuraTreatmentRulesEngine {
  static const String rulesVersion = 'kura_rules_v2';

  /// Genera el régimen completo de tratamiento + interconsultas + alertas.
  static ({
    List<RegimenComponente> regimen,
    List<Interconsulta> interconsultas,
    List<String> alertas,
  }) generate({
    required KuraEngineInput input,
    required KuraScenario scenario,
  }) {
    final regimen = <RegimenComponente>[];
    final interconsultas = <Interconsulta>[];
    final alertas = <String>[];

    final isquemiaCritica = input.isquemiaCritica;
    // kura_rules_v2: la infeccion se escalona en dos niveles.
    // - sospechaInfeccionLocal: >=2 factores locales significativos.
    // - infeccionPropagada: eritema >2cm, celulitis, fiebre o malestar general.
    final sospechaInfeccionLocal = input.sospechaInfeccionLocal;
    final infeccionPropagada = input.infeccionPropagada;
    // kura_rules_v2 (correccion): infeccionSistemica es el subconjunto de
    // infeccionPropagada confirmado clinicamente (celulitis/fiebre/malestar).
    // Rige EXCLUSIVAMENTE la suspension de la compresion venosa graduada.
    final infeccionSistemica = input.infeccionSistemica;
    final composicionDesbridable = input.necrosisPct + input.esfaceloPct;
    // Terapia seca (Protocolo "Terapia seca"): úlcera arterial/isquémica, no
    // revascularizable, o isquemia crítica. Suprime la cura húmeda por
    // defecto, contraindica compresión y desbridamiento cortante, y protege
    // la escara seca estable.
    final terapiaSeca = input.requiereTerapiaSeca;

    // ---- 1. Limpieza (cura húmeda) o Terapia seca (arterial/isquémica) ----
    if (terapiaSeca) {
      regimen.add(const RegimenComponente(
        metodo: 'Terapia seca',
        producto:
            'Yodopovidona 10%, secado al aire, proteger escara estable',
        justificacion:
            'Úlcera arterial/isquémica o no revascularizable: se suprime la '
            'cura húmeda por defecto. Mantener la escara seca estable como '
            'barrera biológica (Protocolo "Terapia seca").',
      ));
    } else {
      regimen.add(const RegimenComponente(
        metodo: 'Limpieza de la herida',
        producto: 'Solución salina / Prontosan',
        justificacion: 'Limpieza en cada cambio de aposito (regla base).',
      ));
    }

    // ---- 2. Desbridamiento (condicional + reglas de seguridad ABI) ----
    if (isquemiaCritica) {
      alertas.add(
        'ALERTA DE SEGURIDAD: ABI/ITB < 0.5 (isquemia critica). '
        'NO se recomienda desbridamiento. Referir a angiologia para '
        'revascularizacion antes de cualquier desbridamiento.',
      );
      interconsultas.add(const Interconsulta(
        especialidad: 'Angiologia / Cirugia vascular',
        motivo: 'Isquemia critica (ABI/ITB < 0.5). Evaluar revascularizacion '
            'antes de desbridar.',
        esUrgente: true,
      ));
    } else if (terapiaSeca) {
      // Arterial/isquémica o no revascularizable, sin isquemia crítica:
      // contraindicar desbridamiento cortante y NO desbridar escara seca
      // estable aunque necrosis >=15% (Protocolo "Terapia seca").
      alertas.add(
        'Terapia seca: desbridamiento CORTANTE CONTRAINDICADO. No desbridar '
        'escara seca estable aunque necrosis/esfacelo >=15%. Desbridamiento '
        'únicamente autolítico/enzimático "según Doppler/angiólogo" si '
        'aparece esfacelo húmedo o signos de infección.',
      );
    } else if (composicionDesbridable >= 15) {
      final metodo = input.entorno == Entorno.clinica
          ? 'Cortante / combinado'
          : 'Autolítico / enzimático / mecánico';
      regimen.add(RegimenComponente(
        metodo: 'Desbridamiento',
        producto: metodo,
        justificacion:
            'Esfacelo + necrosis = ${composicionDesbridable.toStringAsFixed(0)}% '
            '(>=15%) y sin isquemia critica. Metodo segun entorno '
            '(${input.entorno == Entorno.clinica ? 'clinica' : 'domicilio'}).',
      ));
    }

    // ---- 3. Relleno si profundidad >=0.5cm o cavidad/tunelizacion ----
    // No aplica en terapia seca: el relleno húmedo (alginato) contradice el
    // secado al aire y la conservación de la escara seca estable.
    if (!terapiaSeca &&
        (input.depthCm >= 0.5 || input.tunelizacionOSocavamiento)) {
      regimen.add(RegimenComponente(
        metodo: 'Relleno de cavidad',
        producto: 'Alginato de calcio / gasa impregnada',
        justificacion: input.tunelizacionOSocavamiento
            ? 'Presencia de tunelizacion/socavamiento.'
            : 'Profundidad ${input.depthCm.toStringAsFixed(1)} cm (>=0.5 cm).',
      ));
    }

    // ---- 4. Aposito secundario absorbente si exudado moderado/abundante ----
    // No aplica en terapia seca: el objetivo es mantener la escara seca, no
    // gestionar humedad con apósitos absorbentes.
    if (!terapiaSeca &&
        (input.exudadoCantidad == ExudadoCantidad.moderado ||
            input.exudadoCantidad == ExudadoCantidad.abundante)) {
      regimen.add(RegimenComponente(
        metodo: 'Apósito',
        producto: 'Espuma con borde adhesivo / alta absorción',
        justificacion: 'Exudado '
            '${input.exudadoCantidad == ExudadoCantidad.moderado ? 'moderado' : 'abundante'}: '
            'requiere aposito secundario absorbente.',
      ));
    }

    // ---- 5. Proteccion perilesional si piel seca/fragil/macerada ----
    final pielRiesgo = input.pielPerilesional.intersection({
      PielPerilesionalEstado.seca,
      PielPerilesionalEstado.fragil,
      PielPerilesionalEstado.macerada,
    });
    if (pielRiesgo.isNotEmpty) {
      regimen.add(RegimenComponente(
        metodo: 'Protección de la piel',
        producto: 'Película barrera / óxido de zinc',
        justificacion:
            'Piel perilesional en riesgo: ${pielRiesgo.map((e) => e.name).join(', ')}.',
      ));
    }

    // ---- 6. Tratamiento escalonado de infeccion (kura_rules_v2) ----
    // Regla clinica final:
    // - sospechaInfeccionLocal && !infeccionPropagada -> regimen local +
    //   antimicrobiano topico (PHMB/plata).
    // - infeccionPropagada -> interconsulta urgente + tratamiento sistemico /
    //   referencia hospitalaria; el topico NO se recomienda para propagacion
    //   (no resuelve infeccion propagada).
    // - <2 factores locales o solo aumento de exudado -> no hay infeccion ->
    //   no se agrega antimicrobiano.
    if (infeccionPropagada) {
      regimen.add(const RegimenComponente(
        metodo: 'Tratamiento para la infección',
        producto: 'Tratamiento sistémico / referencia hospitalaria',
        justificacion: 'Infeccion propagada (eritema >2cm, celulitis, fiebre '
            'o malestar general). Requiere manejo sistemico; el '
            'antimicrobiano topico no resuelve infeccion propagada.',
      ));
      interconsultas.add(const Interconsulta(
        especialidad: 'Infectologia / Cirugia',
        motivo: 'Infeccion propagada: eritema >2cm, celulitis, fiebre o '
            'malestar general. Se requiere tratamiento sistemico y '
            'valoracion hospitalaria.',
        esUrgente: true,
      ));
    } else if (sospechaInfeccionLocal) {
      regimen.add(RegimenComponente(
        metodo: 'Tratamiento para la infección',
        producto: 'PHMB / plata (antimicrobiano tópico)',
        justificacion: 'Sospecha de infeccion local: '
            '${input.nFactoresLocalesInfeccion} factores locales '
            'significativos presentes (>=2).',
      ));
    }

    // ---- 7. Educacion a paciente/cuidador ----
    final necesitaEducacion = input.entorno == Entorno.domicilio ||
        input.tieneCuidadorIdentificado ||
        input.etiologia == Etiologia.lpp;
    if (necesitaEducacion) {
      regimen.add(RegimenComponente(
        metodo: 'Educación al paciente/cuidador',
        producto: 'Material educativo + demostración práctica',
        justificacion: [
          if (input.entorno == Entorno.domicilio) 'atencion en domicilio',
          if (input.tieneCuidadorIdentificado) 'cuidador identificado',
          if (input.etiologia == Etiologia.lpp) 'etiologia LPP',
        ].join(', '),
      ));
    }

    // ---- 8. Reglas especificas por etiologia ----
    switch (input.etiologia) {
      case Etiologia.pieDiabetico:
        _applyPieDiabeticoRules(
          input: input,
          regimen: regimen,
          interconsultas: interconsultas,
          alertas: alertas,
        );
        break;
      case Etiologia.vascular:
        _applyVascularRules(
          input: input,
          isquemiaCritica: isquemiaCritica,
          infeccionSistemica: infeccionSistemica,
          terapiaSeca: terapiaSeca,
          regimen: regimen,
          interconsultas: interconsultas,
          alertas: alertas,
        );
        break;
      case Etiologia.quirurgica:
        _applyQuirurgicaRules(
          input: input,
          regimen: regimen,
          interconsultas: interconsultas,
          alertas: alertas,
        );
        break;
      case Etiologia.traumatica:
        _applyTraumaticaRules(
          input: input,
          regimen: regimen,
          interconsultas: interconsultas,
        );
        break;
      case Etiologia.lpp:
        _applyLppRules(input: input, regimen: regimen);
        break;
      case Etiologia.otra:
        break;
    }

    // ---- 9. Interconsultas automaticas generales ----
    // NOTA: la interconsulta urgente de infeccion propagada ya se agrega en
    // el paso 6 (Infectologia/Cirugia). Aqui se mantiene una interconsulta
    // adicional a Cirugia por necrosis extensa y/o propagacion, ya que ambos
    // escenarios pueden requerir valoracion quirurgica independiente de la
    // infectologica.
    final necrosisExtensa = input.necrosisPct >= 30;
    if (necrosisExtensa || infeccionPropagada) {
      interconsultas.add(Interconsulta(
        especialidad: 'Cirugia',
        motivo: necrosisExtensa && infeccionPropagada
            ? 'Necrosis extensa (>=30%) e infeccion propagada.'
            : necrosisExtensa
                ? 'Necrosis extensa (>=30%).'
                : 'Infeccion propagada (criterios IWII de propagacion).',
        esUrgente: infeccionPropagada,
      ));
    }

    // Interconsulta a GERIATRIA (Protocolo "Interconsultas"): úlcera vascular
    // (MMII), paciente frágil, LPP recurrente, cuidados paliativos o dolor
    // crónico. Se listan todos los motivos aplicables.
    final motivosGeriatria = <String>[
      if (input.etiologia == Etiologia.vascular) 'úlcera vascular (MMII)',
      if (input.pacienteFragil) 'paciente frágil',
      if (input.etiologia == Etiologia.lpp && input.lppRecurrente)
        'LPP recurrente',
      if (input.cuidadosPaliativos) 'cuidados paliativos',
      if (input.dolorCronico) 'dolor crónico',
    ];
    if (motivosGeriatria.isNotEmpty) {
      interconsultas.add(Interconsulta(
        especialidad: 'Geriatria',
        motivo: 'Valoración geriátrica integral recomendada: '
            '${motivosGeriatria.join(', ')}.',
      ));
    }

    // Interconsulta a ANGIOLOGIA por ITB anómalo (< 0.9 o > 1.4), para
    // CUALQUIER etiología con extremidad inferior evaluada (Protocolo
    // "Interconsultas"). Coordinado con el fix arterial (Prompt 1): las reglas
    // vasculares y la de isquemia crítica ya pueden haber agregado una
    // interconsulta a angiología; aquí se evita duplicarla.
    final yaHayAngiologia = interconsultas
        .any((i) => i.especialidad.toLowerCase().contains('angiolog'));
    if (input.requiereDerivacionAngiologiaPorItb && !yaHayAngiologia) {
      interconsultas.add(Interconsulta(
        especialidad: 'Angiologia / Cirugia vascular',
        motivo: 'ITB anómalo (${_itbLabel(input)}): < 0.9 o > 1.4, fuera del '
            'rango seguro. Valoración angiológica (Protocolo "Interconsultas").',
      ));
    }

    // Referencia por TÚNEL profundo (> 7 cm) o COMPROMISO ARTICULAR (Protocolo
    // "Interconsultas").
    if (input.requiereReferenciaPorTunel) {
      interconsultas.add(Interconsulta(
        especialidad: 'Cirugia',
        motivo: 'Túnel profundo (${input.tunnelDepthCm!.toStringAsFixed(1)} cm '
            '> 7 cm): descartar trayecto fistuloso/absceso; referencia '
            'quirúrgica (Protocolo "Interconsultas").',
      ));
    }
    if (input.requiereReferenciaPorArticulacion) {
      interconsultas.add(const Interconsulta(
        especialidad: 'Cirugia / Ortopedia',
        motivo: 'Herida con compromiso articular: descartar artritis séptica / '
            'exposición articular; referencia (Protocolo "Interconsultas").',
      ));
    }

    // ---- 10. Alerta adicional por escenario C (contencion) ----
    if (scenario == KuraScenario.c) {
      alertas.add(
        'Escenario C: cierre no esperado en el horizonte evaluado. '
        'Enfoque de confort, prevencion de complicaciones y control de '
        'sintomas (dolor, exudado, olor).',
      );
    }

    return (regimen: regimen, interconsultas: interconsultas, alertas: alertas);
  }

  static void _applyPieDiabeticoRules({
    required KuraEngineInput input,
    required List<RegimenComponente> regimen,
    required List<Interconsulta> interconsultas,
    required List<String> alertas,
  }) {
    final wagner = input.wagnerGrade ?? WagnerGrade.g0;
    String descarga;
    switch (wagner) {
      case WagnerGrade.g0:
      case WagnerGrade.g1:
        descarga = 'Calzado terapéutico / plantilla de descarga';
        break;
      case WagnerGrade.g2:
        descarga = 'Bota walker removible (descarga parcial)';
        break;
      case WagnerGrade.g3:
      case WagnerGrade.g4:
        descarga = 'TCC (Total Contact Cast) o bota walker con descarga total';
        break;
      case WagnerGrade.g5:
        descarga = 'Descarga total + valoración quirúrgica urgente';
        break;
    }
    regimen.add(RegimenComponente(
      metodo: 'Dispositivo de descarga',
      producto: descarga,
      justificacion: 'Pie diabetico, grado Wagner ${wagner.name.toUpperCase()}.',
    ));
    regimen.add(const RegimenComponente(
      metodo: 'Manejo neuropático',
      producto: 'Evaluación de sensibilidad + control glucémico estrecho',
      justificacion: 'Pie diabetico: manejo neuropatico integral.',
    ));
    if (wagner == WagnerGrade.g3 ||
        wagner == WagnerGrade.g4 ||
        wagner == WagnerGrade.g5) {
      interconsultas.add(Interconsulta(
        especialidad: 'Cirugia / Ortopedia',
        motivo: 'Pie diabetico Wagner ${wagner.name.toUpperCase()}.',
        esUrgente: wagner == WagnerGrade.g4 || wagner == WagnerGrade.g5,
      ));
    }
  }

  static void _applyLppRules({
    required KuraEngineInput input,
    required List<RegimenComponente> regimen,
  }) {
    // Modalidad de tratamiento según el rango de Braden (Protocolo LPP):
    // riesgo alto/muy alto (Braden <=12) -> a cargo de la clínica; riesgo
    // moderado/bajo/sin riesgo (>=13) -> tratamiento compartido con el
    // cuidador. Ver KuraEngineInput.bradenModalidad para las bandas.
    final modalidad = input.bradenModalidad;
    if (modalidad != null) {
      regimen.add(RegimenComponente(
        metodo: 'Modalidad de tratamiento (LPP)',
        producto: modalidad.label,
        justificacion:
            'LPP con Braden ${input.bradenScore} (${input.bradenScore! <= 12 ? 'riesgo alto/muy alto' : 'riesgo moderado/bajo'}): '
            'modalidad ${modalidad == ModalidadTratamiento.aCargoClinica ? 'a cargo de la clínica' : 'compartida'} '
            '(Protocolo LPP).',
      ));
    }
  }

  static void _applyVascularRules({
    required KuraEngineInput input,
    required bool isquemiaCritica,
    required bool infeccionSistemica,
    required bool terapiaSeca,
    required List<RegimenComponente> regimen,
    required List<Interconsulta> interconsultas,
    required List<String> alertas,
  }) {
    // ---- Rama ARTERIAL / ISQUÉMICA / NO REVASCULARIZABLE (terapia seca) ----
    // La compresión NUNCA se indica aquí: aplicar compresión venosa a una
    // úlcera arterial puede agravar la isquemia (Protocolo "Úlceras MMII").
    if (terapiaSeca) {
      if (isquemiaCritica) {
        // Se conserva la alerta histórica de contraindicación por isquemia
        // crítica (ABI < 0.5); la interconsulta urgente a angiología ya se
        // agregó en el paso 2 (desbridamiento).
        alertas.add(
          'Compresion graduada CONTRAINDICADA: ABI/ITB < 0.5 (isquemia critica).',
        );
      } else {
        alertas.add(
          'Compresión NUNCA indicada en úlcera arterial/isquémica o no '
          'revascularizable (terapia seca).',
        );
        // Derivar a angiología para valorar revascularización / plan de
        // terapia seca (Protocolo "Interconsultas").
        interconsultas.add(Interconsulta(
          especialidad: 'Angiologia / Cirugia vascular',
          motivo:
              'Úlcera arterial/isquémica o no revascularizable. Valorar '
              'revascularización y confirmar plan de terapia seca (Doppler). '
              'ITB=${_itbLabel(input)}.',
          esUrgente: false,
        ));
      }
      return;
    }

    // ---- Rama VENOSA / MIXTA (candidata a compresión) ----
    // kura_rules_v2 (correccion): la compresion solo se SUSPENDE ante
    // infeccion sistemica confirmada (celulitis, fiebre o malestar general).
    if (infeccionSistemica) {
      alertas.add(
        'Compresion graduada SUSPENDIDA hasta controlar la infeccion '
        'sistemica (celulitis, fiebre o malestar general).',
      );
      return;
    }
    // Sospecha de infeccion local o eritema >2cm aislado (sin
    // celulitis/fiebre/malestar general): la compresion CONTINUA con
    // vigilancia estrecha. En este punto infeccionSistemica ya es false, por
    // lo que input.infeccionPropagada solo puede provenir de eritemaMayor2cm.
    if (input.sospechaInfeccionLocal || input.infeccionPropagada) {
      alertas.add(
        'Compresion graduada CONTINUA con vigilancia estrecha: sospecha de '
        'infeccion local o eritema >2cm aislado, sin criterios de infeccion '
        'sistemica (celulitis/fiebre/malestar general).',
      );
    }

    // Compresión calibrada a la tabla del protocolo "Úlceras MMII". La
    // derivación a angiología por ITB anómalo (>1.4 o <0.9) se centraliza en
    // el paso 9 (interconsultas generales) para no duplicarla ni acotarla a la
    // etiología vascular.
    final band = input.itbCompresionBand;
    switch (band) {
      case ItbCompresionBand.incompresible:
        // ITB > 1.4: arterias incompresibles/calcificación. NO comprimir.
        alertas.add(
          'Compresión NO aplicada: ITB > 1.4 (arterias incompresibles / '
          'calcificación). Derivar a angiología (Protocolo "Úlceras MMII").',
        );
        return;
      case ItbCompresionBand.noAplica:
        // ITB < 0.6: perfusión insuficiente para compresión.
        alertas.add(
          'Compresión NO aplicada: ITB < 0.6 (perfusión insuficiente). '
          'Derivar a angiología (Protocolo "Úlceras MMII").',
        );
        return;
      case ItbCompresionBand.fuerte:
        regimen.add(RegimenComponente(
          metodo: 'Terapia compresiva',
          producto: 'Compresión fuerte (30-40 mmHg)',
          justificacion:
              'Úlcera venosa/mixta, ITB ${_itbLabel(input)} (0.9-1.4): '
              'compresión fuerte (Protocolo "Úlceras MMII").',
        ));
        break;
      case ItbCompresionBand.precaucion:
        regimen.add(RegimenComponente(
          metodo: 'Terapia compresiva',
          producto: 'Compresión con precaución (multicomponente reducida)',
          justificacion:
              'Úlcera venosa/mixta, ITB ${_itbLabel(input)} (0.8-0.89): '
              'compresión con precaución y vigilancia estrecha; derivar a '
              'angiología (Protocolo "Úlceras MMII").',
        ));
        break;
      case ItbCompresionBand.reducida:
        regimen.add(RegimenComponente(
          metodo: 'Terapia compresiva',
          producto: 'Compresión reducida (máx 20 mmHg)',
          justificacion:
              'Úlcera venosa/mixta, ITB ${_itbLabel(input)} (0.6-0.8): '
              'compresión reducida a máx 20 mmHg y derivar a angiología '
              '(Protocolo "Úlceras MMII").',
        ));
        break;
      case ItbCompresionBand.na:
        regimen.add(const RegimenComponente(
          metodo: 'Terapia compresiva',
          producto:
              'Compresión moderada (20-30 mmHg) — confirmar ITB antes de iniciar',
          justificacion:
              'Úlcera venosa sin ITB documentado: medir ITB antes de iniciar '
              'compresión (Protocolo "Úlceras MMII").',
        ));
        break;
    }
  }

  /// Etiqueta legible del ITB mínimo para justificaciones/interconsultas.
  static String _itbLabel(KuraEngineInput input) {
    final v = input.abiMinimo;
    return v == null ? 'no documentado' : v.toStringAsFixed(2);
  }

  static void _applyQuirurgicaRules({
    required KuraEngineInput input,
    required List<RegimenComponente> regimen,
    required List<Interconsulta> interconsultas,
    required List<String> alertas,
  }) {
    final grade = input.wuwhsGrade ?? WuwhsGrade.g1;
    String manejo;
    switch (grade) {
      case WuwhsGrade.g1:
        manejo = 'Vigilancia + cuidado de herida estándar';
        break;
      case WuwhsGrade.g2:
        manejo = 'Manejo local intensivo + reevaluación en 48-72h';
        break;
      case WuwhsGrade.g3:
        manejo = 'Manejo local intensivo + interconsulta a cirugía';
        break;
      case WuwhsGrade.g4:
        manejo = 'Manejo urgente: dehiscencia/infección grave';
        break;
    }
    regimen.add(RegimenComponente(
      metodo: 'Manejo de herida quirúrgica',
      producto: manejo,
      justificacion: 'Grado WUWHS ${grade.name.toUpperCase()}.',
    ));
    if (grade == WuwhsGrade.g3 || grade == WuwhsGrade.g4) {
      interconsultas.add(Interconsulta(
        especialidad: 'Cirugia',
        motivo: 'Herida quirurgica WUWHS ${grade.name.toUpperCase()}.',
        esUrgente: grade == WuwhsGrade.g4,
      ));
      if (grade == WuwhsGrade.g4) {
        alertas.add(
          'ALERTA: WUWHS G4 detectado. Requiere valoracion QUIRURGICA URGENTE.',
        );
      }
    }
  }

  static void _applyTraumaticaRules({
    required KuraEngineInput input,
    required List<RegimenComponente> regimen,
    required List<Interconsulta> interconsultas,
  }) {
    final agente = input.agenteCausal ?? AgenteCausal.otro;
    switch (agente) {
      case AgenteCausal.mordedura:
        regimen.add(const RegimenComponente(
          metodo: 'Manejo de herida por mordedura',
          producto: 'Profilaxis antibiótica + lavado abundante',
          justificacion: 'Agente causal: mordedura (alto riesgo de infeccion).',
        ));
        interconsultas.add(const Interconsulta(
          especialidad: 'Infectologia',
          motivo: 'Herida por mordedura: valorar profilaxis antirrabica/antibiotica.',
        ));
        break;
      case AgenteCausal.armaFuego:
        regimen.add(const RegimenComponente(
          metodo: 'Manejo de herida por arma de fuego',
          producto: 'Exploración quirúrgica + descarte de lesión profunda',
          justificacion: 'Agente causal: arma de fuego.',
        ));
        interconsultas.add(const Interconsulta(
          especialidad: 'Cirugia de trauma',
          motivo: 'Herida por arma de fuego: exploracion quirurgica.',
          esUrgente: true,
        ));
        break;
      case AgenteCausal.aplastamiento:
        regimen.add(const RegimenComponente(
          metodo: 'Manejo de herida por aplastamiento',
          producto: 'Vigilancia de síndrome compartimental + manejo de tejidos',
          justificacion: 'Agente causal: aplastamiento.',
        ));
        interconsultas.add(const Interconsulta(
          especialidad: 'Cirugia / Ortopedia',
          motivo: 'Herida por aplastamiento: descartar sindrome compartimental.',
          esUrgente: true,
        ));
        break;
      case AgenteCausal.punzocortante:
        regimen.add(const RegimenComponente(
          metodo: 'Manejo de herida punzocortante',
          producto: 'Exploración de estructuras profundas + cierre según caso',
          justificacion: 'Agente causal: punzocortante.',
        ));
        break;
      case AgenteCausal.otro:
        regimen.add(const RegimenComponente(
          metodo: 'Manejo de herida traumática',
          producto: 'Según evaluación clínica del mecanismo de lesión',
          justificacion: 'Agente causal no especificado o categoria otro.',
        ));
        break;
    }
  }
}
