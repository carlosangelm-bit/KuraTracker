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
  static const String rulesVersion = 'kura_rules_v1';

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
    final hayInfeccion = input.hayInfeccion;
    final composicionDesbridable = input.necrosisPct + input.esfaceloPct;

    // ---- 1. Limpieza en cada cambio de aposito (siempre) ----
    regimen.add(const RegimenComponente(
      metodo: 'Limpieza de la herida',
      producto: 'Solucion salina / Prontosan',
      justificacion: 'Limpieza en cada cambio de aposito (regla base).',
    ));

    // ---- 2. Desbridamiento (condicional + regla de seguridad ABI) ----
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
    } else if (composicionDesbridable >= 15) {
      final metodo = input.entorno == Entorno.clinica
          ? 'Cortante / combinado'
          : 'Autolitico / enzimatico / mecanico';
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
    if (input.depthCm >= 0.5 || input.tunelizacionOSocavamiento) {
      regimen.add(RegimenComponente(
        metodo: 'Relleno de cavidad',
        producto: 'Alginato de calcio / gasa impregnada',
        justificacion: input.tunelizacionOSocavamiento
            ? 'Presencia de tunelizacion/socavamiento.'
            : 'Profundidad ${input.depthCm.toStringAsFixed(1)} cm (>=0.5 cm).',
      ));
    }

    // ---- 4. Aposito secundario absorbente si exudado moderado/abundante ----
    if (input.exudadoCantidad == ExudadoCantidad.moderado ||
        input.exudadoCantidad == ExudadoCantidad.abundante) {
      regimen.add(RegimenComponente(
        metodo: 'Aposito',
        producto: 'Espuma con borde adhesivo / alta absorcion',
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
        metodo: 'Proteccion de la piel',
        producto: 'Pelicula barrera / oxido de zinc',
        justificacion:
            'Piel perilesional en riesgo: ${pielRiesgo.map((e) => e.name).join(', ')}.',
      ));
    }

    // ---- 6. Antimicrobiano topico si hay infeccion ----
    if (hayInfeccion) {
      regimen.add(const RegimenComponente(
        metodo: 'Tratamiento para la infeccion',
        producto: 'PHMB / plata',
        justificacion: 'Criterios de infeccion IWII presentes.',
      ));
    }

    // ---- 7. Educacion a paciente/cuidador ----
    final necesitaEducacion = input.entorno == Entorno.domicilio ||
        input.tieneCuidadorIdentificado ||
        input.etiologia == Etiologia.lpp;
    if (necesitaEducacion) {
      regimen.add(RegimenComponente(
        metodo: 'Educacion al paciente/cuidador',
        producto: 'Material educativo + demostracion practica',
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
          hayInfeccion: hayInfeccion,
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
      case Etiologia.otra:
        break;
    }

    // ---- 9. Interconsultas automaticas generales ----
    final necrosisExtensa = input.necrosisPct >= 30;
    final infeccionSistemica = input.infeccionCriterios.contains(
          InfeccionCriterioIwii.fiebre,
        ) ||
        input.infeccionCriterios.contains(
          InfeccionCriterioIwii.malestarGeneral,
        ) ||
        input.infeccionCriterios.contains(InfeccionCriterioIwii.celulitis);
    if (necrosisExtensa || infeccionSistemica) {
      interconsultas.add(Interconsulta(
        especialidad: 'Cirugia',
        motivo: necrosisExtensa && infeccionSistemica
            ? 'Necrosis extensa (>=30%) e infeccion sistemica.'
            : necrosisExtensa
                ? 'Necrosis extensa (>=30%).'
                : 'Infeccion sistemica (criterios IWII sistemicos).',
        esUrgente: infeccionSistemica,
      ));
    }

    if (input.etiologia == Etiologia.vascular || input.pacienteFragil) {
      interconsultas.add(Interconsulta(
        especialidad: 'Geriatria',
        motivo: input.etiologia == Etiologia.vascular
            ? 'Ulcera venosa: valoracion geriatrica integral recomendada.'
            : 'Paciente fragil: valoracion geriatrica integral recomendada.',
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
        descarga = 'Calzado terapeutico / plantilla de descarga';
        break;
      case WagnerGrade.g2:
        descarga = 'Bota walker removible (descarga parcial)';
        break;
      case WagnerGrade.g3:
      case WagnerGrade.g4:
        descarga = 'TCC (Total Contact Cast) o bota walker con descarga total';
        break;
      case WagnerGrade.g5:
        descarga = 'Descarga total + valoracion quirurgica urgente';
        break;
    }
    regimen.add(RegimenComponente(
      metodo: 'Dispositivo de descarga',
      producto: descarga,
      justificacion: 'Pie diabetico, grado Wagner ${wagner.name.toUpperCase()}.',
    ));
    regimen.add(const RegimenComponente(
      metodo: 'Manejo neuropatico',
      producto: 'Evaluacion de sensibilidad + control glucemico estrecho',
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

  static void _applyVascularRules({
    required KuraEngineInput input,
    required bool isquemiaCritica,
    required bool hayInfeccion,
    required List<RegimenComponente> regimen,
    required List<Interconsulta> interconsultas,
    required List<String> alertas,
  }) {
    if (isquemiaCritica) {
      alertas.add(
        'Compresion graduada CONTRAINDICADA: ABI/ITB < 0.5 (isquemia critica).',
      );
      return;
    }
    if (hayInfeccion) {
      alertas.add(
        'Compresion graduada diferida hasta controlar la infeccion activa.',
      );
      return;
    }
    final categoria = input.abiCategory;
    String nivel;
    switch (categoria) {
      case AbiCategory.high:
        nivel = 'Compresion fuerte (30-40 mmHg)';
        break;
      case AbiCategory.mod:
        nivel = 'Compresion reducida (18-25 mmHg), supervision estrecha';
        break;
      case AbiCategory.low:
        nivel = 'No aplica (isquemia critica)';
        break;
      case AbiCategory.na:
        nivel = 'Compresion moderada (20-30 mmHg) — confirmar ABI antes de iniciar';
        break;
    }
    regimen.add(RegimenComponente(
      metodo: 'Terapia compresiva',
      producto: nivel,
      justificacion: 'Ulcera venosa, ABI/ITB categoria: ${categoria.name}.',
    ));
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
        manejo = 'Vigilancia + cuidado de herida estandar';
        break;
      case WuwhsGrade.g2:
        manejo = 'Manejo local intensivo + reevaluacion en 48-72h';
        break;
      case WuwhsGrade.g3:
        manejo = 'Manejo local intensivo + interconsulta a cirugia';
        break;
      case WuwhsGrade.g4:
        manejo = 'Manejo urgente: dehiscencia/infeccion grave';
        break;
    }
    regimen.add(RegimenComponente(
      metodo: 'Manejo de herida quirurgica',
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
          producto: 'Profilaxis antibiotica + lavado abundante',
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
          producto: 'Exploracion quirurgica + descarte de lesion profunda',
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
          producto: 'Vigilancia de sindrome compartimental + manejo de tejidos',
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
          producto: 'Exploracion de estructuras profundas + cierre segun caso',
          justificacion: 'Agente causal: punzocortante.',
        ));
        break;
      case AgenteCausal.otro:
        regimen.add(const RegimenComponente(
          metodo: 'Manejo de herida traumatica',
          producto: 'Segun evaluacion clinica del mecanismo de lesion',
          justificacion: 'Agente causal no especificado o categoria otro.',
        ));
        break;
    }
  }
}
