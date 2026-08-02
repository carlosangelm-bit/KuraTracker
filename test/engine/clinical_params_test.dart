// Validación de esquema y consistencia de los parámetros clínicos
// (assets/engine/clinical/*.json), Fase A del refactor data-driven.
//
// Garantiza que:
//  - los JSON reales cargan y validan (estructura, tipos, procedencia);
//  - cada umbral/mapa/banda trae source completo (protocolo/rationale/
//    reviewed_by/reviewed_date) — sin procedencia => falla;
//  - las bandas de compresión son contiguas (sin huecos ni traslapes) y
//    cubren todo el rango de ITB;
//  - los cortes ABI/albúmina están ordenados;
//  - no hay refs colgantes (todo grado Wagner/WUWHS y banda con producto existe);
//  - un JSON malformado o sin source es RECHAZADO.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kuratracker/engine/models/kura_engine_enums.dart';
import 'package:kuratracker/engine/params/clinical_params.dart';

String _readAsset(String name) =>
    File('assets/engine/clinical/$name').readAsStringSync();

void main() {
  late String thresholds;
  late String archetypes;

  setUpAll(() {
    thresholds = _readAsset('thresholds.json');
    archetypes = _readAsset('archetypes.json');
  });

  group('Carga y esquema de los assets reales', () {
    test('los JSON reales cargan y validan', () {
      final p = ClinicalParams.fromJsonStrings(
        thresholdsJson: thresholds,
        archetypesJson: archetypes,
      );
      expect(p.version, isNotEmpty);
      // Umbrales esperados presentes con el valor de la conducta vigente.
      expect(p.debridementCompositionMinPct, 15);
      expect(p.necrosisExtensaMinPct, 30);
      expect(p.depthRellenoMinCm, 0.5);
      expect(p.infeccionLocalMinFactores, 2);
      expect(p.tunelReferenciaMinCm, 7.0);
      expect(p.bradenACargoClinicaMax, 17);
      expect(p.bradenAltoMuyAltoMax, 12);
      expect(p.abiIncompresibleAbove, 1.4);
      expect(p.abiHighMin, 0.80);
      expect(p.abiModMin, 0.50);
      expect(p.albuminaNormalMin, 3.5);
      expect(p.albuminaMildMin, 3.0);
    });

    test('las bandas de compresión reproducen los cortes ITB del protocolo', () {
      final p = ClinicalParams.fromJsonStrings(
        thresholdsJson: thresholds,
        archetypesJson: archetypes,
      );
      expect(p.itbBandFor(1.5), ItbCompresionBand.incompresible);
      expect(p.itbBandFor(1.4), ItbCompresionBand.fuerte);
      expect(p.itbBandFor(0.95), ItbCompresionBand.fuerte);
      expect(p.itbBandFor(0.9), ItbCompresionBand.fuerte);
      expect(p.itbBandFor(0.85), ItbCompresionBand.precaucion);
      expect(p.itbBandFor(0.8), ItbCompresionBand.precaucion);
      expect(p.itbBandFor(0.7), ItbCompresionBand.reducida);
      expect(p.itbBandFor(0.6), ItbCompresionBand.reducida);
      expect(p.itbBandFor(0.5), ItbCompresionBand.noAplica);
      expect(p.itbBandFor(0.0), ItbCompresionBand.noAplica);
    });

    test('los mapeos cubren todos los grados y bandas (sin refs colgantes)', () {
      final p = ClinicalParams.fromJsonStrings(
        thresholdsJson: thresholds,
        archetypesJson: archetypes,
      );
      for (final g in WagnerGrade.values) {
        expect(p.descargaFor(g), isNotEmpty);
      }
      for (final g in WuwhsGrade.values) {
        expect(p.manejoFor(g), isNotEmpty);
      }
      for (final b in [
        ItbCompresionBand.fuerte,
        ItbCompresionBand.precaucion,
        ItbCompresionBand.reducida,
        ItbCompresionBand.na,
      ]) {
        expect(p.compresionProductoFor(b), isNotEmpty);
      }
    });

    test('toda entrada de umbral trae procedencia (source) completa', () {
      // Recorre el JSON crudo y exige source con los 4 campos por umbral.
      final t = _decodeMap(thresholds);
      final ths = t['thresholds'] as Map<String, dynamic>;
      for (final entry in ths.entries) {
        final src = (entry.value as Map)['source'];
        expect(src, isA<Map>(), reason: '${entry.key} sin source');
        for (final f in ['protocolo', 'rationale', 'reviewed_by', 'reviewed_date']) {
          expect((src as Map)[f], isA<String>(),
              reason: '${entry.key}.source.$f faltante');
          expect((src[f] as String).trim(), isNotEmpty,
              reason: '${entry.key}.source.$f vacío');
        }
      }
    });
  });

  group('Consistencia / rechazo de datos inválidos', () {
    test('rechaza un umbral sin source (procedencia)', () {
      final broken = thresholds.replaceFirst(
        RegExp(r'"source":\s*\{[^}]*\}', dotAll: true),
        '"source": null',
      );
      expect(
        () => ClinicalParams.fromJsonStrings(
          thresholdsJson: broken,
          archetypesJson: archetypes,
        ),
        throwsA(isA<ClinicalParamsException>()),
      );
    });

    test('rechaza JSON malformado', () {
      expect(
        () => ClinicalParams.fromJsonStrings(
          thresholdsJson: '{ not json',
          archetypesJson: archetypes,
        ),
        throwsA(anything),
      );
    });

    test('rechaza bandas de compresión con hueco', () {
      // Rompe la contigüidad: reducida sube su "to" a 0.75 (deja hueco 0.75-0.8).
      final broken = thresholds.replaceFirst(
        '{ "band": "reducida", "from": 0.6, "from_inclusive": true, "to": 0.8, "to_inclusive": false }',
        '{ "band": "reducida", "from": 0.6, "from_inclusive": true, "to": 0.75, "to_inclusive": false }',
      );
      expect(broken == thresholds, isFalse, reason: 'la mutación debió aplicar');
      expect(
        () => ClinicalParams.fromJsonStrings(
          thresholdsJson: broken,
          archetypesJson: archetypes,
        ),
        throwsA(isA<ClinicalParamsException>()),
      );
    });

    test('rechaza cortes ABI fuera de orden', () {
      // abi_high_min (0.80) por encima de abi_incompresible_above (1.4): invierte.
      final broken = thresholds.replaceFirst(
        '"abi_incompresible_above": {\n      "value": 1.4,',
        '"abi_incompresible_above": {\n      "value": 0.4,',
      );
      expect(broken == thresholds, isFalse, reason: 'la mutación debió aplicar');
      expect(
        () => ClinicalParams.fromJsonStrings(
          thresholdsJson: broken,
          archetypesJson: archetypes,
        ),
        throwsA(isA<ClinicalParamsException>()),
      );
    });

    test('rechaza un mapa Wagner con ref colgante (falta un grado)', () {
      final broken = archetypes.replaceFirst(
        RegExp(r'"g5":\s*"[^"]*"'),
        '"gX": "placeholder"',
      );
      expect(broken == archetypes, isFalse, reason: 'la mutación debió aplicar');
      expect(
        () => ClinicalParams.fromJsonStrings(
          thresholdsJson: thresholds,
          archetypesJson: broken,
        ),
        throwsA(isA<ClinicalParamsException>()),
      );
    });
  });
}

Map<String, dynamic> _decodeMap(String s) =>
    jsonDecode(s) as Map<String, dynamic>;
