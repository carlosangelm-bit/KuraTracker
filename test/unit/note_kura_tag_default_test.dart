// GUARDA (Carlos, 19-sep): el tramo protocolo→nota. note_option_catalog.kura_tag estaba en NULL en
// cada centro (0013 agregó la columna, nadie la rellenó), así que "Aceptar y aplicar a la nota"
// (Fase 3) no pre-marcaba nada y el aviso pedía etiquetas que nadie podía poner. El arreglo:
//  1. un mapeo por defecto (kDefaultNoteOptionKuraTags) que rellena los conceptos precargados;
//  2. la migración 0151 lo aplica a los centros EXISTENTES (catálogo global) sin pisar lo ajustado;
//  3. la pantalla que asigna etiquetas se abre con el asiento que enciende el protocolo, no con el
//     módulo de administración.
// Estas pruebas MIRAN EL RESULTADO EN LA NOTA (qué conceptos se pre-marcan), no que la pantalla abra.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kuratracker/models/note_option_catalog.dart';
import 'package:kuratracker/services/data_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('un régimen con métodos etiquetados pre-marca conceptos en la nota (escribe algo)', () async {
    final repo = await DataRepository.instance();
    // Métodos que el motor emite en una curación típica → sus KuraTags (misma lógica que
    // _applyRegimenToNote: método → kKuraMethodToTag → filtra los conceptos con ese tag).
    final metodos = ['Limpieza de la herida', 'Apósito', 'Terapia compresiva'];
    final tags = metodos.map((m) => kKuraMethodToTag[m]).whereType<KuraTag>().toSet();
    expect(tags, isNotEmpty, reason: 'estos métodos deben mapear a tags');

    List<String> preselect(NoteOptionField field) => repo
        .listNoteOptions(field)
        .where((o) => o.kuraTag != null && tags.contains(o.kuraTag))
        .map((o) => o.label)
        .toList();
    final proc = preselect(NoteOptionField.procedureDesc);
    final mat = preselect(NoteOptionField.materialsUsed);

    // Lo que de verdad se escribe en la nota: al menos un concepto pre-marcado.
    expect([...proc, ...mat], isNotEmpty,
        reason: '"Aceptar y aplicar a la nota" debe pre-marcar ≥1 concepto (si no, kura_tag sigue NULL)');
    // Resultado concreto: la limpieza y el apósito llegan a la nota.
    expect(proc, contains('Limpieza con solución salina y cambio de apósito'));
    expect(mat, contains('Apósito de espuma (foam)'));
  });

  test('el mapeo por defecto vive en UNA fuente: migración 0151 y seed demo coinciden con la lista',
      () {
    final mig = File(
            'supabase/migrations/0151_note_option_catalog_default_kura_tag.sql')
        .readAsStringSync();
    final demo =
        File('lib/services/local_db/demo_seed.dart').readAsStringSync();
    // Statements de la migración (separados por ';'), para verificar cada relleno completo.
    final stmts = mig.split(';');
    expect(kDefaultNoteOptionKuraTags, isNotEmpty);
    for (final (field, label, tag) in kDefaultNoteOptionKuraTags) {
      // La migración rellena (campo,label) con ese tag SOLO donde está NULL (no pisa lo ajustado).
      final hasStmt = stmts.any((s) =>
          s.contains("kura_tag = '$tag'") &&
          s.contains("field = '$field'") &&
          s.contains("label = '$label'") &&
          s.contains('kura_tag is null'));
      expect(hasStmt, isTrue,
          reason: 'la migración 0151 debe rellenar $field/"$label" → $tag donde kura_tag is null');
      // El seed de la demo trae el mismo concepto con el mismo tag (no divergen).
      expect(demo.contains("'$label', '$tag'"), isTrue,
          reason: 'el seed de la demo debe etiquetar "$label" → $tag igual que la migración');
    }
  });

  test('la pantalla de etiquetas se abre con el asiento del protocolo, no solo con module:admin',
      () {
    final src =
        File('lib/features/admin/protocol_kura_screen.dart').readAsStringSync();
    // El add-on que enciende el protocolo (seat:protocolo) desbloquea la configuración de etiquetas.
    expect(src.contains('premiumProtocoloKuraFor'), isTrue,
        reason: 'etiquetar la nota va con el asiento que enciende el protocolo (seat:protocolo)');
  });
}
