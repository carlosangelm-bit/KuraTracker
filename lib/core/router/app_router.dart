import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../providers/session_provider.dart';
import 'nav_redirect.dart';
import '../../models/app_user.dart';
import '../../models/module_key.dart';
import '../../features/auth/demo_persona_screen.dart';
import '../../features/auth/login_screen.dart';
import '../../features/auth/reset_password_screen.dart';
import '../../features/treatment/treatment_program_builder_screen.dart';
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
import '../../features/admin/protocol_kura_screen.dart';
import '../../features/admin/protocol_matrix_screen.dart';
import '../../features/admin/acuity_session_type_screen.dart';
import '../../features/admin/acuity_visit_type_map_screen.dart';
import '../../features/admin/patient_cleanup_screen.dart';
import '../../features/admin/scale_toggles_screen.dart';
import '../../features/admin/recommendations_reference_screen.dart';
import '../../features/admin/data_disclosures_screen.dart';
import '../../services/data_repository.dart';
import '../widgets/kura_error_state.dart';
import '../../features/import_export/import_export_screen.dart';
import '../../features/import_export/ekare_import_screen.dart';
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
/// Builder para una pantalla hija de /admin que necesita el DataRepository (async)
/// y el centro en sesión. Resuelve el repo con su estado de carga/error y arma la
/// pantalla; así cada ruta hija se declara en una línea sin repetir el `.when`.
Widget Function(BuildContext, GoRouterState) _adminChild(
    Widget Function(DataRepository repo, String? organizationId) build) {
  return (context, state) => Consumer(
        builder: (ctx, ref, _) {
          final repoAsync = ref.watch(dataRepositoryProvider);
          final org = ref.watch(sessionProvider).user?.organizationId;
          return repoAsync.when(
            loading: () =>
                const Scaffold(body: Center(child: CircularProgressIndicator())),
            error: (e, _) => Scaffold(
              appBar: AppBar(),
              body: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: KuraErrorState(
                    title: 'No pudimos cargar esta pantalla',
                    reassurance:
                        'Puede ser tu conexión. Tus datos están a salvo.',
                    detail: '$e',
                    onRetry: () => ref.invalidate(dataRepositoryProvider),
                  ),
                ),
              ),
            ),
            data: (repo) => build(repo, org),
          );
        },
      );
}

/// Ruta clínica de PRIMER NIVEL (un destino del riel). Con el riel único, moverse entre
/// estos destinos es cambiar de PANEL, igual que entre las secciones de /admin y
/// /platform: sin animación (NoTransitionPage). Las rutas PROFUNDAS —detalle de paciente,
/// expediente, captura— NO usan esto: conservan la transición por omisión, porque ahí sí
/// estás navegando hacia ADENTRO y el movimiento lo comunica (§ etapa 5, simetría a).
GoRoute _topLevel(String path, Widget child) => GoRoute(
      path: path,
      pageBuilder: (context, state) => NoTransitionPage(child: child),
    );

