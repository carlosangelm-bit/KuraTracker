import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:kuratracker/models/center_type.dart';
import 'package:kuratracker/models/module_key.dart';
import 'package:kuratracker/services/data_repository.dart';

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
}
