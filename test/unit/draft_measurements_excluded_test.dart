import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:kuratracker/engine/models/kura_engine_enums.dart';
import 'package:kuratracker/models/consultation.dart';
import 'package:kuratracker/services/data_repository.dart';

/// Ronda 7: las mediciones de consultas en BORRADOR no deben entrar a la
/// evolución clínica. `listMeasurementsForWound` las excluye por defecto y solo
/// las incluye con `includeDrafts: true` (reabrir borrador / detalle de esa
/// consulta). Antes, una medición ligera de borrador (composición 0) se volvía
/// la "actual" y marcaba deterioro falso por pérdida de granulación.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('listMeasurementsForWound excluye borradores por defecto', () async {
    final repo = await DataRepository.instance();
    final siteId = repo.listSites().first.id;
    final staffId = repo.listStaff().first.id;
    final patientId = repo.listAllPatients().first.id;

    final wound = await repo.createWound({
      'patient_id': patientId,
      'etiology': Etiologia.pieDiabetico.name,
      'body_location_primary': 'Talón (prueba borrador)',
    });

    Future<void> addMeasurement({
      required bool isDraft,
      required int daysAgo,
      required double granulation,
    }) async {
      final c = await repo.createConsultation(
        patientId: patientId,
        staffId: staffId,
        siteId: siteId,
        visitType: VisitType.seguimiento,
        visitDate: DateTime.now().subtract(Duration(days: daysAgo)),
        isDraft: isDraft,
      );
      await repo.createMeasurement({
        'wound_id': wound.id,
        'consultation_id': c.id,
        'measured_at': c.visitDate.toIso8601String().substring(0, 10),
        'length_cm': 3.0,
        'width_cm': 2.0,
        'area_cm2': 6.0,
        'depth_cm': 0.4,
        'granulation_pct': granulation,
      });
    }

    // Dos seguimientos FINALIZADOS (el último con 60% de granulación) + un
    // BORRADOR reciente con composición ligera (0%).
    await addMeasurement(isDraft: false, daysAgo: 14, granulation: 80);
    await addMeasurement(isDraft: false, daysAgo: 7, granulation: 60);
    await addMeasurement(isDraft: true, daysAgo: 0, granulation: 0);

    final visible = repo.listMeasurementsForWound(wound.id);
    expect(visible.length, 2, reason: 'el borrador no debe contarse');
    expect(visible.last.granulationPct, 60,
        reason: 'la "actual" es el último FINALIZADO (60%), no el borrador 0%');

    final all = repo.listMeasurementsForWound(wound.id, includeDrafts: true);
    expect(all.length, 3, reason: 'con includeDrafts sí aparece el borrador');
    expect(all.last.granulationPct, 0);
  });
}
