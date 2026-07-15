import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:kuratracker/models/consultation.dart';
import 'package:kuratracker/models/note_option_catalog.dart';
import 'package:kuratracker/services/data_repository.dart';

/// Cobertura del borrado de conceptos del catalogo de la nota de
/// seguimiento (Administracion -> Configuracion), agregado junto al
/// switch de activar/desactivar existente.
///
/// Usa el DataRepository real respaldado por LocalStore (backend de la
/// demo, SharedPreferences mockeado) para ejercitar exactamente el mismo
/// camino que usa la UI: createNoteOption() -> deleteNoteOption() ->
/// listAllNoteOptions(), sin necesidad de credenciales de Supabase real
/// (la politica RLS `note_option_catalog_admin_delete` de la migracion
/// 0011 solo restringe QUIEN puede borrar en produccion; el metodo del
/// repositorio en si es el mismo DELETE en ambos backends via la
/// interfaz DataStore).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test(
      'deleteNoteOption() borra la fila y deja de aparecer en '
      'listAllNoteOptions(), sin afectar otros conceptos del mismo campo',
      () async {
    final repo = await DataRepository.instance();

    final created = await repo.createNoteOption(
      field: NoteOptionField.materialsUsed,
      label: 'Concepto de prueba para borrar',
      organizationId: null,
    );

    final before = repo.listAllNoteOptions(NoteOptionField.materialsUsed);
    expect(
      before.any((o) => o.id == created.id),
      isTrue,
      reason: 'El concepto recien creado debe aparecer en el listado antes de borrarlo.',
    );
    final countBefore = before.length;

    await repo.deleteNoteOption(created.id);

    final after = repo.listAllNoteOptions(NoteOptionField.materialsUsed);
    expect(
      after.any((o) => o.id == created.id),
      isFalse,
      reason: 'Tras deleteNoteOption(), el concepto ya no debe aparecer en el listado.',
    );
    expect(
      after.length,
      countBefore - 1,
      reason: 'Borrar un concepto no debe afectar a los demas conceptos del mismo campo '
          '(p.ej. los precargados por DemoSeed: Solución salina 0.9%, Gasa estéril, etc.).',
    );
  });

  test(
      'deleteNoteOption() de un concepto de un campo no afecta a los '
      'conceptos de otros campos', () async {
    final repo = await DataRepository.instance();

    final created = await repo.createNoteOption(
      field: NoteOptionField.careType,
      label: 'Tipo de atencion de prueba para borrar',
      organizationId: null,
    );

    final otherFieldBefore = repo.listAllNoteOptions(NoteOptionField.materialsUsed).length;

    await repo.deleteNoteOption(created.id);

    expect(
      repo.listAllNoteOptions(NoteOptionField.careType).any((o) => o.id == created.id),
      isFalse,
    );
    expect(
      repo.listAllNoteOptions(NoteOptionField.materialsUsed).length,
      otherFieldBefore,
      reason: 'Borrar un concepto de "Tipo de atención" no debe alterar el catálogo '
          'de "Material utilizado" ni de ningún otro campo.',
    );
  });

  test(
      'borrar un concepto del catalogo NO afecta las notas de seguimiento '
      'ya guardadas que usaron ese texto (no hay FK hacia '
      'note_option_catalog.id, solo se copia el label como texto plano)',
      () async {
    final repo = await DataRepository.instance();

    final sites = repo.listSites();
    final staff = repo.listStaff();
    final patients = repo.listAllPatients();
    expect(sites, isNotEmpty, reason: 'DemoSeed debe poblar al menos un sitio');
    expect(staff, isNotEmpty, reason: 'DemoSeed debe poblar al menos un miembro del personal');
    expect(patients, isNotEmpty, reason: 'DemoSeed debe poblar al menos un paciente');

    final created = await repo.createNoteOption(
      field: NoteOptionField.materialsUsed,
      label: 'Material efímero de prueba (se borrará del catálogo)',
      organizationId: null,
    );

    // La consulta guarda el LABEL como texto libre en
    // follow_up_materials_used, no el id del concepto del catalogo (asi
    // funciona hoy _NoteCatalogTab/wound_capture_screen: el chip
    // seleccionado aporta su .label, no su .id).
    final consultation = await repo.createConsultation(
      patientId: patients.first.id,
      staffId: staff.first.id,
      siteId: sites.first.id,
      visitType: VisitType.seguimiento,
      visitDate: DateTime.now(),
      isDraft: false,
      followUpMaterialsUsed: created.label,
    );

    // Se borra el concepto del catalogo (accion nueva de esta feature).
    await repo.deleteNoteOption(created.id);

    // El concepto ya no aparece como opcion futura...
    expect(
      repo.listAllNoteOptions(NoteOptionField.materialsUsed).any((o) => o.id == created.id),
      isFalse,
    );

    // ...pero la nota de seguimiento ya guardada conserva su texto intacto,
    // exactamente como antes de borrar el concepto del catalogo.
    final reloaded = repo
        .listConsultationsForPatient(patients.first.id)
        .firstWhere((c) => c.id == consultation.id);
    expect(reloaded.followUpMaterialsUsed, created.label,
        reason: 'El historial de la nota de seguimiento no depende de que '
            'la fila del catalogo siga existiendo: guarda el texto, no una '
            'referencia por id.');
  });
}
