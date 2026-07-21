import 'package:flutter_test/flutter_test.dart';
import 'package:kuratracker/engine/kura_sheehan_checkpoint.dart';
import 'package:kuratracker/engine/models/kura_engine_enums.dart';

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

  // ===========================================================================
  // PROMPT 4 — Umbrales de Sheehan POR ETIOLOGÍA
  // UPD 8 sem/50%, MMII 4 sem/40%, LPP 8 sem/50%, quirúrgica 4 sem/50%.
  // ===========================================================================
  group('Hitos por etiología', () {
    test('hitos declarados coinciden con el protocolo', () {
      expect(KuraSheehanCheckpoint.hitoParaEtiologia(Etiologia.pieDiabetico),
          (semanaHito: 8, pctCierre: 50.0));
      expect(KuraSheehanCheckpoint.hitoParaEtiologia(Etiologia.vascular),
          (semanaHito: 4, pctCierre: 40.0));
      expect(KuraSheehanCheckpoint.hitoParaEtiologia(Etiologia.lpp),
          (semanaHito: 8, pctCierre: 50.0));
      expect(KuraSheehanCheckpoint.hitoParaEtiologia(Etiologia.quirurgica),
          (semanaHito: 4, pctCierre: 50.0));
    });

    test('etiologías sin hito propio devuelven null (usan tabla genérica)', () {
      expect(KuraSheehanCheckpoint.hitoParaEtiologia(Etiologia.traumatica),
          isNull);
      expect(KuraSheehanCheckpoint.hitoParaEtiologia(Etiologia.otra), isNull);
    });

    test('en la semana del hito, cierre = % del hito y alerta = 0.6x', () {
      final upd = KuraSheehanCheckpoint.umbralesParaEtiologiaYSemana(
          Etiologia.pieDiabetico, 8);
      expect(upd.cierre, closeTo(50, 1e-9));
      expect(upd.alerta, closeTo(30, 1e-9));

      final mmii = KuraSheehanCheckpoint.umbralesParaEtiologiaYSemana(
          Etiologia.vascular, 4);
      expect(mmii.cierre, closeTo(40, 1e-9));
      expect(mmii.alerta, closeTo(24, 1e-9));

      final quir = KuraSheehanCheckpoint.umbralesParaEtiologiaYSemana(
          Etiologia.quirurgica, 4);
      expect(quir.cierre, closeTo(50, 1e-9));
    });

    test('rampa lineal antes del hito (UPD semana 4 = mitad de 8 -> 25%)', () {
      final upd = KuraSheehanCheckpoint.umbralesParaEtiologiaYSemana(
          Etiologia.pieDiabetico, 4);
      expect(upd.cierre, closeTo(25, 1e-9));
    });

    test('se mantiene plano después del hito (UPD semana 12 -> 50%)', () {
      final upd = KuraSheehanCheckpoint.umbralesParaEtiologiaYSemana(
          Etiologia.pieDiabetico, 12);
      expect(upd.cierre, closeTo(50, 1e-9));
    });

    test('evaluate con etiología UPD en semana 8 clasifica por su hito', () {
      // 50% de reducción en la semana del hito -> confirmar cierre.
      final ok = KuraSheehanCheckpoint.evaluate(
        semana: 8,
        areaBasalCm2: 10,
        areaActualCm2: 5,
        etiologia: Etiologia.pieDiabetico,
      );
      expect(ok.umbralCierre, closeTo(50, 1e-9));
      expect(ok.decision, SheehanDecision.confirmarCierre);

      // 40% -> por debajo del cierre (50) pero sobre alerta (30): observar.
      final obs = KuraSheehanCheckpoint.evaluate(
        semana: 8,
        areaBasalCm2: 10,
        areaActualCm2: 6,
        etiologia: Etiologia.pieDiabetico,
      );
      expect(obs.decision, SheehanDecision.extenderObservacion);

      // 10% -> por debajo de alerta: reclasificar a C.
      final malo = KuraSheehanCheckpoint.evaluate(
        semana: 8,
        areaBasalCm2: 10,
        areaActualCm2: 9,
        etiologia: Etiologia.pieDiabetico,
      );
      expect(malo.decision, SheehanDecision.reclasificarC);
    });

    test('MMII en semana 4 con 40% reducción -> confirmar cierre', () {
      final r = KuraSheehanCheckpoint.evaluate(
        semana: 4,
        areaBasalCm2: 10,
        areaActualCm2: 6, // 40%
        etiologia: Etiologia.vascular,
      );
      expect(r.umbralCierre, closeTo(40, 1e-9));
      expect(r.decision, SheehanDecision.confirmarCierre);
    });

    test('sin etiología conserva el comportamiento genérico (semana 4=50%)',
        () {
      final r = KuraSheehanCheckpoint.evaluate(
        semana: 4,
        areaBasalCm2: 10,
        areaActualCm2: 6, // 40% -> < 50 genérico
      );
      expect(r.umbralCierre, 50);
      expect(r.decision, SheehanDecision.extenderObservacion);
    });
  });
}
