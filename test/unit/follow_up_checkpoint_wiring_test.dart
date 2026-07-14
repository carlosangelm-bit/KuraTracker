import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:kuratracker/engine/kura_sheehan_checkpoint.dart';
import 'package:kuratracker/engine/models/kura_engine_enums.dart';
import 'package:kuratracker/models/consultation.dart';
import 'package:kuratracker/services/data_repository.dart';

/// Prueba de aceptacion (a nivel de datos, sin UI): reproduce exactamente
/// la logica que ejecuta follow_up_screen.dart al construir el checkpoint
/// -- crea una herida con una medicion basal y 2 seguimientos con area
/// decreciente, el ultimo con low_adherence=true e infection_criteria no
/// vacio, y verifica que:
///  1) el checkpoint usa la evaluacion de la visita mas reciente (empate
///     por consultation_id, tal como hace follow_up_screen.dart),
///  2) bajaAdherencia e infeccionActiva se derivan correctamente de esa
///     evaluacion,
///  3) el % ajustado (con penalizaciones) es menor que el % bruto.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('checkpoint de seguimiento usa low_adherence + infection_criteria de la visita mas reciente', () async {
    final repo = await DataRepository.instance();

    // Sitio y personal minimos requeridos por createConsultation.
    final sites = repo.listSites();
    final staff = repo.listStaff();
    expect(sites, isNotEmpty, reason: 'DemoSeed debe poblar al menos un sitio');
    expect(staff, isNotEmpty, reason: 'DemoSeed debe poblar al menos un miembro del personal');
    final siteId = sites.first.id;
    final staffId = staff.first.id;

    // Paciente y herida nuevos, aislados de los datos de demo.
    final patients = repo.listAllPatients();
    final patientId = patients.first.id;

    final wound = await repo.createWound({
      'patient_id': patientId,
      'etiology': Etiologia.pieDiabetico.name,
      'body_location_primary': 'Talon derecho (prueba de aceptacion)',
    });

    // --- Visita 1: consulta basal (valoracion) ---
    final baselineConsultation = await repo.createConsultation(
      patientId: patientId,
      staffId: staffId,
      siteId: siteId,
      visitType: VisitType.valoracion,
      visitDate: DateTime.now().subtract(const Duration(days: 28)),
      isDraft: false,
    );
    await repo.createMeasurement({
      'wound_id': wound.id,
      'consultation_id': baselineConsultation.id,
      'measured_at': baselineConsultation.visitDate.toIso8601String(),
      'length_cm': 4.0,
      'width_cm': 4.0,
      'area_cm2': 16.0,
      'depth_cm': 0.5,
    });
    await repo.createAssessment({
      'consultation_id': baselineConsultation.id,
      'wound_id': wound.id,
      'exudate_amount': ExudadoCantidad.moderado.name,
      'exudate_type': ExudadoTipo.seroso.name,
      'infection_criteria': <String>[],
      'low_adherence': false,
    });

    // --- Visita 2: primer seguimiento, area menor, sin penalizaciones ---
    final followUp1 = await repo.createConsultation(
      patientId: patientId,
      staffId: staffId,
      siteId: siteId,
      visitType: VisitType.seguimiento,
      visitDate: DateTime.now().subtract(const Duration(days: 14)),
      isDraft: false,
    );
    await repo.createMeasurement({
      'wound_id': wound.id,
      'consultation_id': followUp1.id,
      'measured_at': followUp1.visitDate.toIso8601String(),
      'length_cm': 3.2,
      'width_cm': 3.2,
      'area_cm2': 10.24,
      'depth_cm': 0.3,
    });
    await repo.createAssessment({
      'consultation_id': followUp1.id,
      'wound_id': wound.id,
      'exudate_amount': ExudadoCantidad.escaso.name,
      'exudate_type': ExudadoTipo.seroso.name,
      'infection_criteria': <String>[],
      'low_adherence': false,
    });

    // --- Visita 3: segundo seguimiento (la mas reciente), area aun menor,
    // PERO con baja adherencia e infeccion reportadas.
    final followUp2 = await repo.createConsultation(
      patientId: patientId,
      staffId: staffId,
      siteId: siteId,
      visitType: VisitType.seguimiento,
      visitDate: DateTime.now(),
      isDraft: false,
    );
    await repo.createMeasurement({
      'wound_id': wound.id,
      'consultation_id': followUp2.id,
      'measured_at': followUp2.visitDate.toIso8601String(),
      'length_cm': 2.5,
      'width_cm': 2.5,
      'area_cm2': 6.25,
      'depth_cm': 0.2,
    });
    await repo.createAssessment({
      'consultation_id': followUp2.id,
      'wound_id': wound.id,
      'exudate_amount': ExudadoCantidad.moderado.name,
      'exudate_type': ExudadoTipo.purulento.name,
      'infection_criteria': [InfeccionCriterioIwii.eritemaPerilesional.name],
      'low_adherence': true,
    });

    // --- Reproduce exactamente la logica de follow_up_screen.dart ---
    final measurements = repo.listMeasurementsForWound(wound.id);
    expect(measurements.length, 3, reason: 'basal + 2 seguimientos');
    final baseline = measurements.first;
    final current = measurements.last;
    final hasFollowUps = measurements.length > 1;
    expect(hasFollowUps, isTrue);

    // Un punto por visita, orden ascendente por measured_at.
    expect(measurements.map((m) => m.areaCm2).toList(), [16.0, 10.24, 6.25]);
    for (var i = 1; i < measurements.length; i++) {
      expect(measurements[i].areaCm2, lessThan(measurements[i - 1].areaCm2),
          reason: 'la curva de area debe ser estrictamente descendente');
    }

    final assessments = repo.listAssessmentsForWound(wound.id);
    final matching = assessments.where((a) => a.consultationId == current.consultationId).toList();
    expect(matching, isNotEmpty,
        reason: 'debe existir una evaluacion ligada a la consulta de la medicion mas reciente');
    final latestAssessment = matching.first;

    // Verifica que efectivamente se recupero la evaluacion de la VISITA
    // MAS RECIENTE (followUp2), no la basal ni el primer seguimiento.
    expect(latestAssessment.lowAdherence, isTrue);
    expect(latestAssessment.infectionCriteria, isNotEmpty);
    expect(latestAssessment.exudateType, ExudadoTipo.purulento);

    final weeksSinceBaseline =
        current.measuredAt.difference(baseline.measuredAt).inDays ~/ 7;

    final checkpointSinPenalizar = KuraSheehanCheckpoint.evaluate(
      semana: weeksSinceBaseline.clamp(1, 52),
      areaBasalCm2: baseline.areaCm2,
      areaActualCm2: current.areaCm2,
    );

    final checkpointConPenalizaciones = KuraSheehanCheckpoint.evaluate(
      semana: weeksSinceBaseline.clamp(1, 52),
      areaBasalCm2: baseline.areaCm2,
      areaActualCm2: current.areaCm2,
      bajaAdherencia: latestAssessment.lowAdherence,
      infeccionActiva: latestAssessment.infectionCriteria.isNotEmpty,
    );

    // El % bruto es igual en ambos (no depende de penalizaciones).
    expect(checkpointConPenalizaciones.pctReduccionBruta,
        checkpointSinPenalizar.pctReduccionBruta);

    // El % ajustado, con los flags cableados desde datos reales, debe ser
    // estrictamente menor que el bruto (2 penalizaciones x 5pp = 10pp).
    expect(checkpointConPenalizaciones.pctReduccionAjustada,
        lessThan(checkpointConPenalizaciones.pctReduccionBruta));
    expect(
      checkpointConPenalizaciones.pctReduccionBruta -
          checkpointConPenalizaciones.pctReduccionAjustada,
      closeTo(10.0, 0.001),
    );
    expect(checkpointConPenalizaciones.penalizacionesAplicadas,
        containsAll(['Baja adherencia al tratamiento', 'Infeccion activa']));

    // Fotos: sin fotos registradas para esta herida de prueba -> ambas
    // (basal/actual) deben resolver a null (estado vacio explicito, no
    // datos ficticios).
    final photos = repo.listPhotosForWound(wound.id);
    expect(photos, isEmpty);
  });
}
