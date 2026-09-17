// §15 etapa 6.2 — los TRES estados de la Matriz, cada uno con su render. 364 líneas de pantalla no
// pueden quedar sin prueba: autora → catálogo con cabecera; admin sin autoría → editor propio
// (delegado); sin permiso → mensaje dicho, no vacío. El candado comercial (sin module:admin) lo
// cubre admin_gated_screens_lock_test; aquí todos los orgs traen el módulo para llegar al gating por rol.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:kuratracker/core/design/tokens.dart';
import 'package:kuratracker/core/providers/session_provider.dart';
import 'package:kuratracker/features/admin/protocol_matrix_screen.dart';
import 'package:kuratracker/features/admin/protocol_product_rules_screen.dart';
import 'package:kuratracker/models/app_user.dart';
import 'package:kuratracker/services/data_repository.dart';
import 'package:kuratracker/services/local_db/local_store.dart';

class _FakeSessionController extends SessionController {
  _FakeSessionController(AppUser user) {
    state = SessionState(user: user);
  }
}

AppUser _user(AppRole role, String org) => AppUser(
      id: 'u-${role.name}',
      role: role,
      fullName: 'X',
      email: 'x@y.test',
      organizationId: org,
    );

Future<void> _seedEntitlement(
    LocalStore store, String org, String key) async {
  await store.upsert(Collections.orgEntitlements, {
    'id': '$org-$key',
    'organization_id': org,
    'kind': 'module',
    'key': key,
    'status': 'active',
    'source': 'master',
  });
}

