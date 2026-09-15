// §10.2/§10.3/§10.7 sobre el mecanismo COMPARTIDO de las pantallas clínicas (todas pasan
// por KuraScreen.primaryAction): CON riel la acción es un botón sólido en el encabezado y NO
// hay FAB; SIN riel es un FAB abajo a la derecha y NO hay botón en el encabezado; y si la
// acción es null (condición del §8.3 sin cumplir) no hay ni uno ni otro.
//
// CI-only: KuraScreen arrastra google_fonts (no compila en el toolchain local).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kuratracker/core/design/tokens.dart';
import 'package:kuratracker/core/nav/section_action.dart';
import 'package:kuratracker/core/providers/session_provider.dart';
import 'package:kuratracker/core/router/app_shell.dart';
import 'package:kuratracker/core/widgets/kura_primary_fab.dart';
import 'package:kuratracker/models/app_user.dart';
import 'package:kuratracker/models/module_key.dart';

class _FakeSession extends SessionController {
  _FakeSession(AppUser user) {
    state = SessionState(user: user);
  }
}

const _clin = AppUser(
  id: 'c1', role: AppRole.clinico, fullName: 'Clin Uno',
  email: 'c@x.test', staffId: 's1', organizationId: 'org-demo',
);

Future<void> _pump(WidgetTester t, Size size, {required SectionAction? action}) async {
  t.view.devicePixelRatio = 1.0;
  t.view.physicalSize = size;
  addTearDown(() {
    t.view.resetPhysicalSize();
    t.view.resetDevicePixelRatio();
  });
  await t.pumpWidget(ProviderScope(
    overrides: [
      sessionProvider.overrideWith((ref) => _FakeSession(_clin)),
      enabledModulesProvider.overrideWithValue(const {
        ModuleKey.patients,
        ModuleKey.agenda,
        ModuleKey.reports,
      }),
    ],
    child: MaterialApp(
      theme: ThemeData(extensions: <ThemeExtension<dynamic>>[BrandTokens.kura]),
      home: KuraScreen(
        title: 'Prueba',
        primaryAction: action,
        body: const SizedBox(),
      ),
    ),
  ));
  await t.pump();
}

SectionAction _action() => SectionAction(
      sectionKey: 'prueba',
      label: 'Crear algo',
      icon: Icons.add,
      onPressed: () {},
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('≥900 (riel): botón sólido en el encabezado, sin FAB', (t) async {
    await _pump(t, const Size(1400, 900), action: _action());
    expect(find.byType(SectionActionButton), findsOneWidget);
    expect(find.byType(KuraPrimaryFab), findsNothing);
  });

  testWidgets('<900 (sin riel): FAB, sin botón en el encabezado', (t) async {
    await _pump(t, const Size(500, 900), action: _action());
    expect(find.byType(KuraPrimaryFab), findsOneWidget);
    expect(find.byType(SectionActionButton), findsNothing);
  });

  testWidgets('acción null (§8.3): ni botón ni FAB, en ninguna anchura', (t) async {
    await _pump(t, const Size(1400, 900), action: null);
    expect(find.byType(SectionActionButton), findsNothing);
    expect(find.byType(KuraPrimaryFab), findsNothing);
    await _pump(t, const Size(500, 900), action: null);
    expect(find.byType(SectionActionButton), findsNothing);
    expect(find.byType(KuraPrimaryFab), findsNothing);
  });
}
