// Tests de la firma digital vectorial (SignatureController + SignatureData):
// estado vacío/no vacío y roundtrip de serialización JSON.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kuratracker/core/widgets/signature_model.dart';

void main() {
  group('SignatureController', () {
    test('vacío al inicio; un solo punto sigue contando como vacío', () {
      final c = SignatureController();
      expect(c.isEmpty, isTrue);
      c.setCanvasSize(const Size(200, 100));
      c.startStroke(const Offset(5, 5)); // 1 punto
      expect(c.isEmpty, isTrue, reason: 'un trazo de 1 punto no es firma');
      expect(c.toJsonString(), isNull);
    });

    test('un trazo con >=2 puntos ya no está vacío y serializa', () {
      final c = SignatureController();
      c.setCanvasSize(const Size(200, 100));
      c.startStroke(const Offset(0, 0));
      c.appendPoint(const Offset(10, 10));
      c.appendPoint(const Offset(20, 5));
      expect(c.isNotEmpty, isTrue);
      final json = c.toJsonString();
      expect(json, isNotNull);
    });

    test('clear vuelve a estado vacío', () {
      final c = SignatureController();
      c.setCanvasSize(const Size(200, 100));
      c.startStroke(const Offset(0, 0));
      c.appendPoint(const Offset(10, 10));
      expect(c.isNotEmpty, isTrue);
      c.clear();
      expect(c.isEmpty, isTrue);
    });
  });

  group('SignatureData roundtrip', () {
    test('parse conserva trazos y tamaño de captura', () {
      final c = SignatureController();
      c.setCanvasSize(const Size(300, 150));
      c.startStroke(const Offset(1, 2));
      c.appendPoint(const Offset(3, 4));
      c.appendPoint(const Offset(5, 6));
      final json = c.toJsonString();

      final data = SignatureData.tryParse(json);
      expect(data, isNotNull);
      expect(data!.size, const Size(300, 150));
      expect(data.strokes, hasLength(1));
      expect(data.strokes.first, [
        const Offset(1, 2),
        const Offset(3, 4),
        const Offset(5, 6),
      ]);
    });

    test('tryParse tolera null / vacío / json inválido', () {
      expect(SignatureData.tryParse(null), isNull);
      expect(SignatureData.tryParse(''), isNull);
      expect(SignatureData.tryParse('no-es-json'), isNull);
    });
  });
}
