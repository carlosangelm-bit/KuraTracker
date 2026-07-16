// Cobertura del fix de layout movil de ReportsScreen (rama
// feat/reports-mobile-list-fix): verifica que en un viewport angosto
// (movil) el cuadro de pacientes se ve con contenido y que el resto del
// formulario (incluir/evidencias/generar) es alcanzable via scroll de
// pagina; y que en un viewport ancho (escritorio) no hay regresion.
// Tambien cubre el estado vacio ("No hay pacientes disponibles").
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:kuratracker/core/providers/session_provider.dart';
import 'package:kuratracker/features/reports/reports_screen.dart';
import 'package:kuratracker/models/app_user.dart';

/// SessionController de prueba: expone un estado fijo sin tocar
/// Supabase/AppConfig (coincide con el modo demo local usado por el resto
/// de la suite de tests).
class _FakeSessionController extends SessionController {
  _FakeSessionController(AppUser user) {
    state = SessionState(user: user);
  }
}

const _adminUser = AppUser(
  id: 'admin-1',
  role: AppRole.admin,
  fullName: 'Admin de prueba',
  email: 'admin.prueba@kuratracker.test',
);

// Rol clinico sin staffId asignado: repo.listPatientsForStaff no se
// invoca (staffId == null), por lo que ReportsScreen calcula
// patients = <Patient>[] -> dispara el estado vacio.
const _clinicoSinAsignaciones = AppUser(
  id: 'clinico-1',
  role: AppRole.clinico,
  fullName: 'Clinico sin pacientes',
  email: 'clinico.prueba@kuratracker.test',
);

Widget _buildApp(AppUser user) {
  return ProviderScope(
    overrides: [
      sessionProvider.overrideWith((ref) => _FakeSessionController(user)),
    ],
    child: const MaterialApp(home: ReportsScreen()),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets(
    'viewport movil angosto: el cuadro de pacientes muestra varios '
    'pacientes y el resto del formulario es alcanzable por scroll',
    (tester) async {
      // iPhone SE-ish: 360x640 logico, tipico "viewport corto" de movil.
      await tester.binding.setSurfaceSize(const Size(360, 640));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(_buildApp(_adminUser));
      await tester.pumpAndSettle();

      // El cuadro de pacientes (demo seed: admin ve listAllPatients(),
      // que incluye varios pacientes) debe estar visible con al menos un
      // CheckboxListTile.
      expect(find.byType(CheckboxListTile), findsWidgets);
      expect(find.text('Selecciona pacientes'), findsOneWidget);

      // El boton "Generar reporte (PDF)" vive al final del formulario,
      // debajo del cuadro de pacientes y las secciones de
      // incluir/evidencias. En un viewport de 640px de alto no cabe todo
      // sin scroll; debe ser alcanzable haciendo scroll de la pagina
      // (SingleChildScrollView), no quedar recortado/inaccesible.
      final generarFinder = find.text('Generar reporte (PDF)');
      await tester.dragUntilVisible(
        generarFinder,
        find.byType(SingleChildScrollView),
        const Offset(0, -200),
      );
      expect(generarFinder, findsOneWidget);

      // Las secciones intermedias tambien deben ser alcanzables.
      expect(find.text('Incluir en el reporte'), findsOneWidget);
      expect(find.text('Evidencias'), findsOneWidget);
    },
  );

  testWidgets(
    'viewport de escritorio (ancho): sin regresion, pacientes y formulario '
    'completo visibles/alcanzables',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(_buildApp(_adminUser));
      await tester.pumpAndSettle();

      expect(find.byType(CheckboxListTile), findsWidgets);
      expect(find.text('Selecciona pacientes'), findsOneWidget);

      final generarFinder = find.text('Generar reporte (PDF)');
      await tester.dragUntilVisible(
        generarFinder,
        find.byType(SingleChildScrollView),
        const Offset(0, -200),
      );
      expect(generarFinder, findsOneWidget);
    },
  );

  testWidgets(
    'sin pacientes disponibles: se muestra el estado vacio en vez de un '
    'cuadro en blanco',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(360, 640));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(_buildApp(_clinicoSinAsignaciones));
      await tester.pumpAndSettle();

      expect(find.text('No hay pacientes disponibles'), findsOneWidget);
      // El ListView.builder de pacientes no debe renderizarse en el
      // estado vacio (los 3 CheckboxListTile de "Incluir en el reporte"
      // si son parte fija del formulario y deben seguir presentes).
      expect(find.byType(ListView), findsNothing);
      expect(find.byType(CheckboxListTile), findsNWidgets(3));
    },
  );
}
