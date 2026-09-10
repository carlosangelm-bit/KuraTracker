import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:kuratracker/models/center_type.dart';
import 'package:kuratracker/models/module_key.dart';
import 'package:kuratracker/services/data_repository.dart';
import 'package:kuratracker/services/local_db/local_store.dart';

/// Fase 1 §4 — El AND por licencia en la app:
///   efectivo = tiene DERECHO (org_entitlements) AND module_settings/default AND
///   availableFor(tipo). Sin el derecho, el módulo NO se muestra aunque el
///   default lo tenga encendido. Sin derechos cargados, el conjunto es vacío
///   (fallback seguro), no los defaults del tipo de centro.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('mapeo módulo → derecho de VISIBILIDAD (§4 + desacople 0121)', () {
    // TODOS los módulos gobiernan su VISIBILIDAD con module:clinico. Insumos y
    // Comercial se movieron de su clave homónima a 'clinico' al desacoplar
    // visibilidad de pago (0121): su nav monta sobre el clínico, y module:insumos /
    // module:comercial pasaron a ser SOLO el candado de pago (premiumInsumosFor /
    // premiumComercialFor), no la visibilidad. eKare ya era 'clinico' (entra con el
    // clínico sin costo).
    for (final m in [
      ModuleKey.insumos,
      ModuleKey.comercial,
      ModuleKey.patients,
      ModuleKey.agenda,
      ModuleKey.prevention,
      ModuleKey.reports,
      ModuleKey.ekare,
      ModuleKey.vac,
    ]) {
      expect(m.entitlementKey, 'clinico', reason: '$m debe requerir module:clinico');
    }
  });

  test('con derecho + default encendido → módulo visible', () async {
    final repo = await DataRepository.instance();
    final clinica = repo
        .listOrganizations()
        .firstWhere((o) => repo.centerTypeFor(o.id) == CenterType.clinicaHeridas);

    // La clínica demo tiene module:clinico (la clave de visibilidad de insumos tras
    // el desacople 0121), e insumos va encendido por default en clínica de heridas.
    expect(repo.hasModuleEntitlement(clinica.id, 'clinico'), isTrue);
    expect(repo.isModuleEnabled(ModuleKey.patients, organizationId: clinica.id), isTrue);
    expect(repo.isModuleEnabled(ModuleKey.insumos, organizationId: clinica.id), isTrue);
  });

  test('derecho SIN default encendido → sigue apagado (AND requiere ambos)', () async {
    final repo = await DataRepository.instance();
    final hospital = repo
        .listOrganizations()
        .firstWhere((o) => repo.centerTypeFor(o.id) == CenterType.hospital);

    // El hospital demo SÍ tiene el derecho de VISIBILIDAD de insumos (module:clinico,
    // que se siembra a todos), pero insumos está APAGADO por default en hospital → el
    // AND lo deja apagado. (Tras el desacople 0121, la visibilidad de insumos monta
    // sobre clinico, no sobre module:insumos.)
    expect(repo.hasModuleEntitlement(hospital.id, 'clinico'), isTrue);
    expect(repo.isModuleEnabled(ModuleKey.insumos, organizationId: hospital.id), isFalse);
  });

  test('sin derechos (centro desconocido) → conjunto vacío, fallback seguro', () async {
    final repo = await DataRepository.instance();
    expect(repo.hasModuleEntitlement('org-inexistente', 'clinico'), isFalse);
    // Antes del AND, un centro sin datos devolvía los defaults del tipo; ahora,
    // sin derecho, no se muestra nada.
    expect(repo.isModuleEnabled(ModuleKey.patients, organizationId: 'org-inexistente'), isFalse);
    expect(repo.enabledModules(organizationId: 'org-inexistente'), isEmpty);
  });

  test('organizationId null → vacío (no defaults)', () async {
    final repo = await DataRepository.instance();
    expect(repo.isModuleEnabled(ModuleKey.patients, organizationId: null), isFalse);
    expect(repo.enabledModules(organizationId: null), isEmpty);
  });

  test('leer vs escribir + asimetría stripe(status)/master(tiempo)', () async {
    final store = await LocalStore.instance();
    final repo = await DataRepository.instance();
    final past = DateTime.now().subtract(const Duration(days: 1)).toIso8601String();
    final future = DateTime.now().add(const Duration(days: 10)).toIso8601String();
    var n = 0;
    // Cada escenario en su propio org (sin FK en LocalStore), para no chocar por la
    // unicidad (org,kind,key) que la base sí impone.
    Future<String> org(String status, String source, {String? cpe}) async {
      final id = 'rw-${n++}';
      await store.upsert(Collections.orgEntitlements, {
        'id': id,
        'organization_id': id,
        'kind': 'module',
        'key': 'clinico',
        'status': status,
        'source': source,
        if (cpe != null) 'current_period_end': cpe,
      });
      return id;
    }

    // past_due (stripe): LEE, no escribe.
    final pd = await org('past_due', 'stripe');
    expect(repo.canReadModule(pd, 'clinico'), isTrue, reason: 'past_due lee');
    expect(repo.canWriteModule(pd, 'clinico'), isFalse, reason: 'past_due no escribe');

    // canceled: LEE, no escribe.
    final cx = await org('canceled', 'master');
    expect(repo.canReadModule(cx, 'clinico'), isTrue);
    expect(repo.canWriteModule(cx, 'clinico'), isFalse);

    // stripe activo: escribe.
    final sa = await org('active', 'stripe');
    expect(repo.canWriteModule(sa, 'clinico'), isTrue);

    // Asimetría: stripe activo NUNCA se gatea por tiempo (renovación tardía no bloquea).
    final sap = await org('active', 'stripe', cpe: past);
    expect(repo.canWriteModule(sap, 'clinico'), isTrue,
        reason: 'stripe por status, no por current_period_end');

    // master activo pero vencido por TIEMPO (prueba terminada) → no escribe, sí lee.
    final me = await org('active', 'master', cpe: past);
    expect(repo.canReadModule(me, 'clinico'), isTrue, reason: 'prueba vencida sigue leyendo');
    expect(repo.canWriteModule(me, 'clinico'), isFalse, reason: 'prueba vencida no escribe');

    // master activo vigente por tiempo, o sin fecha → escribe.
    expect(repo.canWriteModule(await org('active', 'master', cpe: future), 'clinico'), isTrue);
    expect(repo.canWriteModule(await org('active', 'master'), 'clinico'), isTrue);
  });

  test('candado de escritura en el REPOSITORIO: modo lectura lanza, activo pasa, '
      'sin derecho no bloquea', () async {
    final store = await LocalStore.instance();
    final repo = await DataRepository.instance();
    var n = 0;
    Future<String> orgWith(String? status) async {
      final id = 'wg-${n++}';
      if (status != null) {
        await store.upsert(Collections.orgEntitlements, {
          'id': '$id-e',
          'organization_id': id,
          'kind': 'module',
          'key': 'clinico',
          'status': status,
          'source': 'stripe',
        });
      }
      return id;
    }

    // past_due: el candado del repositorio lanza CLINICAL_READ_ONLY (no depende de
    // que la UI escondiera el botón).
    final ro = await orgWith('past_due');
    await expectLater(
      repo.createPatient(fullName: 'RO', organizationId: ro),
      throwsA(predicate(
          (e) => DataRepository.readOnlyMessageFor(e as Object) != null)),
    );

    // active: pasa.
    final ok = await orgWith('active');
    final p = await repo.createPatient(fullName: 'OK', organizationId: ok);
    expect(p.organizationId, ok);

    // sin derecho clínico (centro sin sembrar / fixture): NO bloquea.
    final none = await orgWith(null);
    final p2 = await repo.createPatient(fullName: 'None', organizationId: none);
    expect(p2.organizationId, none);
  });
}
