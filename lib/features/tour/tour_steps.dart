import '../../models/app_user.dart';
import 'tour_controller.dart';

/// Recorrido guiado por rol. Cuando hay un paciente/herida demo resuelto, el
/// tour navega también a la valoración y al seguimiento en 5 fases. Solo se
/// usan rutas que ese rol puede abrir (respetando el gating del router).
List<TourStep> tourStepsFor(
  AppRole role, {
  String? patientId,
  String? woundId,
  String? consultationId,
}) {
  final hasWound = patientId != null && woundId != null;

  switch (role) {
    case AppRole.master:
      return const [
        TourStep(
          route: '/platform',
          title: 'Bienvenido al recorrido · Plataforma',
          body:
              'Como master administras la PLATAFORMA, no datos clínicos: aquí das '
              'de alta centros (organizaciones), usuarios, sitios, catálogos y '
              'activas/ desactivas módulos por centro.',
        ),
        TourStep(
          title: 'Organizaciones y módulos',
          body:
              'En las pestañas gestionas cada centro y su tipo (clínica de '
              'heridas, hospital o cuidadores), su personal y qué módulos ve. '
              'También puedes descargar/subir los parámetros clínicos del motor.',
        ),
        TourStep(
          title: '¡Listo!',
          body:
              'Eso es tu área. Explora libremente; puedes reabrir este recorrido '
              'con el botón “?”.',
        ),
      ];

    case AppRole.cuidador:
      return const [
        TourStep(
          route: '/caregiver',
          title: 'Bienvenido al recorrido · Monitoreo',
          body:
              'Como cuidador ves solo a los pacientes que el centro te asignó: su '
              'evolución, las instrucciones y tu agenda de tareas.',
        ),
        TourStep(
          title: '¡Listo!',
          body:
              'Ese es tu espacio. Explora libremente; reabre el recorrido con el '
              'botón “?”.',
        ),
      ];

    case AppRole.enfermeria:
      return const [
        TourStep(
          route: '/',
          title: 'Bienvenido al recorrido',
          body:
              'Este es tu inicio. Como enfermería observas, reportas y ejecutas '
              'cuidados (no diagnosticas ni cambias el protocolo).',
        ),
        TourStep(
          route: '/patients',
          title: 'Pacientes',
          body:
              'Aquí ves a los pacientes del centro y su expediente: heridas, '
              'evolución y riesgo.',
        ),
        TourStep(
          route: '/risk',
          title: 'Prevención de LPP',
          body:
              'Valora el riesgo de lesión por presión con la escala de Braden '
              '(completa, 6 subescalas) y consulta el tablero de riesgo del centro.',
        ),
        TourStep(
          route: '/prevention-agenda',
          title: 'Rondas',
          body:
              'La agenda de cuidados preventivos: las tareas que siguen al '
              'paciente, autogeneradas por su nivel de riesgo, para ejecutarlas '
              'en la ronda.',
        ),
        TourStep(
          route: '/',
          title: '¡Listo!',
          body:
              'Eso es lo esencial. Explora libremente; reabre el recorrido con el '
              'botón “?”.',
        ),
      ];

    case AppRole.admin:
    case AppRole.clinico:
      // Copy aprobado por Carlos (KuraTracker_lenguaje_del_demo.md): lenguaje de
      // CLIENTE, no de Kuramas. Se resuelven Acuity → "tu sistema de citas en
      // línea"; checkpoint de Sheehan → "revisión de avance de la semana 4";
      // F0..F5 → nombradas en palabras; y "el motor Kura+" → "Protocolo Kura+
      // —el motor de decisión clínica—" la 1ª vez, luego "el protocolo".
      return [
        const TourStep(
          route: '/',
          title: 'Bienvenido',
          body:
              'Te muestro el día a día completo: registrar un paciente, agendar '
              'su cita, la consulta con su nota firmada, el cobro y el '
              'seguimiento de su evolución.',
        ),
        const TourStep(
          route: '/patients',
          title: 'Pacientes',
          body:
              'El listado de tus pacientes: buscar, filtrar por estado o sede, y '
              'dar de alta. Toca “Nuevo paciente” para registrar uno.',
        ),
        const TourStep(
          route: '/patients/new',
          title: 'Crear paciente',
          body:
              'Aquí capturas el expediente: datos generales, enfermedades que ya '
              'tiene, antecedentes y quién lo cuida en casa. Cuanto más completo, '
              'mejores son las recomendaciones que el sistema te va a dar después.',
        ),
        const TourStep(
          route: '/agenda',
          title: 'Agenda',
          body:
              'Programa las citas, o déjalas entrar solas si conectas tu sistema '
              'de citas en línea. Desde una cita abres la consulta con un toque, '
              'sin capturar los datos del paciente otra vez.',
        ),
        const TourStep(
          route: '/agenda',
          title: 'Iniciar la consulta',
          body:
              'Al abrir la cita eliges qué vas a hacer. Si la herida ya existe, '
              'entras directo a su seguimiento; si es nueva, a su primera '
              'valoración.',
        ),
        if (hasWound)
          TourStep(
            route: '/patients/$patientId/wound/$woundId/capture',
            title: 'La valoración',
            body:
                'Los campos cambian según el tipo de herida, y mientras mides el '
                'lecho el Protocolo Kura+ —el motor de decisión clínica del '
                'sistema— te va diciendo, en vivo, qué pronóstico tiene esa '
                'herida.',
          ),
        if (hasWound)
          TourStep(
            route: '/patients/$patientId/wound/$woundId/follow-up/new',
            title: 'El seguimiento, en cinco fases',
            body:
                'Perfil heredado de la valoración anterior; procedimiento '
                'realizado; estado actual de la herida; el tratamiento que el '
                'protocolo recomienda, con sus alertas y a quién derivar; la '
                'revisión de avance de la semana 4; y la nota firmada.',
          ),
        if (patientId != null && consultationId != null)
          TourStep(
            route: '/patients/$patientId/consultation/$consultationId',
            title: 'Hasta el cobro',
            body:
                'Al cerrar la consulta registras qué material usaste y generas el '
                'cobro: efectivo, terminal o liga de pago. El material sale del '
                'inventario y todo queda en el expediente del paciente.',
          ),
        const TourStep(
          route: '/reports',
          title: 'Reportes',
          body:
              'Genera el reporte clínico del paciente —evolución, medidas y '
              'fotos— para entregárselo o compartirlo con otro médico.',
        ),
        const TourStep(
          route: '/',
          title: 'Tu tablero',
          body:
              'El avance de todos tus pacientes de un vistazo: quién mejora, '
              'quién no y quién necesita atención hoy. Listo — explora con '
              'libertad; puedes reabrir este recorrido con el botón de la esquina.',
        ),
      ];
  }
}
