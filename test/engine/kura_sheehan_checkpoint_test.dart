import 'package:flutter_test/flutter_test.dart';
import 'package:kuratracker/engine/kura_sheehan_checkpoint.dart';

void main() {
  group('Umbrales por semana (tabla oficial 8.5)', () {
    test('semana 2: cierre 30%, alerta 15%', () {
      final u = KuraSheehanCheckpoint.umbralesParaSemana(2);
      expect(u.cierre, 30);
      expect(u.alerta, 15);
    });
    test('semana 4 (regla validada): cierre 50%, alerta 30%', () {
      final u = KuraSheehanCheckpoint.umbralesParaSemana(4);
      expect(u.cierre, 50);
      expect(u.alerta, 30);
    });
    test('semana 6: cierre 65%, alerta 45%', () {
      final u = KuraSheehanCheckpoint.umbralesParaSemana(6);
      expect(u.cierre, 65);
      expect(u.alerta, 45);
    });
    test('semana 8: cierre 75%, alerta 60%', () {
      final u = KuraSheehanCheckpoint.umbralesParaSemana(8);
      expect(u.cierre, 75);
      expect(u.alerta, 60);
    });
    test('semana fuera de rango (1) usa el extremo mas cercano (semana 2)', () {
      final u = KuraSheehanCheckpoint.umbralesParaSemana(1);
      expect(u.cierre, 30);
      expect(u.alerta, 15);
    });
    test('semana fuera de rango (10) usa el extremo mas cercano (semana 8)', () {
      final u = KuraSheehanCheckpoint.umbralesParaSemana(10);
      expect(u.cierre, 75);
      expect(u.alerta, 60);
    });
    test('semana intermedia (3) interpola linealmente entre 2 y 4', () {
      final u = KuraSheehanCheckpoint.umbralesParaSemana(3);
      expect(u.cierre, closeTo(40, 1e-9)); // (30+50)/2
      expect(u.alerta, closeTo(22.5, 1e-9)); // (15+30)/2
    });
  });

  group('Decision del checkpoint', () {
    test('reduccion >= umbral de cierre en semana 4 => confirmar cierre', () {
      final r = KuraSheehanCheckpoint.evaluate(
        semana: 4,
        areaBasalCm2: 10,
        areaActualCm2: 4, // reduccion 60% >= 50%
      );
      expect(r.pctReduccionBruta, closeTo(60.0, 1e-9));
      expect(r.decision, SheehanDecision.confirmarCierre);
    });

    test('reduccion entre alerta y cierre en semana 4 => extender observacion', () {
      final r = KuraSheehanCheckpoint.evaluate(
        semana: 4,
        areaBasalCm2: 10,
        areaActualCm2: 6, // reduccion 40%, entre 30% y 50%
      );
      expect(r.pctReduccionBruta, closeTo(40.0, 1e-9));
      expect(r.decision, SheehanDecision.extenderObservacion);
    });

    test('reduccion por debajo del umbral de alerta => reclasificar a C', () {
      final r = KuraSheehanCheckpoint.evaluate(
        semana: 4,
        areaBasalCm2: 10,
        areaActualCm2: 9, // reduccion 10% < 30%
      );
      expect(r.pctReduccionBruta, closeTo(10.0, 1e-9));
      expect(r.decision, SheehanDecision.reclasificarC);
    });

    test('penalizaciones reducen el % ajustado y pueden cambiar la decision', () {
      // Reduccion bruta 55% (>=50% cierre en semana 4), pero con 2
      // penalizaciones de 5pp cada una => 45% ajustado (< 50%, >=30% alerta)
      final r = KuraSheehanCheckpoint.evaluate(
        semana: 4,
        areaBasalCm2: 10,
        areaActualCm2: 4.5, // reduccion bruta 55%
        infeccionActiva: true,
        bajaAdherencia: true,
      );
      expect(r.pctReduccionBruta, closeTo(55.0, 1e-9));
      expect(r.pctReduccionAjustada, closeTo(45.0, 1e-9));
      expect(r.decision, SheehanDecision.extenderObservacion);
      expect(r.penalizacionesAplicadas.length, 2);
    });

    test('area basal = 0 no produce division por cero (reduccion 0%)', () {
      final r = KuraSheehanCheckpoint.evaluate(
        semana: 4,
        areaBasalCm2: 0,
        areaActualCm2: 0,
      );
      expect(r.pctReduccionBruta, 0.0);
      expect(r.decision, SheehanDecision.reclasificarC);
    });

    test('area actual mayor que basal (empeoramiento) da reduccion negativa', () {
      final r = KuraSheehanCheckpoint.evaluate(
        semana: 4,
        areaBasalCm2: 10,
        areaActualCm2: 15,
      );
      expect(r.pctReduccionBruta, closeTo(-50.0, 1e-9));
      expect(r.decision, SheehanDecision.reclasificarC);
    });

    test('todas las penalizaciones activas simultaneamente', () {
      final r = KuraSheehanCheckpoint.evaluate(
        semana: 6,
        areaBasalCm2: 10,
        areaActualCm2: 3, // reduccion bruta 70%
        infeccionActiva: true,
        bajaAdherencia: true,
        deterioroDelLecho: true,
        aumentoDeExudado: true,
      );
      expect(r.pctReduccionBruta, closeTo(70.0, 1e-9));
      expect(r.pctReduccionAjustada, closeTo(50.0, 1e-9)); // 70 - 4*5
      expect(r.penalizacionesAplicadas.length, 4);
      // semana 6: cierre 65%, alerta 45% -> 50% cae en "extender observacion"
      expect(r.decision, SheehanDecision.extenderObservacion);
    });
  });
}
