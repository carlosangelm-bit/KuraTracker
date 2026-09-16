import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:kuratracker/core/design/tokens.dart';
import 'package:kuratracker/services/acuity_service.dart';
import 'package:kuratracker/services/data_repository.dart';
import 'package:kuratracker/services/local_db/local_store.dart';

import 'package:kuratracker/features/admin/protocol_kura_screen.dart';
import 'package:kuratracker/features/admin/protocol_product_rules_screen.dart';
import 'package:kuratracker/features/admin/protocol_matrix_screen.dart';
import 'package:kuratracker/features/admin/acuity_session_type_screen.dart';
import 'package:kuratracker/features/admin/acuity_visit_type_map_screen.dart';
import 'package:kuratracker/features/admin/patient_cleanup_screen.dart';

/// 2b — que el candado esté PUESTO, no solo que funcione. Enumera las pantallas
/// gateadas por el módulo Administración avanzada y exige que cada una,
/// abierta sin el módulo (como al teclear su URL), muestre el bloqueo con precio; y
/// que con el módulo, ninguna lo muestre. La lista vive en UN solo lugar: agregar
/// una sexta pantalla gateada obliga a sumarla aquí.
///
/// Las de Acuity leen acuityServiceProvider en initState (red); se sustituye por un
/// fake para poder montarlas sin Supabase.
final _gatedScreens =
    <({String name, String file, Widget Function(DataRepository, String?) build})>[
  (name: 'ProtocolKuraScreen', file: 'protocol_kura_screen.dart', build: (r, o) => ProtocolKuraScreen(repo: r, organizationId: o)),
  (name: 'ProtocolProductRulesScreen', file: 'protocol_product_rules_screen.dart', build: (r, o) => ProtocolProductRulesScreen(repo: r, organizationId: o)),
  // §15 etapa 6: la Matriz reemplaza a la anterior en la ruta. Lleva el candado comercial PRIMERO
  // (gate del centro, antes del rol) para que sobreviva a la unificación futura del modo propio.
  (name: 'ProtocolMatrixScreen', file: 'protocol_matrix_screen.dart', build: (r, o) => ProtocolMatrixScreen(repo: r, organizationId: o)),
  (name: 'AcuitySessionTypeScreen', file: 'acuity_session_type_screen.dart', build: (r, o) => AcuitySessionTypeScreen(repo: r, organizationId: o)),
  (name: 'AcuityVisitTypeMapScreen', file: 'acuity_visit_type_map_screen.dart', build: (r, o) => AcuityVisitTypeMapScreen(repo: r, organizationId: o)),
  (name: 'PatientCleanupScreen', file: 'patient_cleanup_screen.dart', build: (r, o) => PatientCleanupScreen(repo: r, organizationId: o)),
];

/// Archivos de lib/features/admin/ que mencionan premiumAdminFor pero NO son
/// pantallas hijas gateadas — el candado no es su forma. admin_home es el
/// contenedor (gatea por sección); license_panel y license_plan_builder son la
/// pestaña Licencias, que LEE el estado del módulo para mostrar precios y NUNCA se
/// gatea (la compra vive ahí; custodia NOM-004). Cualquier archivo NUEVO que
/// mencione premiumAdminFor y no esté aquí ni en _gatedScreens rompe el test — que
/// es justamente lo que fuerza a enumerar una sexta pantalla gateada.
const _nonGatedAdminFiles = <String>{
  'admin_home_screen.dart',
  // Usuarios menciona premiumAdminFor solo para el mensaje del asiento admin (un
  // usuario solo-administrativo consume asiento clínico sin el módulo). NO es una
  // pantalla gateada: no se bloquea tras module:admin. Etapa 1: se sacó a su archivo.
  'users_screen.dart',
  // Sitios menciona premiumAdminFor solo para el CANDADO COMERCIAL del FAB (el 2º
  // sitio en adelante exige el módulo). La pantalla NO se gatea: la lista siempre se
  // ve. Etapa 3: se sacó a su archivo.
  'sites_screen.dart',
  // Configuración menciona premiumAdminFor solo para decidir si un tile del catálogo
  // NAVEGA o abre el diálogo de compra. La pantalla NO se gatea: el catálogo base
  // siempre se ve (custodia NOM-004). Cierre: se sacó a su archivo.
  'note_catalog_screen.dart',
  'license_panel.dart',
  'license_plan_builder_screen.dart',
};

class _FakeAcuity extends AcuityService {
  @override
  Future<List<dynamic>> appointmentTypes() async => const [];
}

Future<void> _pump(WidgetTester tester, Widget screen) async {
  tester.view.physicalSize = const Size(1200, 2200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(ProviderScope(
    overrides: [acuityServiceProvider.overrideWithValue(_FakeAcuity())],
    child: MaterialApp(
      theme: ThemeData(extensions: <ThemeExtension<dynamic>>[BrandTokens.kura]),
      home: screen,
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  const lockCta = 'Agregar por \$1,200 al mes';

  test('_gatedScreens está completa: todo screen que menciona premiumAdminFor está '
      'enumerado (o es una excepción explícita)', () {
    final gatedFiles = {for (final g in _gatedScreens) g.file};
    final dir = Directory('lib/features/admin');
    final mentioning = dir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .where((f) => f.readAsStringSync().contains('premiumAdminFor'))
        .map((f) => f.uri.pathSegments.last)
        .toList();

    expect(mentioning, isNotEmpty,
        reason: 'No se halló ningún archivo con premiumAdminFor; ¿ruta mal?');

    for (final file in mentioning) {
      expect(
        gatedFiles.contains(file) || _nonGatedAdminFiles.contains(file),
        isTrue,
        reason: '$file menciona premiumAdminFor pero no está en _gatedScreens '
            '(si es una pantalla gateada, enumérala ahí para que esta prueba la '
            'renderice) ni en _nonGatedAdminFiles (si de verdad no se gatea).',
      );
    }
    // Y las excepciones/enumeradas siguen mencionándolo (no quedaron obsoletas).
    for (final f in gatedFiles) {
      expect(mentioning, contains(f),
          reason: '$f está en _gatedScreens pero ya no menciona premiumAdminFor: '
              '¿se le cayó el candado?');
    }
  });

  testWidgets('sin module:admin: todas las gateadas muestran el bloqueo con precio',
      (tester) async {
    final repo = await DataRepository.instance(); // billing_catalog sembrado
    const org = 'gated-sin-admin'; // sin derechos → sin module:admin
    for (final g in _gatedScreens) {
      await _pump(tester, g.build(repo, org));
      expect(find.text(lockCta), findsOneWidget, reason: '${g.name} sin módulo');
    }
  });

  testWidgets('con module:admin: ninguna de las gateadas muestra el bloqueo',
      (tester) async {
    final store = await LocalStore.instance();
    final repo = await DataRepository.instance();
    const org = 'gated-con-admin';
    await store.upsert(Collections.orgEntitlements, {
      'id': '$org-admin',
      'organization_id': org,
      'kind': 'module',
      'key': 'admin',
      'status': 'active',
      'source': 'master',
    });
    for (final g in _gatedScreens) {
      await _pump(tester, g.build(repo, org));
      expect(find.text(lockCta), findsNothing, reason: '${g.name} con módulo');
    }
  });
}
