// Tests de las clasificaciones/campos por etiología (Prompt 5): serialización
// del modelo Wound con los nuevos enums y tolerancia a valores desconocidos.
import 'package:flutter_test/flutter_test.dart';
import 'package:kuratracker/engine/models/kura_engine_enums.dart';
import 'package:kuratracker/models/wound.dart';

void main() {
  group('enumByName', () {
    test('resuelve por name y tolera null/desconocido', () {
      expect(enumByName(NpuapEstadio.values, 'iii'), NpuapEstadio.iii);
      expect(enumByName(NpuapEstadio.values, null), isNull);
      expect(enumByName(NpuapEstadio.values, 'inexistente'), isNull);
    });
  });

  group('Wound — roundtrip de clasificaciones por etiología', () {
    test('todos los campos nuevos sobreviven toJson/fromJson', () {
      final w = Wound(
        id: 'w1',
        patientId: 'p1',
        etiology: Etiologia.pieDiabetico,
        bodyLocationPrimary: 'pie_derecho',
        createdAt: DateTime(2026, 7, 20),
        updSubtipo: UpdSubtipo.neuroisquemica,
        texasGrade: TexasGrade.g2,
        texasStage: TexasStage.d,
        idsaIwgdf: IdsaIwgdf.moderada,
        sensibilidadProtectora: SensibilidadProtectora.ausente,
        rutherford: Rutherford.c5,
        npuapEstadio: NpuapEstadio.lesionTisularProfunda,
        claseContaminacion: ClaseContaminacion.contaminada,
        tipoCierre: TipoCierre.segunda,
        drenajeTipo: DrenajeTipo.aspiracionCerrada,
        suturaTipo: SuturaTipo.grapas,
        motivoEgreso: MotivoEgreso.defuncion,
      );

      final back = Wound.fromJson(w.toJson());
      expect(back.updSubtipo, UpdSubtipo.neuroisquemica);
      expect(back.texasGrade, TexasGrade.g2);
      expect(back.texasStage, TexasStage.d);
      expect(back.idsaIwgdf, IdsaIwgdf.moderada);
      expect(back.sensibilidadProtectora, SensibilidadProtectora.ausente);
      expect(back.rutherford, Rutherford.c5);
      expect(back.npuapEstadio, NpuapEstadio.lesionTisularProfunda);
      expect(back.claseContaminacion, ClaseContaminacion.contaminada);
      expect(back.tipoCierre, TipoCierre.segunda);
      expect(back.drenajeTipo, DrenajeTipo.aspiracionCerrada);
      expect(back.suturaTipo, SuturaTipo.grapas);
      expect(back.motivoEgreso, MotivoEgreso.defuncion);
    });

    test('campos nuevos ausentes quedan null (compatibilidad hacia atrás)', () {
      final w = Wound.fromJson({
        'id': 'w2',
        'patient_id': 'p2',
        'etiology': 'lpp',
        'body_location_primary': 'sacro',
        'is_active': true,
        'created_at': DateTime(2026, 7, 20).toIso8601String(),
      });
      expect(w.npuapEstadio, isNull);
      expect(w.texasGrade, isNull);
      expect(w.motivoEgreso, isNull);
      expect(w.etiology, Etiologia.lpp);
    });

    test('discharge_reason mapea a MotivoEgreso', () {
      final w = Wound.fromJson({
        'id': 'w3',
        'patient_id': 'p3',
        'etiology': 'quirurgica',
        'body_location_primary': 'abdomen',
        'discharge_reason': 'alta_voluntaria',
        'is_active': false,
        'created_at': DateTime(2026, 7, 20).toIso8601String(),
      });
      // El name del enum es camelCase (altaVoluntaria); un valor snake_case del
      // servidor no coincide -> null. Verificamos el name correcto:
      expect(w.motivoEgreso, isNull);
      final w2 = Wound.fromJson({
        ...w.toJson(),
        'discharge_reason': MotivoEgreso.altaVoluntaria.name,
      });
      expect(w2.motivoEgreso, MotivoEgreso.altaVoluntaria);
    });

    test('etiquetas legibles definidas para todos los valores', () {
      for (final v in NpuapEstadio.values) {
        expect(v.label, isNotEmpty);
      }
      for (final v in TexasStage.values) {
        expect(v.label, isNotEmpty);
      }
      for (final v in MotivoEgreso.values) {
        expect(v.label, isNotEmpty);
      }
    });
  });
}
