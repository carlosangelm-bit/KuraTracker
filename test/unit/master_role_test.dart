import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:kuratracker/models/app_user.dart';
import 'package:kuratracker/models/note_option_catalog.dart';
import 'package:kuratracker/services/data_repository.dart';

/// Cobertura del rol `master` (administrador de plataforma, ver
/// 0012_master_role.sql y PlatformHomeScreen).
///
/// Regla de oro que estas pruebas verifican en la capa de repositorio: el
/// master administra ESTRUCTURA (organizations/sites/staff/
/// note_option_catalog) de TODOS los centros -- listOrganizations() /
/// createOrganization() sin filtro -- pero cuando trabaja "dentro" de un
/// centro elegido en el selector de PlatformHomeScreen, listSites() /
/// listStaff() / listNoteOptions() / listAllNoteOptions() con
/// `organizationId` deben acotar el resultado a ESE centro exclusivamente,
/// sin mezclar filas de otros centros. Estos mismos metodos, sin
/// `organizationId` (como los usa el admin normal), siguen devolviendo
/// todo lo que haya en el LocalStore -- el aislamiento real entre
/// organizaciones para el admin normal lo da RLS en Supabase (0011), no
/// esta capa; en el backend de demo (LocalStore) no hay RLS, por eso el
/// filtro opcional es la unica forma de probar el comportamiento del
/// selector de Plataforma sin credenciales reales.
///
/// Usa el DataRepository real respaldado por LocalStore (backend de la
/// demo, SharedPreferences mockeado), poblado por DemoSeed con 2
/// organizaciones ("Kura+ Wound Care" y "Clínica Vitalis") para poder
/// ejercitar el filtro con datos de mas de un centro.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test(
      'DemoSeed pobla un perfil master (organization_id null) ademas de al '
      'menos 2 organizaciones, para poder probar el selector de Plataforma',
      () async {
    final repo = await DataRepository.instance();

    final master = repo.findUserByEmail('master@kuratracker.mx');
    expect(master, isNotNull, reason: 'DemoSeed debe incluir un perfil master de prueba.');
    expect(master!.role, AppRole.master);
    expect(master.isMaster, isTrue);
    expect(
      master.organizationId,
      isNull,
      reason: 'El master no pertenece a ningun centro en particular (administra todos).',
    );

    final orgs = repo.listOrganizations();
    expect(
      orgs.length,
      greaterThanOrEqualTo(2),
      reason: 'DemoSeed debe incluir al menos 2 organizaciones (Kura+ y Clínica Vitalis) '
          'para poder ejercitar el selector de centro de Plataforma.',
    );
    expect(orgs.any((o) => o.name == 'Clínica Vitalis'), isTrue);
  });

  test(
      'createOrganization() agrega un centro nuevo, activo por defecto, y '
      'aparece de inmediato en listOrganizations() junto con los ya '
      'sembrados por DemoSeed', () async {
    final repo = await DataRepository.instance();

    final before = repo.listOrganizations();
    final countBefore = before.length;

    final created = await repo.createOrganization('Centro de Prueba E2E');

    expect(created.name, 'Centro de Prueba E2E');
    expect(created.isActive, isTrue);

    final after = repo.listOrganizations();
    expect(after.length, countBefore + 1);
    expect(after.any((o) => o.id == created.id && o.name == 'Centro de Prueba E2E'), isTrue);
  });

  test(
      'setOrganizationActive() cambia solo el estado activo/inactivo de la '
      'organizacion indicada, sin afectar a las demas', () async {
    final repo = await DataRepository.instance();

    final created = await repo.createOrganization('Centro para desactivar');
    expect(created.isActive, isTrue);

    await repo.setOrganizationActive(created.id, false);

    final reloaded = repo.listOrganizations().firstWhere((o) => o.id == created.id);
    expect(reloaded.isActive, isFalse);

    // El resto de organizaciones (p.ej. las de DemoSeed) no deben verse
    // afectadas por este cambio puntual.
    final others = repo.listOrganizations().where((o) => o.id != created.id);
    expect(others.any((o) => o.name == 'Clínica Vitalis' && !o.isActive), isFalse);
  });

  test(
      'listSites(organizationId: ...) acota el resultado exclusivamente al '
      'centro indicado: el sitio de Clínica Vitalis no debe aparecer al '
      'filtrar por el centro Kura+, y viceversa', () async {
    final repo = await DataRepository.instance();

    final orgs = repo.listOrganizations();
    final kuraPlus = orgs.firstWhere((o) => o.name != 'Clínica Vitalis');
    final vitalis = orgs.firstWhere((o) => o.name == 'Clínica Vitalis');

    final allSites = repo.listSites();
    expect(
      allSites.length,
      greaterThanOrEqualTo(2),
      reason: 'DemoSeed debe poblar sitios de al menos 2 organizaciones distintas.',
    );

    final kuraSites = repo.listSites(organizationId: kuraPlus.id);
    final vitalisSites = repo.listSites(organizationId: vitalis.id);

    expect(kuraSites, isNotEmpty);
    expect(vitalisSites, isNotEmpty);
    expect(
      kuraSites.every((s) => s.organizationId == kuraPlus.id),
      isTrue,
      reason: 'Ningun sitio de otro centro debe filtrarse al pedir el de Kura+.',
    );
    expect(
      vitalisSites.every((s) => s.organizationId == vitalis.id),
      isTrue,
      reason: 'Ningun sitio de otro centro debe filtrarse al pedir el de Vitalis.',
    );
    // El total sin filtro debe ser al menos la suma de ambos subconjuntos
    // (puede haber mas centros/sitios ademas de estos dos).
    expect(allSites.length, greaterThanOrEqualTo(kuraSites.length + vitalisSites.length));
  });

  test(
      'listStaff(organizationId: ...) acota el personal exclusivamente al '
      'centro indicado: la administradora de Vitalis no debe aparecer al '
      'filtrar por el centro Kura+', () async {
    final repo = await DataRepository.instance();

    final orgs = repo.listOrganizations();
    final kuraPlus = orgs.firstWhere((o) => o.name != 'Clínica Vitalis');
    final vitalis = orgs.firstWhere((o) => o.name == 'Clínica Vitalis');

    final kuraStaff = repo.listStaff(organizationId: kuraPlus.id);
    final vitalisStaff = repo.listStaff(organizationId: vitalis.id);

    expect(kuraStaff, isNotEmpty);
    expect(vitalisStaff, isNotEmpty);
    expect(kuraStaff.every((s) => s.organizationId == kuraPlus.id), isTrue);
    expect(vitalisStaff.every((s) => s.organizationId == vitalis.id), isTrue);
    expect(
      vitalisStaff.any((s) => s.fullName == 'Administradora Vitalis'),
      isTrue,
      reason: 'DemoSeed debe incluir personal propio de Clínica Vitalis.',
    );
    expect(
      kuraStaff.any((s) => s.fullName == 'Administradora Vitalis'),
      isFalse,
      reason: 'El personal de Vitalis no debe filtrarse al pedir el de Kura+.',
    );
  });

  test(
      'listAllNoteOptions(field, organizationId: ...) acota el catalogo de '
      'conceptos al centro indicado: un concepto creado para Vitalis no '
      'debe aparecer al filtrar por Kura+, y viceversa', () async {
    final repo = await DataRepository.instance();

    final orgs = repo.listOrganizations();
    final kuraPlus = orgs.firstWhere((o) => o.name != 'Clínica Vitalis');
    final vitalis = orgs.firstWhere((o) => o.name == 'Clínica Vitalis');

    final createdForVitalis = await repo.createNoteOption(
      field: NoteOptionField.materialsUsed,
      label: 'Material exclusivo de Vitalis (prueba)',
      organizationId: vitalis.id,
    );

    final vitalisOptions =
        repo.listAllNoteOptions(NoteOptionField.materialsUsed, organizationId: vitalis.id);
    final kuraOptions =
        repo.listAllNoteOptions(NoteOptionField.materialsUsed, organizationId: kuraPlus.id);

    expect(vitalisOptions.any((o) => o.id == createdForVitalis.id), isTrue);
    expect(
      kuraOptions.any((o) => o.id == createdForVitalis.id),
      isFalse,
      reason: 'Un concepto creado para el catalogo de Vitalis no debe aparecer al '
          'filtrar por el catalogo de Kura+.',
    );

    // Sin filtro (como lo usaria un admin normal sin selector de centro),
    // el concepto sigue apareciendo -- el filtro es estrictamente opcional
    // y aditivo, no cambia el comportamiento existente cuando se omite.
    final unfiltered = repo.listAllNoteOptions(NoteOptionField.materialsUsed);
    expect(unfiltered.any((o) => o.id == createdForVitalis.id), isTrue);
  });
}
