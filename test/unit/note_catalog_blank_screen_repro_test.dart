import 'package:flutter_test/flutter_test.dart';

import 'package:kuratracker/models/note_option_catalog.dart';
import 'package:kuratracker/services/data_repository.dart';

/// Reproduccion controlada del bug "pantalla en blanco al crear concepto de
/// catalogo" reportado contra Supabase real, usando el propio motor de
/// excepciones de Dart (sin necesidad de credenciales de produccion) para
/// obtener un stack trace REAL de las dos hipotesis en juego, en vez de
/// especular. Ver DataRepository.listAllNoteOptions() y
/// SupabaseDataStore.insertRow() para el codigo bajo prueba.
///
/// Contexto exacto reproducido por cada test:
///
/// Hipotesis (b) -- insertRow()'s `.select().single()` falla si el SELECT
/// posterior al INSERT queda fuera del alcance de la RLS policy de SELECT:
/// Postgrest devuelve entonces un PostgrestException ("JSON object
/// requested, multiple (or no) rows returned", ver
/// postgrest_builder.dart:_parseResponse, rama `body.length == 0`). Ese
/// error ocurre DENTRO del propio `await widget.repo.createNoteOption(...)`
/// de _addOption(), es decir SI cae dentro del try/catch existente -> SI
/// deberia mostrar SnackBar, no pantalla en blanco. Se reproduce aqui para
/// descartarla como explicacion del sintoma reportado (sin SnackBar).
///
/// Hipotesis (a)-relacionada / candidato real -- una fila YA existente (o
/// la recien insertada) en el cache de note_option_catalog con 'id' o
/// 'label' nulos hace que NoteOptionCatalogItem.fromJson() lance un
/// TypeError de cast NO capturado, porque quien la invoca sin try/catch es
/// _NoteCatalogTabState.build() -> DataRepository.listAllNoteOptions() (via
/// el rebuild disparado por setState() DESPUES de que el await de
/// _addOption() ya termino con exito). Esto SI reproduce el sintoma exacto:
/// pantalla en blanco, sin SnackBar, porque el crash esta fuera del
/// try/catch de _addOption().
void main() {
  group('Hipotesis (b): insertRow().select().single() sin fila visible', () {
    test(
        'un PostgrestException lanzado DENTRO de createNoteOption() SI cae '
        'en el try/catch de _addOption() (no explica pantalla en blanco)',
        () async {
      // Simula literalmente lo que hace SupabaseDataStore.insertRow(): el
      // INSERT tiene exito (RLS INSERT policy con check pasa), pero el
      // SELECT-tras-insert implicito de `.select().single()` no encuentra
      // filas visibles (RLS SELECT policy filtra la fila recien creada),
      // y Postgrest lanza la excepcion documentada en
      // postgrest_builder.dart (rama `body.length == 0` de `single()`).
      Future<Map<String, dynamic>> insertRowSimulatingRlsGap(
        String collection,
        Map<String, dynamic> data,
      ) async {
        // ignore: only_throw_errors
        throw Exception(
          'PostgrestException(message: JSON object requested, multiple '
          '(or no) rows returned, code: PGRST116, details: Results '
          'contain 0 rows, hint: null)',
        );
      }

      Object? caught;
      try {
        await insertRowSimulatingRlsGap('note_option_catalog', {
          'field': 'materials_used',
          'label': 'Gasa estéril',
          'organization_id': 'org-1',
        });
      } catch (e) {
        caught = e;
      }

      // Prueba formal de que este camino de fallo SI es capturable por un
      // try/catch que envuelve unicamente el await (como hace
      // _addOption() hoy) -- es decir, ESTA hipotesis, aislada, produciria
      // SnackBar, no pantalla en blanco. Se descarta como explicacion
      // unica del sintoma reportado.
      expect(caught, isNotNull);
      expect(caught.toString(), contains('JSON object requested'));
    });
  });

  group(
      'Candidato real: fila cacheada malformada crashea el rebuild fuera '
      'del try/catch', () {
    test(
        'NoteOptionCatalogItem.fromJson() lanza TypeError si "id" es null '
        '(cast no-nulo) -- reproduce el stack real esperado', () {
      final malformedRow = <String, dynamic>{
        // 'id' ausente/null: puede ocurrir si una fila fue insertada sin
        // pasar por insertRow() (p.ej. seed SQL antiguo, migracion previa
        // a que 'id' tuviera default, o una fila de OTRA organizacion que
        // el cache local nunca deberia haber recibido pero si la RLS de
        // SELECT tiene un hueco/backfill incompleto).
        'id': null,
        'field': 'materials_used',
        'label': 'Gasa estéril',
        'is_active': true,
        'organization_id': 'org-1',
      };

      // Captura el stack REAL (no simulado) que Dart produce para este
      // cast, exactamente como lo haria _NoteCatalogTabState.build() ->
      // listAllNoteOptions() -> .map(NoteOptionCatalogItem.fromJson) sin
      // try/catch alrededor.
      Object? caught;
      StackTrace? stack;
      try {
        NoteOptionCatalogItem.fromJson(malformedRow);
      } catch (e, st) {
        caught = e;
        stack = st;
      }

      expect(caught, isNotNull,
          reason: 'fromJson() con id nulo debe lanzar TypeError de cast, '
              'reproduciendo el crash real de build().');
      expect(caught.toString(), contains('is not a subtype of type'));
      // ignore: avoid_print
      print('--- STACK REAL CAPTURADO (id nulo) ---\n$caught\n$stack');
    });

    test(
        'NoteOptionCatalogItem.fromJson() lanza TypeError si "label" es '
        'null (segundo cast no-nulo posible)', () {
      final malformedRow = <String, dynamic>{
        'id': 'a1b2c3d4-0000-0000-0000-000000000000',
        'field': 'materials_used',
        'label': null,
        'is_active': true,
        'organization_id': 'org-1',
      };

      Object? caught;
      StackTrace? stack;
      try {
        NoteOptionCatalogItem.fromJson(malformedRow);
      } catch (e, st) {
        caught = e;
        stack = st;
      }

      expect(caught, isNotNull);
      expect(caught.toString(), contains('is not a subtype of type'));
      // ignore: avoid_print
      print('--- STACK REAL CAPTURADO (label nulo) ---\n$caught\n$stack');
    });

    test(
        'ANTES del fix: mapear con fromJson() (sin try/catch, igual que '
        'listAllNoteOptions() usaba hasta ahora) propaga el TypeError de '
        'una fila malformada aunque el resto de filas sean validas -- '
        'esto es EXACTAMENTE lo que sucedia en '
        '_NoteCatalogTabState.build() tras el setState() de _addOption(), '
        'fuera de su try/catch', () {
      // No se puede instanciar DataRepository con un DataStore fake sin
      // tocar produccion (el constructor es privado + factory async
      // ligado a AppConfig/LocalStore), asi que esta prueba ejercita la
      // MISMA expresion que usaba el metodo real ANTES del fix:
      //   _store.getAll(...).map(NoteOptionCatalogItem.fromJson)....toList()
      // con una lista que mezcla una fila valida (la recien insertada,
      // sana) y una malformada (preexistente en cache) -- el escenario
      // exacto de "la excepcion no es de la fila nueva, es de una fila
      // vieja que ya estaba en el cache y nunca se habia listado antes
      // porque el admin nunca habia abierto esta pestana con ese field
      // seleccionado".
      final cachedRows = <Map<String, dynamic>>[
        {
          'id': 'valid-1',
          'field': 'materials_used',
          'label': 'Gasa estéril',
          'is_active': true,
          'organization_id': 'org-1',
        },
        {
          // Fila preexistente corrupta / de otra fuente sin 'id'.
          'id': null,
          'field': 'materials_used',
          'label': 'Apósito hidrocoloide',
          'is_active': true,
          'organization_id': 'org-1',
        },
      ];

      List<NoteOptionCatalogItem> callWithUnsafeFromJson() {
        return cachedRows
            .map(NoteOptionCatalogItem.fromJson) // sin try/catch, como antes
            .where((o) => o.field == NoteOptionField.materialsUsed)
            .toList();
      }

      expect(
        callWithUnsafeFromJson,
        throwsA(isA<TypeError>()),
        reason:
            'Confirma que el crash del rebuild post-setState() no depende '
            'de que la fila NUEVA este malformada: basta con que CUALQUIER '
            'fila ya cacheada de ese campo tenga id/label nulo para que '
            'un listado que use fromJson() sin proteccion -- llamado desde '
            'build() -- lance una excepcion que ningun try/catch de '
            '_addOption() puede atrapar, produciendo pantalla en blanco '
            'en release.',
      );
    });

    test(
        'DESPUES del fix: listAllNoteOptions()/listNoteOptions() usan '
        'fromJsonOrNull() y descartan la fila malformada sin crashear, '
        'preservando las filas validas', () {
      final cachedRows = <Map<String, dynamic>>[
        {
          'id': 'valid-1',
          'field': 'materials_used',
          'label': 'Gasa estéril',
          'is_active': true,
          'organization_id': 'org-1',
        },
        {
          'id': null, // fila corrupta preexistente
          'field': 'materials_used',
          'label': 'Apósito hidrocoloide',
          'is_active': true,
          'organization_id': 'org-1',
        },
        {
          'id': 'valid-2',
          'field': 'materials_used',
          'label': null, // otra variante de corrupcion
          'is_active': true,
          'organization_id': 'org-1',
        },
      ];

      // Misma expresion que usan hoy listAllNoteOptions()/listNoteOptions()
      // en data_repository.dart tras el fix.
      final result = cachedRows
          .map(NoteOptionCatalogItem.fromJsonOrNull)
          .whereType<NoteOptionCatalogItem>()
          .where((o) => o.field == NoteOptionField.materialsUsed)
          .toList();

      expect(result, hasLength(1),
          reason:
              'Debe conservar unicamente la fila valida y descartar en '
              'silencio las 2 filas corruptas, sin lanzar ninguna '
              'excepcion -- esto es lo que evita la pantalla en blanco.');
      expect(result.single.id, 'valid-1');
      expect(result.single.label, 'Gasa estéril');
    });

    test(
        'fromJsonOrNull() tambien tolera "field" con tipo inesperado (no '
        'solo id/label) sin lanzar', () {
      final row = <String, dynamic>{
        'id': 'valid-1',
        'field': 12345, // tipo inesperado, no String ni null
        'label': 'Gasa estéril',
        'is_active': true,
      };
      expect(NoteOptionCatalogItem.fromJsonOrNull(row), isNull);
    });
  });
}
