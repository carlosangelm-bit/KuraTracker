// Catálogo de alarmas de terapia VAC (NPWT) — módulo VAC Fase 2.
//
// BORRADOR clínico/técnico: severidad y pasos son un punto de partida y deben
// validarse contra la documentación de cada equipo (Solventum). La asesoría
// fina la dará el bot (CustomGPT) en la Fase 3. Regla de oro: las alarmas
// CRÍTICAS nunca las "cierra" el sistema — empujan a reinstalar la terapia y
// contactar a la guardia.

import 'vac_therapy.dart';

enum VacAlarmSeverity { noCritica, critica }

extension VacAlarmSeverityX on VacAlarmSeverity {
  String get label {
    switch (this) {
      case VacAlarmSeverity.noCritica:
        return 'No crítica';
      case VacAlarmSeverity.critica:
        return 'Crítica';
    }
  }
}

/// Una alarma del catálogo: aplica a ciertos equipos, con severidad y pasos.
class VacAlarm {
  final String code;
  final String label;
  final VacAlarmSeverity severity;
  final List<VacEquipment> equipment; // vacío = aplica a todos
  final List<String> steps;
  const VacAlarm({
    required this.code,
    required this.label,
    required this.severity,
    this.equipment = const [],
    required this.steps,
  });

  bool appliesTo(VacEquipment e) => equipment.isEmpty || equipment.contains(e);
}

/// Catálogo estático (borrador). La lista larga la cubre el bot en Fase 3.
class VacAlarmCatalog {
  static const List<VacAlarm> all = [
    VacAlarm(
      code: 'fuga',
      label: 'Fuga / pérdida de sello',
      severity: VacAlarmSeverity.noCritica,
      steps: [
        'Pasa el dedo por los bordes del apósito para localizar la fuga.',
        'Refuerza el área con película adhesiva extra.',
        'Revisa la conexión entre el tubo y el canister.',
        'Confirma que la terapia recupera presión; si no sella tras varios intentos, escala a la guardia.',
      ],
    ),
    VacAlarm(
      code: 'canister_lleno',
      label: 'Canister lleno',
      severity: VacAlarmSeverity.noCritica,
      steps: [
        'Detén la terapia según el equipo.',
        'Cambia el canister por uno nuevo siguiendo la técnica.',
        'Reanuda la terapia y verifica que alcanza la presión objetivo.',
      ],
    ),
    VacAlarm(
      code: 'canister_mal',
      label: 'Canister mal colocado / desprendido',
      severity: VacAlarmSeverity.noCritica,
      steps: [
        'Retira y vuelve a encajar el canister hasta escuchar/sentir el clic.',
        'Verifica que quede firme y que la alarma desaparezca.',
      ],
    ),
    VacAlarm(
      code: 'bateria_baja',
      label: 'Batería baja',
      severity: VacAlarmSeverity.noCritica,
      equipment: [VacEquipment.activac],
      steps: [
        'Conecta el equipo al cargador.',
        'La terapia continúa mientras carga; no la apagues.',
      ],
    ),
    VacAlarm(
      code: 'bloqueo',
      label: 'Bloqueo / obstrucción de la línea',
      severity: VacAlarmSeverity.noCritica,
      steps: [
        'Revisa que el tubo no esté acodado ni atrapado bajo el paciente.',
        'Reacomoda al paciente/tubería.',
        'Si la obstrucción persiste, escala a la guardia.',
      ],
    ),
    VacAlarm(
      code: 'terapia_inactiva',
      label: 'Terapia inactiva / apagada',
      severity: VacAlarmSeverity.critica,
      steps: [
        'Reactiva la terapia de inmediato.',
        'Si el apósito estuvo sin succión por tiempo prolongado, la terapia requiere REINSTALACIÓN.',
        'Contacta a la guardia y no dejes el apósito de espuma sin succión.',
      ],
    ),
    VacAlarm(
      code: 'presion_baja',
      label: 'No alcanza la presión objetivo',
      severity: VacAlarmSeverity.critica,
      steps: [
        'Verifica sello, canister y conexiones (ver "Fuga").',
        'Si tras sellar no alcanza la presión, la terapia requiere REINSTALACIÓN.',
        'Contacta a la guardia.',
      ],
    ),
  ];

  static List<VacAlarm> forEquipment(VacEquipment e) =>
      all.where((a) => a.appliesTo(e)).toList();

  static VacAlarm? byCode(String code) {
    for (final a in all) {
      if (a.code == code) return a;
    }
    return null;
  }
}
