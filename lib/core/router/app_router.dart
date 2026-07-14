import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../providers/session_provider.dart';
import '../../features/auth/login_screen.dart';
import '../../features/dashboard/dashboard_screen.dart';
import '../../features/patients/patients_list_screen.dart';
import '../../features/patients/patient_detail_screen.dart';
import '../../features/patients/patient_form_screen.dart';
import '../../features/consultation/consultation_hub_screen.dart';
import '../../features/wound_capture/wound_capture_screen.dart';
import '../../features/follow_up/follow_up_screen.dart';
import '../../features/follow_up/follow_up_capture_screen.dart';
import '../../features/consultation/consultation_detail_screen.dart';
import '../../features/reports/reports_screen.dart';
import '../../features/admin/admin_home_screen.dart';
import '../../features/import_export/import_export_screen.dart';
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
    initialLocation: '/login',
    refreshListenable: refreshNotifier,
    redirect: (context, state) {
      final loggedIn = ref.read(sessionProvider).isAuthenticated;
      final goingToLogin = state.matchedLocation == '/login';
      if (!loggedIn && !goingToLogin) return '/login';
      if (loggedIn && goingToLogin) return '/';
      return null;
    },
    routes: [
      GoRoute(path: '/login', builder: (context, state) => const LoginScreen()),
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
            path: '/patients/:patientId/consultation/new',
            builder: (context, state) =>
                ConsultationHubScreen(patientId: state.pathParameters['patientId']!),
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
            path: '/patients/:patientId/consultation/:consultationId',
            builder: (context, state) => ConsultationDetailScreen(
              patientId: state.pathParameters['patientId']!,
              consultationId: state.pathParameters['consultationId']!,
            ),
          ),
          GoRoute(path: '/reports', builder: (context, state) => const ReportsScreen()),
          GoRoute(path: '/admin', builder: (context, state) => const AdminHomeScreen()),
          GoRoute(
            path: '/import-export',
            builder: (context, state) => const ImportExportScreen(),
          ),
        ],
      ),
    ],
  );
});
