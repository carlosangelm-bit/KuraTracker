// Verifica el CSV de parámetros clínicos que descarga el master: que cubra
// todos los umbrales, bandas y mapeos, con procedencia y sin filas vacías.
import 'package:csv/csv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kuratracker/services/clinical_params_csv.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('el CSV cubre umbrales, bandas y mapeos con procedencia', () async {
    final csv = await ClinicalParamsCsv.build();

    expect(csv.filename, startsWith('parametros_clinicos_'));
    expect(csv.filename, endsWith('.csv'));

    final rows = const CsvToListConverter(eol: '\r\n').convert(csv.content);
    expect(rows.first, ClinicalParamsCsv.headers);

    final body = rows.skip(1).toList();
    final secciones = body.map((r) => r[0] as String).toSet();
    expect(secciones, containsAll(<String>{
      'umbral',
      'banda_compresion',
      'wagner_descarga',
      'wuwhs_manejo',
      'compresion_producto',
    }));

    // Cada umbral esperado aparece como fila.
    final umbrales = body
        .where((r) => r[0] == 'umbral')
        .map((r) => r[1] as String)
        .toSet();
    expect(umbrales, containsAll(<String>{
      'debridement_composition_min_pct',
      'necrosis_extensa_min_pct',
      'braden_a_cargo_clinica_max',
      'abi_incompresible_above',
      'albumina_normal_min',
      'tunel_referencia_min_cm',
    }));

    // Las 5 bandas de compresión.
    final bandas = body
        .where((r) => r[0] == 'banda_compresion')
        .map((r) => r[1] as String)
        .toSet();
    expect(bandas, {'noAplica', 'reducida', 'precaucion', 'fuerte', 'incompresible'});

    // Toda fila trae valor y procedencia (protocolo + revisor) no vacíos.
    for (final r in body) {
      expect(r[3].toString(), isNotEmpty, reason: 'valor vacío en ${r[1]}');
      expect((r[5] as String).trim(), isNotEmpty, reason: 'protocolo vacío en ${r[1]}');
      expect((r[7] as String).trim(), isNotEmpty, reason: 'revisor vacío en ${r[1]}');
    }
  });
}
