import '../../models/app_user.dart';
import 'tour_controller.dart';

/// Recorrido guiado por rol. Cuando hay un paciente/herida demo resuelto, el
/// tour navega también a la valoración y al seguimiento en 5 fases. Solo se
/// usan rutas que ese rol puede abrir (respetando el gating del router).
List<TourStep> tourStepsFor(
  AppRole role, {
  String? patientId,
  String? woundId,
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
              'Este es tu tablero de inicio, con un resumen de tu actividad y '
              'accesos rápidos.',
        ),
        const TourStep(
          route: '/patients',
          title: 'Pacientes',
          body:
              'Aquí gestionas a tus pacientes y sus heridas: buscar, filtrar y '
              'registrar nuevos.',
        ),
        if (patientId != null)
          TourStep(
            route: '/patients/$patientId',
            title: 'Expediente del paciente',
            body:
                'La ficha completa: heridas, diagnósticos CIE-10, comorbilidades, '
                'consentimientos, laboratorios y su historial de consultas.',
          ),
        if (hasWound)
          TourStep(
            route: '/patients/$patientId/wound/$woundId/capture',
            title: 'Valoración de la herida',
            body:
                'Captura guiada por etiología (divulgación progresiva) con el '
                'PRONÓSTICO EN VIVO del motor Kura+ mientras mides el lecho. '
                '(Es solo un vistazo; no guardaremos nada.)',
          ),
        if (hasWound)
          TourStep(
            route: '/patients/$patientId/wound/$woundId/follow-up/new',
            title: 'Seguimiento en 5 fases',
            body:
                'El seguimiento reorganizado: Fase 0 perfil heredado, 1 '
                'procedimiento físico, 2 estado actual, 3 RÉGIMEN sugerido por '
                'Kura+ (con alertas e interconsultas), 4 checkpoint de Sheehan y '
                '5 nota + firma.',
          ),
        const TourStep(
          route: '/',
          title: '¡Listo!',
          body:
              'Ese es el flujo principal. Explora libremente; puedes reabrir este '
              'recorrido con el botón “?”. Y recuerda: la app también funciona '
              'sin conexión.',
        ),
      ];
  }
}
