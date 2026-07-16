// Cobertura del fix (bug reportado por el usuario): en ConsultationHubScreen
// ("Nueva consulta", abierta desde el "+" de PatientDetailScreen), elegir
// "Seguimiento" en el dropdown de tipo de visita debia navegar al
// formulario real de seguimiento (/wound/:woundId/follow-up/new) sobre una
// herida ACTIVA existente, en vez de siempre ir a la captura de herida
// NUEVA (/wound/new/capture), como ocurria antes del fix.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:kuratracker/core/providers/session_provider.dart';
import 'package:kuratracker/features/consultation/consultation_hub_screen.dart';
import 'package:kuratracker/models/app_user.dart';
import 'package:kuratracker/models/consultation.dart';
import 'package:kuratracker/models/site.dart';
import 'package:kuratracker/services/data_repository.dart';

/// SessionController de prueba: fija un usuario admin (su staffId se
/// resuelve de forma perezosa via ensureAdminStaffId, igual que en
/// produccion), sin tocar Supabase/AppConfig.
class _FakeSessionController extends SessionController {
  _FakeSessionController(AppUser user) {
    state = SessionState(user: user);
  }
}

/// Contenedor mutable para registrar la ultima ruta a la que efectivamente
/// navego el GoRouter de prueba (necesario porque el tap ocurre DESPUES de
/// montar el widget -- un valor de retorno inmutable capturado en ese
/// momento siempre seria null).
class _RouteRecorder {
  String? lastRoute;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  /// Construye un escenario aislado (organizacion/sitio/paciente propios,
  /// sin depender del DemoSeed) y monta ConsultationHubScreen dentro de un
  /// GoRouter minimo que registra a donde termina navegando la pantalla.
  Future<_RouteRecorder> pumpHub(
    WidgetTester tester, {
    required VisitType initialVisitType,
    required int activeWoundCount,
  }) async {
    final repo = await DataRepository.instance();
    final org =
        await repo.createOrganization('Org prueba seguimiento ${DateTime.now().microsecondsSinceEpoch}');
    // ConsultationHubScreen exige un sitio (_siteId) para habilitar el
    // boton de continuar -- sin al menos un Site del centro, el boton
    // queda deshabilitado y la prueba nunca navega.
    await repo.createSite(
        Site(id: '', name: 'Sitio de prueba', kind: 'clinica', organizationId: org.id));
    final patient = await repo.createPatient(
      fullName: 'Paciente Prueba Seguimiento',
      organizationId: org.id,
    );
    for (var i = 0; i < activeWoundCount; i++) {
      await repo.createWound({
        'patient_id': patient.id,
        'etiology': 'vascular',
        'body_location_primary': 'pierna_izquierda',
        'is_active': true,
      });
    }
    final admin = AppUser(
      id: 'admin-test-${org.id}',
      role: AppRole.admin,
      fullName: 'Admin de prueba',
      email: 'admin.prueba.${org.id}@kuratracker.test',
      organizationId: org.id,
    );

    final recorder = _RouteRecorder();
    final router = GoRouter(
      initialLocation: '/patients/${patient.id}/consultation/new',
      routes: [
        GoRoute(
          path: '/patients/:patientId/consultation/new',
          builder: (context, state) => ConsultationHubScreen(
            patientId: state.pathParameters['patientId']!,
            initialVisitType: initialVisitType,
          ),
        ),
        GoRoute(
          path: '/patients/:patientId/wound/:woundId/capture',
          builder: (context, state) {
            recorder.lastRoute = state.uri.toString();
            return const SizedBox.shrink();
          },
        ),
        GoRoute(
          path: '/patients/:patientId/wound/:woundId/follow-up/new',
          builder: (context, state) {
            recorder.lastRoute = state.uri.toString();
            return const SizedBox.shrink();
          },
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sessionProvider.overrideWith((ref) => _FakeSessionController(admin)),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    return recorder;
  }

  group('ConsultationHubScreen - fix ruta de Seguimiento', () {
    testWidgets(
        'con "Seguimiento" preseleccionado y 1 sola herida activa, navega '
        'directo a /wound/:id/follow-up/new (NO a /wound/new/capture)',
        (tester) async {
      final recorder = await pumpHub(
        tester,
        initialVisitType: VisitType.seguimiento,
        activeWoundCount: 1,
      );

      expect(find.text('Continuar: registrar seguimiento'), findsOneWidget);

      await tester.tap(find.text('Continuar: registrar seguimiento'));
      await tester.pumpAndSettle();

      expect(recorder.lastRoute, isNotNull);
      expect(recorder.lastRoute, contains('/follow-up/new'));
      expect(recorder.lastRoute, isNot(contains('/capture')));
    });

    testWidgets(
        'con "Seguimiento" y varias heridas activas, muestra el selector de '
        'heridas y navega a /follow-up/new de la herida elegida',
        (tester) async {
      final recorder = await pumpHub(
        tester,
        initialVisitType: VisitType.seguimiento,
        activeWoundCount: 2,
      );

      await tester.tap(find.text('Continuar: registrar seguimiento'));
      await tester.pumpAndSettle();

      // El wound picker sheet debe aparecer (2 heridas activas).
      expect(find.text('¿Seguimiento de qué herida?'), findsOneWidget);

      // Elegir la primera opcion del sheet.
      await tester.tap(find.byIcon(Icons.healing_outlined).first);
      await tester.pumpAndSettle();

      expect(recorder.lastRoute, isNotNull);
      expect(recorder.lastRoute, contains('/follow-up/new'));
    });

    testWidgets(
        'con "Valoracion" (default) preserva el comportamiento previo: '
        'navega a /wound/new/capture', (tester) async {
      final recorder = await pumpHub(
        tester,
        initialVisitType: VisitType.valoracion,
        activeWoundCount: 0,
      );

      expect(find.text('Continuar: capturar herida'), findsOneWidget);

      await tester.tap(find.text('Continuar: capturar herida'));
      await tester.pumpAndSettle();

      expect(recorder.lastRoute, isNotNull);
      expect(recorder.lastRoute, contains('/wound/new/capture'));
    });

    testWidgets(
        'con "Seguimiento" pero SIN heridas activas, muestra aviso y NO '
        'navega a ninguna ruta de captura', (tester) async {
      final recorder = await pumpHub(
        tester,
        initialVisitType: VisitType.seguimiento,
        activeWoundCount: 0,
      );

      await tester.tap(find.text('Continuar: registrar seguimiento'));
      await tester.pumpAndSettle();

      expect(
        find.text('Este paciente no tiene heridas activas para dar seguimiento.'),
        findsOneWidget,
      );
      expect(recorder.lastRoute, isNull);
    });
  });
}
