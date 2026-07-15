import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:kuratracker/models/note_option_catalog.dart';
import 'package:kuratracker/services/data_repository.dart';

/// Cobertura de `DataRepository.seedDefaultNoteOptions()`: el boton
/// "Cargar catálogo base" agregado a `NoteCatalogTab` (Administracion /
/// Plataforma), pensado sobre todo para un centro NUEVO (creado desde
/// Plataforma por el master via `createOrganization()`, que
/// deliberadamente no siembra ningun concepto) para no tener que dar de
/// alta uno por uno los conceptos mas comunes.
///
/// Usa el DataRepository real respaldado por LocalStore (backend de la
/// demo, SharedPreferences mockeado); DemoSeed ya deja precargado el
/// catalogo base para sus 2 organizaciones ("Kura+ Wound Care" y
/// "Clínica Vitalis"), asi que estos tests usan una organizacion NUEVA
/// (creada en el propio test via `createOrganization()`) para poder
/// probar el caso real de un centro vacio.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test(
      'seedDefaultNoteOptions() carga las 4 secciones del catalogo base en '
      'un centro nuevo sin ningun concepto propio', () async {
    final repo = await DataRepository.instance();

    final org = await repo.createOrganization('Centro Nuevo Sin Catalogo');

    for (final field in NoteOptionField.values) {
      expect(
        repo.listAllNoteOptions(field, organizationId: org.id),
        isEmpty,
        reason: 'Un centro recien creado desde Plataforma no debe traer ningun '
            'concepto precargado (createOrganization() no siembra catalogo).',
      );
    }

    final summary = await repo.seedDefaultNoteOptions(organizationId: org.id);

    expect(
      summary.added,
      DataRepository.defaultNoteOptionCatalog.length,
      reason: 'Debe agregarse exactamente el catalogo base completo en un centro vacio.',
    );
    expect(summary.updated, 0);
    expect(summary.skipped, 0);

    for (final field in NoteOptionField.values) {
      final expectedLabels = DataRepository.defaultNoteOptionCatalog
          .where((e) => e.$1 == field)
          .map((e) => e.$2)
          .toSet();
      final actualLabels =
          repo.listAllNoteOptions(field, organizationId: org.id).map((o) => o.label).toSet();
      expect(
        actualLabels,
        expectedLabels,
        reason: 'Los conceptos base de "${field.label}" deben coincidir exactamente.',
      );
    }
  });

  test(
      'seedDefaultNoteOptions() es idempotente: llamarlo dos veces no '
      'duplica conceptos', () async {
    final repo = await DataRepository.instance();
    final org = await repo.createOrganization('Centro Nuevo Idempotencia');

    await repo.seedDefaultNoteOptions(organizationId: org.id);
    final countAfterFirst =
        repo.listAllNoteOptions(NoteOptionField.materialsUsed, organizationId: org.id).length;

    final secondSummary = await repo.seedDefaultNoteOptions(organizationId: org.id);

    expect(
      secondSummary.added,
      0,
      reason: 'La segunda carga no debe agregar nada nuevo (todo ya existe).',
    );
    expect(
      repo.listAllNoteOptions(NoteOptionField.materialsUsed, organizationId: org.id).length,
      countAfterFirst,
      reason: 'El total de conceptos de "Material utilizado" no debe cambiar en la segunda carga.',
    );
  });

  test(
      'seedDefaultNoteOptions() no pisa un concepto que el admin ya '
      'personalizo o desactivo antes de cargar el catalogo base', () async {
    final repo = await DataRepository.instance();
    final org = await repo.createOrganization('Centro Nuevo Personalizado');

    // El admin desactiva de antemano un concepto que tambien esta en el
    // catalogo base, con exactamente el mismo texto (mismo (field, label)).
    final preExisting = await repo.createNoteOption(
      field: NoteOptionField.evolution,
      label: 'Favorable, con reducción de área',
      organizationId: org.id,
    );
    await repo.setNoteOptionActive(preExisting.id, false);

    final summary = await repo.seedDefaultNoteOptions(organizationId: org.id);

    final reloaded = repo
        .listAllNoteOptions(NoteOptionField.evolution, organizationId: org.id)
        .firstWhere((o) => o.id == preExisting.id);
    expect(
      reloaded.isActive,
      isFalse,
      reason: 'Cargar el catalogo base no debe reactivar un concepto que el admin '
          'desactivo deliberadamente, aunque el texto coincida con el catalogo base.',
    );
    expect(
      summary.added,
      DataRepository.defaultNoteOptionCatalog.length - 1,
      reason: 'El concepto ya existente (aunque desactivado) no debe contarse como '
          'agregado; el resto del catalogo base si.',
    );

    // Tampoco debe haberse creado una fila duplicada con ese mismo texto.
    final matches = repo
        .listAllNoteOptions(NoteOptionField.evolution, organizationId: org.id)
        .where((o) => o.label == 'Favorable, con reducción de área');
    expect(matches.length, 1);
  });

  test(
      'seedDefaultNoteOptions() en un centro distinto no afecta el catalogo '
      'de otro centro (mismo aislamiento por organizacion que el resto del '
      'catalogo)', () async {
    final repo = await DataRepository.instance();
    final orgA = await repo.createOrganization('Centro A Catalogo Base');
    final orgB = await repo.createOrganization('Centro B Catalogo Base');

    await repo.seedDefaultNoteOptions(organizationId: orgA.id);

    for (final field in NoteOptionField.values) {
      expect(
        repo.listAllNoteOptions(field, organizationId: orgB.id),
        isEmpty,
        reason: 'Cargar el catalogo base en el Centro A no debe crear nada en el Centro B.',
      );
    }
  });
}
