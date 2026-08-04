import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../providers/session_provider.dart';
import '../../models/app_user.dart';
import '../../models/module_key.dart';
import '../../features/auth/demo_persona_screen.dart';
import '../../features/auth/login_screen.dart';
import '../../features/support/support_bot_screen.dart';
import '../../features/comercial/payment_result_screen.dart';
import '../../features/dashboard/dashboard_screen.dart';
import '../../features/patients/patients_list_screen.dart';
import '../../features/patients/patient_detail_screen.dart';
import '../../features/patients/patient_form_screen.dart';
import '../../features/patients/comorbidities_screen.dart';
import '../../features/patients/patient_labs_screen.dart';
import '../../features/patients/diagnoses_screen.dart';
import '../../features/risk/risk_board_screen.dart';
import '../../features/risk/patient_risk_screen.dart';
import '../../features/consultation/consultation_hub_screen.dart';
import '../../models/consultation.dart';
import '../../features/wound_capture/wound_capture_screen.dart';
import '../../features/follow_up/follow_up_screen.dart';
import '../../features/follow_up/follow_up_capture_screen.dart';
import '../../features/adverse_events/adverse_events_screen.dart';
import '../../features/adverse_events/adverse_events_capture_screen.dart';
import '../../features/consultation/consultation_detail_screen.dart';
import '../../features/consents/consents_screen.dart';
import '../../features/referrals/referrals_screen.dart';
import '../../features/referrals/referral_create_screen.dart';
import '../../features/reports/reports_screen.dart';
import '../../features/agenda/agenda_screen.dart';
import '../../features/admin/admin_home_screen.dart';
import '../../features/import_export/import_export_screen.dart';
import '../../features/platform/platform_home_screen.dart';
import '../../features/prevention_agenda/prevention_agenda_screen.dart';
import '../../features/hospital_dashboard/hospital_dashboard_screen.dart';
import '../../features/vac/vac_therapies_screen.dart';
import '../../features/vac/vac_therapy_detail_screen.dart';
import '../../features/vac/vac_alarm_screen.dart';
import '../../features/vac/vac_bot_screen.dart';
import '../../features/insumos/insumos_home_screen.dart';
import '../../features/insumos/tienda_screen.dart';
import '../../features/insumos/mapeo_screen.dart';
import '../../features/insumos/inventario_screen.dart';
import '../../features/insumos/consumo_screen.dart';
import '../../features/insumos/reabasto_screen.dart';
import '../../features/comercial/comercial_screen.dart';
import '../../features/caregiver/caregiver_home_screen.dart';
import '../../features/caregiver/caregiver_patient_screen.dart';
import 'app_shell.dart';

/// Notificador puente para que GoRouter reaccione a cambios de sesion
/// (login/logout) y vuelva a evaluar sus redirects.
class _RouterRefreshNotifier extends ChangeNotifier {
  void ping() => notifyListeners();
}