final routerProvider = Provider<GoRouter>((ref) {
  final refreshNotifier = _RouterRefreshNotifier();
  ref.listen(sessionProvider, (previous, next) {
    refreshNotifier.ping();
  });

  // Restablecer contraseña: al abrir el enlace del correo, Supabase deja una
  // sesión de recuperación y emite passwordRecovery. Lo marcamos para que el
  // redirect lleve al usuario a /reset-password aunque la app aún no tenga
  // sesión propia. Solo en modo Supabase (en demo no hay auth real).
  if (!isDemoMode) {
    ref.listen(passwordRecoveryProvider, (_, __) => refreshNotifier.ping());
    // El evento passwordRecovery lo captura este listener. NOTA (§prod): con detectSessionInUri por
    // defecto, el evento de la URL INICIAL se emite DENTRO de Supabase.initialize —antes de que este
    // listener exista— y se pierde (broadcast sin replay): la carrera del enlace de recuperación
    // sigue ABIERTA. El arreglo anterior (bootstrap con detectSessionInUri:false + procesado manual)
    // se revirtió por causar una regresión de sesión-en-recarga en web; se re-aborda con verificación
    // en el sandbox. Aquí el listener cubre las recuperaciones POSTERIORES (app ya abierta).
    Supabase.instance.client.auth.onAuthStateChange.listen((data) {
      if (data.event == AuthChangeEvent.passwordRecovery) {
        ref.read(passwordRecoveryProvider.notifier).state = true;
      }
    });
  }

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
      // Restablecer contraseña: ruta pública; y si Supabase emitió el evento,
      // forzamos ir ahí hasta que el usuario termine o cancele.
      if (state.matchedLocation.startsWith('/reset-password')) return null;
      // La recuperación (passwordRecoveryProvider) ahora se decide DENTRO de resolveNavRedirect
      // (gana sobre la sesión), para que la prueba de conducta cubra el caso con sesión previa.
      // El master no tiene datos clínicos propios (0012); el CUIDADOR (Fase 3) solo
      // ve /caregiver; enfermería (0045) es clínica restringida. Los flags de rol se
      // computan aquí y alimentan la decisión de auth/rol (función pura, misma lógica
      // que se prueba: resolveNavRedirect).
      final isMaster = session.user?.role == AppRole.master;
      final isCaregiver = session.user?.isCaregiverOnly ?? false;
      final isNurse = session.user?.isRestrictedNurse ?? false;
      final isAdmin = session.user?.isAdmin ?? false;

      // Auth + rol + /platform + /admin + compra: el ?from= (enlace profundo en frío)
      // gana ANTES que los retornos por rol, así un master/cuidador que entró a una
      // ruta profunda no la pierde (la pasada siguiente reajusta si no le toca).
      final roleRedirect = resolveNavRedirect(
        loggedIn: loggedIn,
        isDemoMode: isDemoMode,
        goingToLogin: goingToLogin,
        goingToDemo: goingToDemo,
        matchedLocation: state.matchedLocation,
        uriString: state.uri.toString(),
        fromParam: state.uri.queryParameters['from'],
        isMaster: isMaster,
        isCaregiver: isCaregiver,
        isAdmin: isAdmin,
        isPasswordRecovery: !isDemoMode && ref.read(passwordRecoveryProvider),
      );
      if (roleRedirect != null) return roleRedirect;

      final location = state.matchedLocation;

      // Enfermería: bloquear rutas de ESCRITURA de diagnóstico/protocolo (la
      // RLS 0045 ya se lo niega; esto pule la UX y evita pantallas de captura).
      // Puede: leer expediente, ficha de riesgo (reporte Braden), eventos
      // adversos (reporte) y agenda de prevención (ejecución).
      // (La compra de insumos y /admin ya se gatearon en resolveNavRedirect.)

      // Rutas de ESCRITURA clínica (crear/editar). Se GATEA LA RUTA, no solo el
      // guardado: un centro en modo lectura (prueba vencida/impago) o enfermería
      // restringida no debe poder abrir el formulario, trabajar y enterarse al final.
      final isClinicalWriteRoute = location == '/patients/new' ||
          location.endsWith('/edit') ||
          location.contains('/consultation/new') ||
          (location.contains('/wound/') && location.endsWith('/capture')) ||
          (location.contains('/wound/') && location.contains('/plan/')) ||
          location.endsWith('/follow-up/new') ||
          location.contains('/follow-up/draft/') ||
          location.endsWith('/comorbidities') ||
          location.endsWith('/diagnoses') ||
          location.endsWith('/referrals/new');
      // Rebota al detalle del paciente si se puede inferir, si no al inicio; ahí la
      // banda del shell explica el motivo (y ofrece Licencias al admin).
      String bounceFromWrite() {
        final segs = location.split('/').where((s) => s.isNotEmpty).toList();
        if (segs.length >= 2 && segs[0] == 'patients') return '/patients/${segs[1]}';
        return '/';
      }

      if (loggedIn && isNurse && isClinicalWriteRoute) {
        return bounceFromWrite();
      }

      // Centro en modo LECTURA (prueba terminada / pago vencido / cancelado): lee su
      // expediente, no escribe. Mismo criterio que el candado del repositorio
      // (clinicalReadOnlyReason ≠ null solo cuando HAY derecho clínico y no es
      // escribible; sin derecho no rebota, para no romper fixtures/edge).
      if (loggedIn && !isMaster && isClinicalWriteRoute) {
        final repo = ref.read(dataRepositoryProvider).valueOrNull;
        if (repo != null &&
            repo.clinicalReadOnlyReason(session.user?.organizationId) != null) {
          return bounceFromWrite();
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
      GoRoute(path: '/demo', builder: (context, state) => const DemoGateScreen()),
      // Resultado de pago (público, fuera del shell): Stripe redirige aquí.
      GoRoute(
          path: '/pago-recibido',
          builder: (context, state) => const PaymentResultScreen(success: true)),
      GoRoute(
          path: '/pago-cancelado',
          builder: (context, state) => const PaymentResultScreen(success: false)),
      GoRoute(
          path: '/reset-password',
          builder: (context, state) => const ResetPasswordScreen()),
      ShellRoute(
        builder: (context, state, child) =>
            AppShell(currentPath: state.matchedLocation, child: child),
        routes: [
          _topLevel('/', const DashboardScreen()),
          _topLevel('/patients', const PatientsListScreen()),
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
                typeLocked: state.uri.queryParameters['typeLocked'] == '1',
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
            path: '/patients/:patientId/wound/:woundId/plan/:consultationId',
            builder: (context, state) => TreatmentProgramBuilderScreen(
              patientId: state.pathParameters['patientId']!,
              woundId: state.pathParameters['woundId']!,
              consultationId: state.pathParameters['consultationId']!,
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
          _topLevel('/reports', const ReportsScreen()),
          _topLevel('/insumos', const InsumosHomeScreen()),
          _topLevel('/comercial', const ComercialScreen()),
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
          _topLevel('/agenda', const AgendaScreen()),
          _topLevel('/risk', const RiskBoardScreen()),
          _topLevel('/prevention-agenda', const PreventionAgendaScreen()),
          GoRoute(
              path: '/hospital',
              builder: (context, state) => const HospitalDashboardScreen()),
          _topLevel('/vac', const VacTherapiesScreen()),
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
          _topLevel('/caregiver', const CaregiverHomeScreen()),
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
          // /admin: canónico + ShellRoute anidado. El canónico es un route APARTE (sin
          // hijos) para que solo dispare en /admin a secas — anidar las secciones bajo un
          // padre CON redirect hacía que el redirect (matchedLocation == '/admin')
          // capturara también a las hijas. El riel vive en el shell (AdminSectionsShell)
          // y PERSISTE entre secciones; cada sección es solo su cuerpo, con
          // NoTransitionPage (cambiar de sección no anima ni recarga la pantalla).
          // El PROPIO shell va también con NoTransitionPage (pageBuilder): ENTRAR a la
          // consola desde una pestaña clínica NO debe animar el subárbol completo (§12).
          // Con `builder:` go_router lo envolvía en la página por omisión (MaterialPage) y
          // esa transición delataba «recarga» al entrar, aunque entre secciones no anime.
          GoRoute(
            path: '/admin',
            redirect: (context, state) => '/admin/usuarios',
          ),
          ShellRoute(
            pageBuilder: (context, state, child) => NoTransitionPage(
              child: AdminSectionsShell(
                  currentRoute: state.matchedLocation, child: child),
            ),
            routes: [
              for (final s in const [
                'usuarios',
                'personal',
                'sitios',
                'configuracion',
                'marca',
                'licencias',
              ])
                GoRoute(
                  path: '/admin/$s',
                  pageBuilder: (context, state) =>
                      NoTransitionPage(child: AdminSectionBody(section: s)),
                ),
            ],
          ),
          // Las 8 pantallas hijas profundas de Administración (FUERA del shell de
          // secciones: son pantallas completas). El gate por rol lo da el redirect global.
          GoRoute(
              path: '/admin/protocolo-kura',
              builder: _adminChild((repo, org) =>
                  ProtocolKuraScreen(repo: repo, organizationId: org))),
          GoRoute(
              path: '/admin/productos-protocolo',
              // §15 etapa 6: la Matriz reemplaza al editor viejo. Gatea tres estados por permiso
              // (autora → catálogo + atado; módulo sin autoría → reglas propias; sin permiso → dicho).
              builder: _adminChild((repo, org) =>
                  ProtocolMatrixScreen(repo: repo, organizationId: org))),
          GoRoute(
              path: '/admin/tipo-cita-sesiones',
              builder: _adminChild((repo, org) =>
                  AcuitySessionTypeScreen(repo: repo, organizationId: org))),
          GoRoute(
              path: '/admin/tipos-consulta',
              builder: _adminChild((repo, org) =>
                  AcuityVisitTypeMapScreen(repo: repo, organizationId: org))),
          GoRoute(
              path: '/admin/depurar-expedientes',
              builder: _adminChild((repo, org) =>
                  PatientCleanupScreen(repo: repo, organizationId: org))),
          GoRoute(
              path: '/admin/escalas-protocolo',
              builder: _adminChild((repo, org) =>
                  ScaleTogglesScreen(repo: repo, organizationId: org))),
          GoRoute(
              path: '/admin/fuente-recomendaciones',
              builder: (context, state) =>
                  const RecommendationsReferenceScreen()),
          GoRoute(
              path: '/admin/divulgaciones',
              builder: (context, state) => const DataDisclosuresScreen()),
          // /platform: canónico (childless, canoniza a Centros) + ShellRoute anidado. El
          // riel vive en el shell (PlatformSectionsShell) y persiste; cada sección es su
          // cuerpo, con NoTransitionPage (cambiar de sección no anima ni recarga). El
          // centro seleccionado vive en un provider, así sobrevive el cambio de sección.
          // El PROPIO shell va también con NoTransitionPage (pageBuilder): ENTRAR a la
          // consola del master desde una pestaña clínica NO debe animar el subárbol (§12).
          GoRoute(
            path: '/platform',
            redirect: (context, state) => '/platform/centros',
          ),
          ShellRoute(
            pageBuilder: (context, state, child) => NoTransitionPage(
              child: PlatformSectionsShell(
                  currentRoute: state.matchedLocation, child: child),
            ),
            routes: [
              for (final s in const [
                'centros',
                'usuarios',
                'personal',
                'sitios',
                'catalogo',
                'marca',
                'modulos',
                'solicitudes',
                'licencia',
              ])
                GoRoute(
                  path: '/platform/$s',
                  pageBuilder: (context, state) =>
                      NoTransitionPage(child: PlatformSectionBody(section: s)),
                ),
            ],
          ),
          _topLevel('/import-export', const ImportExportScreen()),
          GoRoute(
            // Hija de /import-export para que ModuleKey.forRoute la atrape (via
            // el prefijo de la ruta del módulo) y herede el gate del módulo. Como
            // ruta de primer nivel quedaba fuera del gate — el mismo hueco que
            // tuvo /admin (auditoría 1-sep).
            path: '/import-export/ekare',
            builder: (context, state) => const EkareImportScreen(),
          ),
        ],
      ),
    ],
  );
});
