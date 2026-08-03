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
      return [
        const TourStep(
          route: '/',
          title: 'Bienvenido al recorrido',
          body:
              'Te muestro el flujo real del día a día: crear un paciente, '
              'agendar, la consulta hasta el cobro, los reportes y el tablero de '
              'avance.',
        ),
        const TourStep(
          route: '/patients',
          title: '1 · Pacientes',
          body:
              'El listado de tus pacientes: buscar, filtrar y dar de alta. Toca '
              '“Nuevo paciente” para registrar uno.',
        ),
        const TourStep(
          route: '/patients/new',
          title: '2 · Crear paciente',
          body:
              'Aquí capturas el perfil completo: datos generales, comorbilidades, '
              'antecedentes y cuidador. Entre más completo, mejor alimenta el '
              'motor Kura+ y el módulo de prevención.',
        ),
        const TourStep(
          route: '/agenda',
          title: '3 · Agenda de consultas',
          body:
              'Programa citas (o se sincronizan desde Acuity). Desde una cita: '
              '“Iniciar consulta”; si ya existe, “Ir a la consulta” — sin '
              'capturar dos veces.',
        ),
        const TourStep(
          route: '/agenda',
          title: '4 · Iniciar consulta o seguimiento',
          body:
              'Al iniciar la consulta eliges el tipo. Para una herida existente, '
              '“Seguimiento” te lleva directo a su formulario (ya no a una '
              'valoración).',
        ),
        if (hasWound)
          TourStep(
            route: '/patients/$patientId/wound/$woundId/capture',
            title: '5 · La consulta · Valoración',
            body:
                'Captura guiada por etiología con el PRONÓSTICO EN VIVO del motor '
                'mientras mides el lecho. (Solo un vistazo; no guardamos nada.)',
          ),
        if (hasWound)
          TourStep(
            route: '/patients/$patientId/wound/$woundId/follow-up/new',
            title: '6 · La consulta · Seguimiento (5 fases)',
            body:
                'Perfil heredado (F0), procedimiento físico (F1), estado (F2), '
                'RÉGIMEN de Kura+ con alertas/interconsultas (F3), checkpoint de '
                'Sheehan (F4) y nota + firma (F5).',
          ),
        if (patientId != null && consultationId != null)
          TourStep(
            route: '/patients/$patientId/consultation/$consultationId',
            title: '7 · …hasta el cobro',
            body:
                'Al cerrar la consulta registras los insumos usados y generas el '
                'COBRO: efectivo, terminal Point o link de pago (Stripe). Todo '
                'queda en el expediente.',
          ),
        const TourStep(
          route: '/reports',
          title: '8 · Reportes del paciente',
          body:
              'Genera reportes clínicos (evolución, medidas, fotos) para '
              'compartir con el paciente o exportar.',
        ),
        const TourStep(
          route: '/',
          title: '9 · Dashboard · avance de todos',
          body:
              'El tablero de inicio: el avance de TODOS tus pacientes de un '
              'vistazo (riesgo, cierres, pendientes). ¡Listo, explora libremente! '
              'Reabre el recorrido con el botón “Tour”.',
        ),
      ];
  }
}