/// El router se construye una sola vez (Provider), y se suscribe via
/// ref.listen a cambios de sesion para disparar sus redirects sin perder
/// el estado de navegacion en cada rebuild de widgets.
final routerProvider = Provider<GoRouter>((ref) {
  final refreshNotifier = _RouterRefreshNotifier();
  ref.listen(sessionProvider, (previous, next) {
    refreshNotifier.ping();
  });

  return GoRouter(
    initialLocation: isDemoMode ? '/demo' : '/login',
    refreshListenable: refreshNotifier,
    redirect: (context, state) {
      final session = ref.read(sessionProvider);
      final loggedIn = session.isAuthenticated;
      final goingToLogin = state.matchedLocation == '/login';
      // Capa previa al login SOLO en demo: elegir perfil (usuario demo).
      final goingToDemo = state.matchedLocation == '/demo';
      // Rutas PÚBLICAS (sin sesión): páginas de resultado de pago a las que
      // Stripe redirige al PACIENTE. No deben pasar por el login ni la app.
      if (state.matchedLocation.startsWith('/pago-')) return null;
      if (!loggedIn && !goingToLogin && !goingToDemo) {
        // En demo, la landing es la selección de perfil; en prod, el login.
        return isDemoMode ? '/demo' : '/login';
      }

      // El master (administrador de plataforma) no tiene datos clinicos
      // propios (dashboard/pacientes/reportes quedarian vacios para el,
      // ver regla de oro en 0012_master_role.sql): al iniciar sesion se le
      // manda directo a su area de trabajo real, '/platform'.
      final isMaster = session.user?.role == AppRole.master;
      // El CUIDADOR (Fase 3) es un rol restringido: su única área es
      // '/caregiver' (monitoreo de los pacientes que el centro le asignó, solo
      // lectura + sus tareas). No ve el dashboard clínico ni el resto de la nav.
      final isCaregiver = session.user?.role == AppRole.cuidador;
      // Enfermería (0045): personal clínico restringido — observa, reporta y
      // ejecuta, pero NO diagnostica ni cambia protocolo. Se le bloquean las
      // rutas de escritura de diagnóstico/protocolo (abajo).
      final isNurse = session.user?.role == AppRole.enfermeria;
      if (loggedIn && (goingToLogin || goingToDemo)) {
        if (isMaster) return '/platform';
        if (isCaregiver) return '/caregiver';
        return '/';
      }

      final location = state.matchedLocation;
      if (loggedIn && isMaster) {
        // Si el master cae en cualquier ruta clinica (tecleada a mano,
        // bookmark antiguo, etc.) se le redirige a su area real: esas
        // pantallas no tienen datos utiles para el (misma regla de oro).
        final isClinicalRoute =
            location == '/' || location.startsWith('/patients') || location == '/reports';
        if (isClinicalRoute) return '/platform';
      } else if (loggedIn && isCaregiver) {
        // El cuidador solo puede estar en su área; cualquier otra ruta lo
        // regresa a '/caregiver' (defensa de UX; la RLS 0042 ya le niega el
        // resto de los datos). Excepción: el asistente de ayuda ('/support')
        // está permitido para todos los roles.
        if (!location.startsWith('/caregiver') && location != '/support') {
          return '/caregiver';
        }
      } else if (loggedIn && location.startsWith('/caregiver')) {
        // Un no-cuidador que teclee '/caregiver' no tiene nada ahí.
        return '/';
      } else if (loggedIn && location.startsWith('/platform')) {
        // Hardening (no es hueco de datos: la RLS is_master() de 0012 ya le
        // niega todo a un no-master; esto solo pule la UX): un admin/clinico
        // que teclee '/platform' a mano no debe quedarse ahi -- se le manda
        // a su dashboard normal.
        return '/';
      }

      // Enfermería: bloquear rutas de ESCRITURA de diagnóstico/protocolo (la
      // RLS 0045 ya se lo niega; esto pule la UX y evita pantallas de captura).
      // Puede: leer expediente, ficha de riesgo (reporte Braden), eventos
      // adversos (reporte) y agenda de prevención (ejecución).
      if (loggedIn && isNurse) {
        final blocked = location == '/patients/new' ||
            location.endsWith('/edit') ||
            location.contains('/consultation/new') ||
            (location.contains('/wound/') && location.endsWith('/capture')) ||
            location.endsWith('/follow-up/new') ||
            location.contains('/follow-up/draft/') ||
            location.endsWith('/comorbidities') ||
            location.endsWith('/diagnoses') ||
            location.endsWith('/referrals/new');
        if (blocked) {
          // Regresar al detalle del paciente si se puede inferir, si no al inicio.
          final segs = location.split('/').where((s) => s.isNotEmpty).toList();
          if (segs.length >= 2 && segs[0] == 'patients') {
            return '/patients/${segs[1]}';
          }
          return '/';
        }
      }

      // Gating por módulo (Fase 2): si la ruta pertenece a un módulo apagado
      // para el centro/sitio/usuario, se redirige al dashboard. Solo aplica a
      // no-master/no-cuidador (esos no navegan rutas de módulos). No bloquea
      // datos (eso lo hace la RLS); es coherencia con el nav visible.
      if (loggedIn && !isMaster && !isCaregiver) {
        final module = ModuleKeyX.forRoute(location);
        // La agenda de prevención es submódulo de Prevención.
        final needsPrevention = location.startsWith('/prevention-agenda') ||
            location.startsWith('/hospital');
        final modules = ref.read(enabledModulesProvider);
        if ((module != null && !modules.contains(module)) ||
            (needsPrevention && !modules.contains(ModuleKey.prevention))) {
          return '/';
        }
      }

      return null;
    },
    routes: [
      GoRoute(path: '/login', builder: (context, state) => const LoginScreen()),
      GoRoute(path: '/demo', builder: (context, state) => const DemoPersonaScreen()),
      // Resultado de pago (público, fuera del shell): Stripe redirige aquí.
      GoRoute(
          path: '/pago-recibido',
          builder: (context, state) => const PaymentResultScreen(success: true)),
      GoRoute(
          path: '/pago-cancelado',
          builder: (context, state) => const PaymentResultScreen(success: false)),
      ShellRoute(
        builder: (context, state, child) =>
            AppShell(currentPath: state.matchedLocation, child: child),
        routes: [
          GoRoute(path: '/', builder: (context, state) => const DashboardScreen()),
          GoRoute(
            path: '/patients',
            builder: (context, state) => const PatientsListScreen(),
          ),
          GoRoute(
            path: '/patients/new',
            builder: (context, state) => const PatientFormScreen(),
          ),
          GoRoute(
            path: '/patients/:patientId',
            builder: (context, state) =>
                PatientDetailScreen(patientId: state.pathParameters['patientId']!),
          ),
          GoRoute(
            path: '/patients/:patientId/edit',
            builder: (context, state) => PatientFormScreen(
              patientId: state.pathParameters['patientId']!,
            ),
          ),
          GoRoute(
            path: '/patients/:patientId/consultation/new',
            builder: (context, state) {
              final visitTypeParam = state.uri.queryParameters['visitType'];
              final visitType = VisitType.values.firstWhere(
                (v) => v.name == visitTypeParam,
                orElse: () => VisitType.valoracion,
              );
              return ConsultationHubScreen(
                patientId: state.pathParameters['patientId']!,
                initialVisitType: visitType,
                scheduledAppointmentRef: state.uri.queryParameters['appt'],
              );
            },
          ),
          GoRoute(
            path: '/patients/:patientId/wound/:woundId/capture',
            builder: (context, state) => WoundCaptureScreen(
              patientId: state.pathParameters['patientId']!,
              woundId: state.pathParameters['woundId'],
              consultationId: state.uri.queryParameters['consultationId'],
            ),
          ),
          GoRoute(
            path: '/patients/:patientId/wound/:woundId/follow-up',
            builder: (context, state) => FollowUpScreen(
              patientId: state.pathParameters['patientId']!,
              woundId: state.pathParameters['woundId']!,
            ),
          ),
          GoRoute(
            path: '/patients/:patientId/wound/:woundId/follow-up/new',
            builder: (context, state) => FollowUpCaptureScreen(
              patientId: state.pathParameters['patientId']!,
              woundId: state.pathParameters['woundId']!,
            ),
          ),
          GoRoute(
            path: '/patients/:patientId/wound/:woundId/follow-up/draft/:draftId',
            builder: (context, state) => FollowUpCaptureScreen(
              patientId: state.pathParameters['patientId']!,
              woundId: state.pathParameters['woundId']!,
              draftConsultationId: state.pathParameters['draftId'],
            ),
          ),
          GoRoute(
            path: '/patients/:patientId/labs',
            builder: (context, state) => PatientLabsScreen(
              patientId: state.pathParameters['patientId']!,
            ),
          ),
          GoRoute(
            path: '/patients/:patientId/comorbidities',
            builder: (context, state) => ComorbiditiesScreen(
              patientId: state.pathParameters['patientId']!,
            ),
          ),
          GoRoute(
            path: '/patients/:patientId/diagnoses',
            builder: (context, state) => DiagnosesScreen(
              patientId: state.pathParameters['patientId']!,
            ),
          ),
          GoRoute(
            path: '/patients/:patientId/adverse-events',
            builder: (context, state) => AdverseEventsScreen(
              patientId: state.pathParameters['patientId']!,
            ),
          ),
          GoRoute(
            path: '/patients/:patientId/adverse-events/new',
            builder: (context, state) => AdverseEventsCaptureScreen(
              patientId: state.pathParameters['patientId']!,
              woundId: state.uri.queryParameters['woundId'],
              consultationId: state.uri.queryParameters['consultationId'],
            ),
          ),
          GoRoute(
            path: '/patients/:patientId/consents',
            builder: (context, state) => ConsentsScreen(
              patientId: state.pathParameters['patientId']!,
            ),
          ),
          GoRoute(
            path: '/patients/:patientId/referrals',
            builder: (context, state) => ReferralsScreen(
              patientId: state.pathParameters['patientId']!,
            ),
          ),
          GoRoute(
            path: '/patients/:patientId/referrals/new',
            builder: (context, state) => ReferralCreateScreen(
              patientId: state.pathParameters['patientId']!,
              woundId: state.uri.queryParameters['woundId'],
              consultationId: state.uri.queryParameters['consultationId'],
            ),
          ),
          GoRoute(
            path: '/patients/:patientId/consultation/:consultationId',
            builder: (context, state) => ConsultationDetailScreen(
              patientId: state.pathParameters['patientId']!,
              consultationId: state.pathParameters['consultationId']!,
            ),
          ),
          GoRoute(path: '/reports', builder: (context, state) => const ReportsScreen()),
          GoRoute(path: '/insumos', builder: (context, state) => const InsumosHomeScreen()),
          GoRoute(path: '/comercial', builder: (context, state) => const ComercialScreen()),
          GoRoute(
              path: '/insumos/tienda',
              builder: (context, state) => const TiendaScreen()),
          GoRoute(
              path: '/insumos/mapeo',
              builder: (context, state) => const MapeoScreen()),
          GoRoute(
              path: '/insumos/inventario',
              builder: (context, state) => const InventarioScreen()),
          GoRoute(
              path: '/insumos/consumo',
              builder: (context, state) => const ConsumoScreen()),
          GoRoute(
              path: '/insumos/reabasto',
              builder: (context, state) => const ReabastoScreen()),
          GoRoute(path: '/agenda', builder: (context, state) => const AgendaScreen()),
          GoRoute(path: '/risk', builder: (context, state) => const RiskBoardScreen()),
          GoRoute(
              path: '/prevention-agenda',
              builder: (context, state) => const PreventionAgendaScreen()),
          GoRoute(
              path: '/hospital',
              builder: (context, state) => const HospitalDashboardScreen()),
          GoRoute(
              path: '/vac',
              builder: (context, state) => const VacTherapiesScreen()),
          GoRoute(
            path: '/vac/:therapyId',
            builder: (context, state) => VacTherapyDetailScreen(
              therapyId: state.pathParameters['therapyId']!,
            ),
          ),
          GoRoute(
            path: '/vac/:therapyId/alarm',
            builder: (context, state) => VacAlarmScreen(
              therapyId: state.pathParameters['therapyId']!,
            ),
          ),
          GoRoute(
            path: '/vac/:therapyId/bot',
            builder: (context, state) => VacBotScreen(
              therapyId: state.pathParameters['therapyId']!,
            ),
          ),
          GoRoute(
            path: '/support',
            builder: (context, state) => SupportBotScreen(
              sessionContext: (state.extra as Map?)?.cast<String, String>(),
            ),
          ),
          GoRoute(
              path: '/caregiver',
              builder: (context, state) => const CaregiverHomeScreen()),
          GoRoute(
            path: '/caregiver/patient/:patientId',
            builder: (context, state) => CaregiverPatientScreen(
              patientId: state.pathParameters['patientId']!,
            ),
          ),
          GoRoute(
            path: '/patients/:patientId/risk',
            builder: (context, state) => PatientRiskScreen(
              patientId: state.pathParameters['patientId']!,
            ),
          ),
          GoRoute(path: '/admin', builder: (context, state) => const AdminHomeScreen()),
          GoRoute(
            path: '/platform',
            builder: (context, state) => const PlatformHomeScreen(),
          ),
          GoRoute(
            path: '/import-export',
            builder: (context, state) => const ImportExportScreen(),
          ),
        ],
      ),
    ],
  );
});
