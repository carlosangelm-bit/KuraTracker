import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:kuratracker/engine/models/kura_engine_enums.dart';
import 'package:kuratracker/engine/models/kura_engine_input.dart';
import 'package:kuratracker/engine/rules/kura_treatment_rules_engine.dart';
import 'package:kuratracker/models/consultation.dart';
import 'package:kuratracker/models/note_option_catalog.dart';
import 'package:kuratracker/models/center_type.dart';
import 'package:kuratracker/services/data_repository.dart';

import '../engine/clinical_params_fixture.dart';

/// Cobertura de rama feat/followup-protocol-suggest:
///   Parte A (multi-seleccion): no hay UI aqui (ver widget_test.dart para
///   eso si se agrega), pero se cubre el modelo/serializacion de kura_tag
///   (Parte B/C) y la tabla de mapeo metodo->tag (Parte D), que es la
///   pieza no trivial y testeable sin necesidad de montar la pantalla.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(loadClinicalParamsForTest);

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('KuraTag (Parte B/C: etiqueta de mapeo del catalogo)', () {
    test('dbValue/fromDb hacen roundtrip para todos los valores del enum', () {
      for (final tag in KuraTag.values) {
        expect(KuraTagDb.fromDb(tag.dbValue), tag);
      }
    });

    test('fromDb(null/vacio/desconocido) devuelve null sin lanzar (nunca rompe)', () {
      expect(KuraTagDb.fromDb(null), isNull);
      expect(KuraTagDb.fromDb(''), isNull);
      expect(KuraTagDb.fromDb('etiqueta_vieja_renombrada'), isNull);
    });

    test('NoteOptionCatalogItem.fromJson/toJson conservan kuraTag', () {
      final json = {
        'id': 'abc',
        'field': 'materials_used',
        'label': 'Apósito de espuma (foam)',
        'is_active': true,
        'organization_id': 'org-1',
        'kura_tag': 'aposito',
      };
      final item = NoteOptionCatalogItem.fromJson(json);
      expect(item.kuraTag, KuraTag.aposito);
      expect(item.toJson()['kura_tag'], 'aposito');
    });

    test('NoteOptionCatalogItem.fromJsonOrNull tolera kura_tag de tipo '
        'inesperado sin lanzar (descarta la fila, no tumba el listado)', () {
      final malformed = {
        'id': 'abc',
        'field': 'materials_used',
        'label': 'Gasa estéril',
        'kura_tag': 12345, // tipo inesperado, no String ni null
      };
      expect(NoteOptionCatalogItem.fromJsonOrNull(malformed), isNull);
    });

    test('un concepto sin kura_tag (columna NULL) deserializa con '
        'kuraTag == null ("Sin etiqueta")', () {
      final json = {
        'id': 'abc',
        'field': 'evolution',
        'label': 'Estable, sin cambios significativos',
        'is_active': true,
      };
      expect(NoteOptionCatalogItem.fromJson(json).kuraTag, isNull);
    });
  });

  group('DataRepository.defaultNoteOptionCatalog (Parte C: sembrado por defecto)', () {
    test('los conceptos ancla mencionados en la tarea llevan la etiqueta esperada', () {
      Map<String, KuraTag?> byLabel(NoteOptionField field) => {
            for (final e in DataRepository.defaultNoteOptionCatalog.where((e) => e.$1 == field))
              e.$2: e.$3,
          };

      final procedure = byLabel(NoteOptionField.procedureDesc);
      final materials = byLabel(NoteOptionField.materialsUsed);

      expect(procedure['Limpieza con solución salina y cambio de apósito'], KuraTag.limpieza);
      expect(procedure['Desbridamiento cortante parcial'], KuraTag.desbridamiento);
      expect(procedure['Aplicación de terapia compresiva'], KuraTag.compresion);
      expect(procedure['Educación al paciente/cuidador'], KuraTag.educacion);
      expect(materials['Apósito de espuma (foam)'], KuraTag.aposito);
      expect(materials['Apósito hidrocoloide'], KuraTag.aposito);
      expect(materials['Vendaje de compresión'], KuraTag.compresion);
      expect(materials['Yodopovidona 10%'], KuraTag.antimicrobiano);

      // Conceptos ambiguos que la tarea implicitamente deja sin etiqueta.
      expect(procedure['Toma de medidas y fotografía de control'], isNull);
      for (final e in DataRepository.defaultNoteOptionCatalog.where((e) => e.$1 == NoteOptionField.evolution)) {
        expect(e.$3, isNull, reason: '"Evolución" no tiene mapeo directo a un metodo del motor.');
      }
    });

    test('seedDefaultNoteOptions() persiste el kura_tag de cada concepto '
        'sembrado (roundtrip completo Parte B->C)', () async {
      final repo = await DataRepository.instance();
      final org = await repo.createOrganization('Centro Prueba KuraTag', CenterType.clinicaHeridas);

      await repo.seedDefaultNoteOptions(organizationId: org.id);

      final materials = repo.listAllNoteOptions(NoteOptionField.materialsUsed, organizationId: org.id);
      final foam = materials.firstWhere((o) => o.label == 'Apósito de espuma (foam)');
      expect(foam.kuraTag, KuraTag.aposito);

      final procedure = repo.listAllNoteOptions(NoteOptionField.procedureDesc, organizationId: org.id);
      final cleaning = procedure.firstWhere((o) => o.label == 'Limpieza con solución salina y cambio de apósito');
      expect(cleaning.kuraTag, KuraTag.limpieza);
      final photoOnly = procedure.firstWhere((o) => o.label == 'Toma de medidas y fotografía de control');
      expect(photoOnly.kuraTag, isNull);
    });

    test('setNoteOptionKuraTag() actualiza la etiqueta de un concepto ya '
        'existente (Parte C, dropdown de administracion)', () async {
      final repo = await DataRepository.instance();
      final created = await repo.createNoteOption(
        field: NoteOptionField.materialsUsed,
        label: 'Concepto de prueba sin etiqueta',
        organizationId: null,
      );
      expect(created.kuraTag, isNull);

      await repo.setNoteOptionKuraTag(created.id, KuraTag.antimicrobiano);
      final reloaded = repo
          .listAllNoteOptions(NoteOptionField.materialsUsed)
          .firstWhere((o) => o.id == created.id);
      expect(reloaded.kuraTag, KuraTag.antimicrobiano);

      // Revertir a "Sin etiqueta" (null) tambien debe persistir.
      await repo.setNoteOptionKuraTag(created.id, null);
      final reloadedAgain = repo
          .listAllNoteOptions(NoteOptionField.materialsUsed)
          .firstWhere((o) => o.id == created.id);
      expect(reloadedAgain.kuraTag, isNull);
    });
  });

  group('kKuraMethodToTag (Parte D: lookup metodo del regimen -> KuraTag)', () {
    test('cubre exactamente los 16 metodos que emite KuraTreatmentRulesEngine '
        '(kura_rules_v2), sin dejar ninguno fuera del mapa', () {
      const metodosConocidos = <String>{
        'Limpieza de la herida',
        'Desbridamiento',
        'Relleno de cavidad',
        'Apósito',
        'Protección de la piel',
        'Tratamiento para la infección',
        'Educación al paciente/cuidador',
        'Dispositivo de descarga',
        'Manejo neuropático',
        'Terapia compresiva',
        'Manejo de herida quirúrgica',
        'Manejo de herida por mordedura',
        'Manejo de herida por arma de fuego',
        'Manejo de herida por aplastamiento',
        'Manejo de herida punzocortante',
        'Manejo de herida traumática',
      };
      expect(kKuraMethodToTag.keys.toSet(), metodosConocidos);
    });

    test('metodos de manejo especializado por tipo de herida (sin '
        'equivalente 1:1 en el catalogo) mapean a null: nunca se '
        'auto-seleccionan', () {
      const sinEquivalente = [
        'Manejo neuropático',
        'Manejo de herida quirúrgica',
        'Manejo de herida por mordedura',
        'Manejo de herida por arma de fuego',
        'Manejo de herida por aplastamiento',
        'Manejo de herida punzocortante',
        'Manejo de herida traumática',
      ];
      for (final m in sinEquivalente) {
        expect(kKuraMethodToTag[m], isNull, reason: '"$m" no debe tener KuraTag.');
      }
    });

    test('metodos con concepto de catalogo equivalente mapean al KuraTag '
        'correcto', () {
      expect(kKuraMethodToTag['Limpieza de la herida'], KuraTag.limpieza);
      expect(kKuraMethodToTag['Desbridamiento'], KuraTag.desbridamiento);
      expect(kKuraMethodToTag['Relleno de cavidad'], KuraTag.rellenoCavidad);
      expect(kKuraMethodToTag['Apósito'], KuraTag.aposito);
      expect(kKuraMethodToTag['Protección de la piel'], KuraTag.proteccionPiel);
      expect(kKuraMethodToTag['Tratamiento para la infección'], KuraTag.antimicrobiano);
      expect(kKuraMethodToTag['Educación al paciente/cuidador'], KuraTag.educacion);
      expect(kKuraMethodToTag['Dispositivo de descarga'], KuraTag.descarga);
      expect(kKuraMethodToTag['Terapia compresiva'], KuraTag.compresion);
    });

    test('todo metodo real emitido por KuraTreatmentRulesEngine.generate() '
        'para un caso base esta cubierto por el mapa (no lanza KeyError '
        'ni deja huecos silenciosos)', () {
      final input = KuraEngineInput(
        etiologia: Etiologia.pieDiabetico,
        entorno: Entorno.clinica,
        areaCm2: 6.25,
        depthCm: 0.3,
        necrosisPct: 10,
        esfaceloPct: 20,
        granulacionPct: 60,
        epitelizacionPct: 10,
        comorbilidades: const {Comorbilidad.diabetesMellitus: ComorbilidadEstado.presente},
      );
      final result = KuraTreatmentRulesEngine.generate(input: input, scenario: KuraScenario.b);
      for (final r in result.regimen) {
        expect(kKuraMethodToTag.containsKey(r.metodo), isTrue,
            reason: 'Metodo real "${r.metodo}" emitido por el motor no esta en kKuraMethodToTag.');
      }
    });
  });

  group('Parte A: concatenacion multi-seleccion al guardar (regresion de '
      'columnas de texto existentes, sin migracion)', () {
    test('createConsultation persiste follow_up_procedure_desc/'
        'follow_up_materials_used como texto concatenado con "; ", igual '
        'que produciria _joinMultiSelect() con >1 concepto marcado', () async {
      final repo = await DataRepository.instance();
      final sites = repo.listSites();
      final staff = repo.listStaff();
      final patients = repo.listAllPatients();

      final consultation = await repo.createConsultation(
        patientId: patients.first.id,
        staffId: staff.first.id,
        siteId: sites.first.id,
        visitType: VisitType.seguimiento,
        visitDate: DateTime.now(),
        isDraft: false,
        followUpProcedureDesc: 'Limpieza con solución salina y cambio de apósito; '
            'Desbridamiento cortante parcial',
        followUpMaterialsUsed: 'Apósito de espuma (foam); Yodopovidona 10%',
      );

      final reloaded = repo
          .listConsultationsForPatient(patients.first.id)
          .firstWhere((c) => c.id == consultation.id);
      expect(
        reloaded.followUpProcedureDesc,
        'Limpieza con solución salina y cambio de apósito; Desbridamiento cortante parcial',
      );
      expect(reloaded.followUpMaterialsUsed, 'Apósito de espuma (foam); Yodopovidona 10%');
    });
  });
}
