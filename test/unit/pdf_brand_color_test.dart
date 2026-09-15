// Color de marca de los PDF del paciente (reporte de herida, referencia, reporte de
// prevención). Antes cada generador tenía su propio literal de respaldo: violeta en dos,
// azul en el otro. Ahora los tres salen de brandPdfColor(), que cae en el brandPrimary
// del PROPIO tipo de centro. Verificado rojo antes (con los literales, un hospital daba
// violeta).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:kuratracker/models/center_type.dart';
import 'package:kuratracker/services/pdf_brand_color.dart';

const _violeta = 0xFF7C3AED; // clínica de heridas
const _azul = 0xFF2563EB; // hospital
const _rosa = 0xFFDB2777; // cuidadores

// Los tres generadores de PDF al paciente. Ninguno debe llevar un literal de color de
// marca: todos pasan por brandPdfColor(org?.brandPrimaryColor, org?.centerType).
const _pdfGenerators = <String>[
  'lib/features/reports/reports_screen.dart',
  'lib/services/referral_pdf.dart',
  'lib/services/prevention_report_pdf.dart',
];

void main() {
  group('brandPdfColor: sin color guardado cae en la marca del PROPIO centro', () {
    test('hospital → azul', () {
      expect(brandPdfColor(null, CenterType.hospital).toInt(), _azul);
      expect(brandPdfColor('', CenterType.hospital).toInt(), _azul);
    });
    test('cuidadores → rosa', () {
      expect(brandPdfColor(null, CenterType.cuidadores).toInt(), _rosa);
    });
    test('clínica de heridas → violeta', () {
      expect(brandPdfColor(null, CenterType.clinicaHeridas).toInt(), _violeta);
    });
  });

  test('un color guardado legible se respeta', () {
    expect(brandPdfColor('#123456', CenterType.hospital).toInt(), 0xFF123456);
    // Con almohadilla o sin ella, 6 u 8 dígitos.
    expect(brandPdfColor('123456', CenterType.cuidadores).toInt(), 0xFF123456);
    expect(brandPdfColor('#FF112233', CenterType.hospital).toInt(), 0xFF112233);
  });

  test('un color guardado ILEGIBLE cae en la marca del centro, no en violeta', () {
    // Hospital con basura guardada → azul del hospital, NO el violeta viejo.
    expect(brandPdfColor('no-es-color', CenterType.hospital).toInt(), _azul);
    expect(brandPdfColor('#12345', CenterType.hospital).toInt(), _azul); // largo inválido
    expect(brandPdfColor('#zzzzzz', CenterType.cuidadores).toInt(), _rosa);
    // Y en ningún caso el violeta fijo cuando el centro no es clínica.
    expect(brandPdfColor('basura', CenterType.hospital).toInt(),
        isNot(_violeta));
  });

  test('ningún generador de PDF contiene un literal de color de marca', () {
    final brandHexes = RegExp(r'0xFF(7C3AED|2563EB|DB2777)', caseSensitive: false);
    for (final path in _pdfGenerators) {
      final src = File(path).readAsStringSync();
      expect(brandHexes.hasMatch(src), isFalse,
          reason: '$path tiene un literal de color de marca; usa brandPdfColor().');
      expect(src.contains('brandPdfColor('), isTrue,
          reason: '$path debe resolver el color con brandPdfColor().');
    }
  });
}
