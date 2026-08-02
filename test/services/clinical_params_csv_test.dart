// Verifica el CSV de parámetros clínicos: (1) que la descarga cubra todo con
// procedencia, y (2) el ROUND-TRIP descarga→carga: parsear el CSV reconstruye
// un JSON que valida y produce EXACTAMENTE los mismos parámetros (garantía de
// que subir lo que María editó no corrompe el motor). También cubre el diff.
import 'dart:convert';
import 'dart:io';

import 'package:csv/csv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kuratracker/engine/params/clinical_params.dart';
import 'package:kuratracker/services/clinical_params_csv.dart';

Map<String, dynamic> _asset(String name) => jsonDecode(
      File('assets/engine/clinical/$name').readAsStringSync(),
    ) as Map<String, dynamic>;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('el CSV cubre umbrales, bandas y mapeos con procedencia', () async {
    final csv = await ClinicalParamsCsv.build();
    expect(csv.filename, startsWith('parametros_clinicos_'));

    final rows = const CsvToListConverter(eol: '\r\n').convert(csv.content);
    expect(rows.first, ClinicalParamsCsv.headers);

    final body = rows.skip(1).toList();
    final secciones = body.map((r) => r[0] as String).toSet();
    expect(secciones, containsAll(<String>{
      'meta',
      'umbral',
      'banda_compresion',
      'wagner_descarga',
      'wuwhs_manejo',
      'compresion_producto',
    }));
  });

  group('round-trip descarga → carga', () {
    late String csvContent;
    setUp(() {
      final built = ClinicalParamsCsv.buildFromMaps(
        thresholds: _asset('thresholds.json'),
        archetypes: _asset('archetypes.json'),
      );
      csvContent = built.content;
    });

    test('parsear el CSV reconstruye parámetros que VALIDAN e igualan al asset',
        () {
      final parsed = ClinicalParamsCsv.parse(csvContent);

      // Valida (procedencia, bandas, orden, refs) — lanza si algo está mal.
      final rebuilt = ClinicalParams.fromJsonStrings(
        thresholdsJson: jsonEncode(parsed.thresholds),
        archetypesJson: jsonEncode(parsed.archetypes),
      );
      final original = ClinicalParams.fromJsonStrings(
        thresholdsJson: jsonEncode(_asset('thresholds.json')),
        archetypesJson: jsonEncode(_asset('archetypes.json')),
      );

      // Umbrales idénticos (valor y tipo).
      expect(rebuilt.thresholds, original.thresholds);
      // Bandas idénticas.
      expect(
        {for (final b in rebuilt.compressionBands) b.band.name: b.rangeLabel},
        {for (final b in original.compressionBands) b.band.name: b.rangeLabel},
      );
      // Mapeos idénticos.
      expect(rebuilt.wagnerDescarga, original.wagnerDescarga);
      expect(rebuilt.wuwhsManejo, original.wuwhsManejo);
      expect(rebuilt.compresionProducto, original.compresionProducto);
      // Sin cambios respecto al original.
      expect(original.diffTo(rebuilt), isEmpty);
    });

    test('una edición de valor se refleja en el diff y sigue validando', () {
      // María cambia el umbral de desbridamiento 15 -> 18 en el CSV.
      final edited = csvContent.replaceFirst(
        'debridement_composition_min_pct,,15,',
        'debridement_composition_min_pct,,18,',
      );
      expect(edited, isNot(equals(csvContent)), reason: 'la edición debió aplicar');

      final parsed = ClinicalParamsCsv.parse(edited);
      final rebuilt = ClinicalParams.fromJsonStrings(
        thresholdsJson: jsonEncode(parsed.thresholds),
        archetypesJson: jsonEncode(parsed.archetypes),
      );
      expect(rebuilt.debridementCompositionMinPct, 18);

      final original = ClinicalParams.fromJsonStrings(
        thresholdsJson: jsonEncode(_asset('thresholds.json')),
        archetypesJson: jsonEncode(_asset('archetypes.json')),
      );
      final diff = original.diffTo(rebuilt);
      expect(diff.length, 1);
      expect(diff.single, contains('debridement_composition_min_pct'));
      expect(diff.single, contains('15 → 18'));
    });

    test('un CSV con banda rota es RECHAZADO al validar', () {
      // Rompe la contigüidad: reducida termina en 0.75 (hueco 0.75-0.8).
      final broken = csvContent.replaceFirst('[0.6, 0.8)', '[0.6, 0.75)');
      expect(broken, isNot(equals(csvContent)));
      final parsed = ClinicalParamsCsv.parse(broken);
      expect(
        () => ClinicalParams.fromJsonStrings(
          thresholdsJson: jsonEncode(parsed.thresholds),
          archetypesJson: jsonEncode(parsed.archetypes),
        ),
        throwsA(isA<ClinicalParamsException>()),
      );
    });
  });
}