Future<void> _pump(
    WidgetTester t, DataRepository repo, AppUser user, String org) async {
  t.view.physicalSize = const Size(1200, 2200);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.resetPhysicalSize);
  addTearDown(t.view.resetDevicePixelRatio);
  await t.pumpWidget(ProviderScope(
    overrides: [
      sessionProvider.overrideWith((ref) => _FakeSessionController(user)),
    ],
    child: MaterialApp(
      theme: ThemeData(extensions: <ThemeExtension<dynamic>>[BrandTokens.kura]),
      // La Matriz ya es un CUERPO sin Scaffold (el shell de /admin da el chrome);
      // se envuelve en Scaffold para el ancestro Material.
      home: Scaffold(body: ProtocolMatrixScreen(repo: repo, organizationId: org)),
    ),
  ));
  await t.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // protocol_catalog_rules es GLOBAL (sin org): sin limpiarla, las reglas que crea un
  // test (alta/edición) se filtran al siguiente. Se limpia antes de cada uno.
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final store = await LocalStore.instance();
    await store.clearCollection(Collections.protocolCatalogRules);
  });

  testWidgets('AUTORA (admin + protocol:author) → catálogo con cabecera del régimen',
      (t) async {
    final store = await LocalStore.instance();
    final repo = await DataRepository.instance();
    const org = 'matrix-author';
    await _seedEntitlement(store, org, 'admin'); // pasa el candado comercial
    await _seedEntitlement(store, org, 'protocol:author'); // autoría
    await _pump(t, repo, _user(AppRole.admin, org), org);
    // La cabecera del interruptor (el guion de la presentación) siempre está en modo catálogo.
    expect(find.text('Este centro resuelve el protocolo con:'), findsOneWidget);
    expect(find.byType(ProtocolProductRulesScreen), findsNothing);
  });

  testWidgets('EDITOR: "Nueva regla" da de alta una regla con su FRASE (el hueco §15)',
      (t) async {
    final store = await LocalStore.instance();
    final repo = await DataRepository.instance();
    const org = 'matrix-editor';
    await _seedEntitlement(store, org, 'admin');
    await _seedEntitlement(store, org, 'protocol:author');
    await _pump(t, repo, _user(AppRole.admin, org), org);

    final before = repo.listProtocolCatalogRules().length;
    await t.tap(find.text('Nueva regla'));
    await t.pumpAndSettle();
    // La FRASE para la nota es el campo central (sin él, el protocolo no sirve).
    expect(find.text('Frase para la nota'), findsOneWidget);
    await t.enterText(
        find.widgetWithText(TextField, 'Frase para la nota'), 'Curación cada 72 h');
    await t.tap(find.text('Crear'));
    await t.pumpAndSettle();

    final rules = repo.listProtocolCatalogRules();
    expect(rules.length, before + 1);
    expect(rules.any((r) => r.notePhrase == 'Curación cada 72 h'), isTrue);
    expect(find.text('Regla creada'), findsOneWidget); // no falla en silencio
  });

  testWidgets('EDITOR: editar REEMPLAZA la frase (no la antepone)', (t) async {
    final store = await LocalStore.instance();
    final repo = await DataRepository.instance();
    const org = 'matrix-edit-replace';
    await _seedEntitlement(store, org, 'admin');
    await _seedEntitlement(store, org, 'protocol:author');
    await store.upsert(Collections.protocolCatalogRules, {
      'id': 'cat-edit-1',
      'category': 'aposito',
      'note_phrase': 'FRASE VIEJA',
      'quantity_mode': 'fixed',
      'quantity_value': 1,
      'sort_order': 0,
    });
    await _pump(t, repo, _user(AppRole.admin, org), org);

    await t.tap(find.byIcon(Icons.edit_outlined).first);
    await t.pumpAndSettle();
    // El campo llega PRECARGADO con la frase vieja.
    expect(find.widgetWithText(TextField, 'FRASE VIEJA'), findsOneWidget);
    // enterText selecciona-todo y escribe encima: debe REEMPLAZAR, no anteponer.
    await t.enterText(
        find.widgetWithText(TextField, 'Frase para la nota'), 'FRASE NUEVA');
    await t.tap(find.text('Guardar'));
    await t.pumpAndSettle();

    final rule = repo
        .listProtocolCatalogRules()
        .firstWhere((r) => r.id == 'cat-edit-1');
    expect(rule.notePhrase, 'FRASE NUEVA'); // reemplazada, no "FRASE NUEVAFRASE VIEJA"
  });

  testWidgets('admin SIN autoría → editor de reglas propias (delegado)', (t) async {
    final store = await LocalStore.instance();
    final repo = await DataRepository.instance();
    const org = 'matrix-own';
    await _seedEntitlement(store, org, 'admin'); // módulo sí; protocol:author NO
    await _pump(t, repo, _user(AppRole.admin, org), org);
    // Se delega al editor existente (para no perder la edición de reglas propias).
    expect(find.byType(ProtocolProductRulesScreen), findsOneWidget);
    expect(find.text('Este centro resuelve el protocolo con:'), findsNothing);
  });

  testWidgets('la tabla muestra contexto LEGIBLE + nota + encabezados de columna', (t) async {
    final store = await LocalStore.instance();
    final repo = await DataRepository.instance();
    const org = 'matrix-table';
    await _seedEntitlement(store, org, 'admin');
    await _seedEntitlement(store, org, 'protocol:author');
    await store.upsert(Collections.protocolCatalogRules, {
      'id': 'cat-tbl-1',
      'category': 'aposito',
      'context_kind': 'etiologia',
      'context_value': 'pie_diabetico',
      'name': 'Producto X',
      'brand': 'Marca Y',
      'note_phrase': 'Aplicar cada 48 h',
      'quantity_mode': 'fixed',
      'quantity_value': 1,
      'sort_order': 0,
    });
    await _pump(t, repo, _user(AppRole.admin, org), org);
    // Etiqueta legible (en el chip de filtro y en la fila), NO el valor crudo con guion bajo (fix #1).
    expect(find.text('Pie diabético'), findsWidgets);
    expect(find.text('pie_diabetico'), findsNothing);
    // note_phrase visible + su encabezado de columna (fix #2, antes no estaban).
    expect(find.text('Aplicar cada 48 h'), findsOneWidget);
    expect(find.text('FRASE PARA LA NOTA'), findsOneWidget);
    expect(find.text('CONTEXTO'), findsOneWidget);
  });

  testWidgets('sin permiso (no admin) → se DICE, no se deja en blanco', (t) async {
    final store = await LocalStore.instance();
    final repo = await DataRepository.instance();
    const org = 'matrix-noperm';
    await _seedEntitlement(store, org, 'admin');
    await _pump(t, repo, _user(AppRole.clinico, org), org);
    expect(find.textContaining('No tienes permiso'), findsOneWidget);
    expect(find.byType(ProtocolProductRulesScreen), findsNothing);
  });
}
