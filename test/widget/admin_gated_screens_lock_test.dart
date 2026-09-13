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
import 'package:kuratracker/features/admin/acuity_session_type_screen.dart';
import 'package:kuratracker/features/admin/acuity_visit_type_map_screen.dart';
import 'package:kuratracker/features/admin/patient_cleanup_screen.dart';

/// 2b — que el candado esté PUESTO, no solo que funcione. Enumera las CINCO
/// pantallas gateadas por el módulo Administración avanzada y exige que cada una,
/// abierta sin el módulo (como al teclear su URL), muestre el bloqueo con precio; y
/// que con el módulo, ninguna lo muestre. La lista vive en UN solo lugar: agregar
/// una sexta pantalla gateada obliga a sumarla aquí.
///
/// Las de Acuity leen acuityServiceProvider en initState (red); se sustituye por un
/// fake para poder montarlas sin Supabase.
final _gatedScreens =
    <({String name, Widget Function(DataRepository, String?) build})>[
  (name: 'ProtocolKuraScreen', build: (r, o) => ProtocolKuraScreen(repo: r, organizationId: o)),
  (name: 'ProtocolProductRulesScreen', build: (r, o) => ProtocolProductRulesScreen(repo: r, organizationId: o)),
  (name: 'AcuitySessionTypeScreen', build: (r, o) => AcuitySessionTypeScreen(repo: r, organizationId: o)),
  (name: 'AcuityVisitTypeMapScreen', build: (r, o) => AcuityVisitTypeMapScreen(repo: r, organizationId: o)),
  (name: 'PatientCleanupScreen', build: (r, o) => PatientCleanupScreen(repo: r, organizationId: o)),
];

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

  testWidgets('sin module:admin: las 5 muestran el bloqueo con precio',
      (tester) async {
    final repo = await DataRepository.instance(); // billing_catalog sembrado
    const org = 'gated-sin-admin'; // sin derechos → sin module:admin
    for (final g in _gatedScreens) {
      await _pump(tester, g.build(repo, org));
      expect(find.text(lockCta), findsOneWidget, reason: '${g.name} sin módulo');
    }
  });

  testWidgets('con module:admin: ninguna de las 5 muestra el bloqueo',
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
