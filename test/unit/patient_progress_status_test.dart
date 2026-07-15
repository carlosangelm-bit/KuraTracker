import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:kuratracker/engine/kura_sheehan_checkpoint.dart';
import 'package:kuratracker/engine/models/kura_engine_enums.dart';
import 'package:kuratracker/engine/sheehan_decision_style.dart';
import 'package:kuratracker/engine/wound_checkpoint_deriver.dart';
import 'package:kuratracker/features/patients/patient_progress_status.dart';
import 'package:kuratracker/features/patients/patients_view_preferences.dart';
import 'package:kuratracker/models/consultation.dart';
import 'package:kuratracker/models/wound.dart';
import 'package:kuratracker/services/data_repository.dart';

/// Cobertura del semaforo de avance (trayectoria, checkpoint de Sheehan):
/// derivacion wound -> SheehanCheckpointResult?, mapeo color/etiqueta,
/// agregacion del peor estatus por paciente, y persistencia del nuevo
/// filtro "Estatus de avance" en PatientsViewPreferences.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Future<({DataRepository repo, String siteId, String staffId, String patientId})>
      seedBase() async {
    final repo = await DataRepository.instance();
    final sites = repo.listSites();
    final staff = repo.listStaff();
    final patients = repo.listAllPatients();
    return (
      repo: repo,
      siteId: sites.first.id,
      staffId: staff.first.id,
      patientId: patients.first.id,
    );
  }

  Future<Wound> createWoundWithMeasurements(
    DataRepository repo, {
    required String patientId,
    required String siteId,
    required String staffId,
    required List<double> areasCm2,
    List<int>? daysAgo,
    bool lastLowAdherence = false,
    bool lastInfeccion = false,
  }) async {
    final wound = await repo.createWound({
      'patient_id': patientId,
      'etiology': Etiologia.vascular.name,
      'body_location_primary': 'Pierna izquierda (prueba semaforo)',
    });

    // Por default, una visita por semana (mas antigua primero); permite
    // pasar `daysAgo` explicito cuando el test necesita controlar la
    // semana exacta (los umbrales del checkpoint varian por semana).
    final effectiveDaysAgo = daysAgo ??
        [for (var i = 0; i < areasCm2.length; i++) (areasCm2.length - i) * 7];

    for (var i = 0; i < areasCm2.length; i++) {
      final visitDate = DateTime.now().subtract(Duration(days: effectiveDaysAgo[i]));
      final consultation = await repo.createConsultation(
        patientId: patientId,
        staffId: staffId,
        siteId: siteId,
        visitType: i == 0 ? VisitType.valoracion : VisitType.seguimiento,
        visitDate: visitDate,
        isDraft: false,
      );
      await repo.createMeasurement({
        'wound_id': wound.id,
        'consultation_id': consultation.id,
        'measured_at': visitDate.toIso8601String(),
        'length_cm': 1.0,
        'width_cm': 1.0,
        'area_cm2': areasCm2[i],
      });
      final isLast = i == areasCm2.length - 1;
      await repo.createAssessment({
        'consultation_id': consultation.id,
        'wound_id': wound.id,
        'exudate_amount': ExudadoCantidad.escaso.name,
        'infection_criteria': isLast && lastInfeccion
            ? [InfeccionCriterioIwii.eritemaPerilesional.name]
            : <String>[],
        'low_adherence': isLast && lastLowAdherence,
      });
    }
    return wound;
  }

  group('WoundCheckpointDeriver.evaluate (derivacion wound -> checkpoint)', () {
    test('herida sin ningun seguimiento (solo basal) devuelve null', () async {
      final base = await seedBase();
      final wound = await createWoundWithMeasurements(
        base.repo,
        patientId: base.patientId,
        siteId: base.siteId,
        staffId: base.staffId,
        areasCm2: [10.0],
      );

      final checkpoint = WoundCheckpointDeriver.evaluate(base.repo, wound);
      expect(checkpoint, isNull);
    });

    test('herida con basal + 1 seguimiento (2 mediciones) SI calcula checkpoint', () async {
      final base = await seedBase();
      final wound = await createWoundWithMeasurements(
        base.repo,
        patientId: base.patientId,
        siteId: base.siteId,
        staffId: base.staffId,
        areasCm2: [16.0, 6.0], // reduccion fuerte -> debe cerrar
      );

      final checkpoint = WoundCheckpointDeriver.evaluate(base.repo, wound);
      expect(checkpoint, isNotNull);
      expect(checkpoint!.decision, SheehanDecision.confirmarCierre);
    });

    test(
        'usa low_adherence/infection_criteria de la evaluacion mas reciente '
        '(coincide con la logica de follow_up_screen.dart)', () async {
      final base = await seedBase();
      final wound = await createWoundWithMeasurements(
        base.repo,
        patientId: base.patientId,
        siteId: base.siteId,
        staffId: base.staffId,
        areasCm2: [16.0, 10.24, 6.25],
        lastLowAdherence: true,
        lastInfeccion: true,
      );

      final checkpoint = WoundCheckpointDeriver.evaluate(base.repo, wound);
      expect(checkpoint, isNotNull);
      expect(checkpoint!.penalizacionesAplicadas,
          containsAll(['Baja adherencia al tratamiento', 'Infeccion activa']));
      expect(checkpoint.pctReduccionAjustada, lessThan(checkpoint.pctReduccionBruta));
    });
  });

  group('ProgressStatus (mapeo color/etiqueta, exigido por la especificacion)', () {
    test('confirmarCierre -> good/verde/"Avanza según lo esperado"', () {
      expect(SheehanDecision.confirmarCierre.toProgressStatus, ProgressStatus.good);
      expect(ProgressStatus.good.shortLabel, 'Avanza según lo esperado');
    });

    test('extenderObservacion -> warning/amarillo/"Avanza con reservas"', () {
      expect(SheehanDecision.extenderObservacion.toProgressStatus, ProgressStatus.warning);
      expect(ProgressStatus.warning.shortLabel, 'Avanza con reservas');
    });

    test('reclasificarC -> danger/rojo/"No avanza"', () {
      expect(SheehanDecision.reclasificarC.toProgressStatus, ProgressStatus.danger);
      expect(ProgressStatus.danger.shortLabel, 'No avanza');
    });

    test('sin datos suficientes -> noData/gris/"Sin seguimiento aún"', () {
      expect(ProgressStatus.noData.shortLabel, 'Sin seguimiento aún');
    });

    test('el tooltip de todos los estatus enmarca el resultado como apoyo a '
        'la decision, no un juicio definitivo (punto 5 de la especificacion)', () {
      for (final s in ProgressStatus.values) {
        expect(s.tooltip(), contains('Apoyo a la decisión'));
      }
    });
  });

  group('PatientProgressStatus.compute (agregacion peor estatus por paciente)', () {
    test('paciente sin heridas activas -> worst = noData, byWound vacio', () async {
      final base = await seedBase();
      final result = PatientProgressStatus.compute(base.repo, const []);
      expect(result.worst, ProgressStatus.noData);
      expect(result.byWound, isEmpty);
    });

    test(
        'con 2 heridas activas (una roja por reclasificarC, otra verde por '
        'confirmarCierre), el peor estatus mostrado es rojo', () async {
      final base = await seedBase();
      final woundRoja = await createWoundWithMeasurements(
        base.repo,
        patientId: base.patientId,
        siteId: base.siteId,
        staffId: base.staffId,
        areasCm2: [16.0, 15.5], // reduccion minima -> reclasificarC
      );
      final woundVerde = await createWoundWithMeasurements(
        base.repo,
        patientId: base.patientId,
        siteId: base.siteId,
        staffId: base.staffId,
        areasCm2: [16.0, 4.0], // reduccion fuerte -> confirmarCierre
      );

      final result = PatientProgressStatus.compute(
          base.repo, [woundRoja, woundVerde]);

      expect(result.worst, ProgressStatus.danger);
      expect(result.byWound.length, 2);
      final statuses = result.byWound.map((w) => w.status).toSet();
      expect(statuses, {ProgressStatus.danger, ProgressStatus.good});
    });

    test(
        'una herida activa sin seguimiento (sin datos) y otra amarilla '
        '(extenderObservacion): el peor estatus es amarillo, no gris '
        '(rojo > amarillo > verde > sin datos)', () async {
      final base = await seedBase();
      final woundSinDatos = await createWoundWithMeasurements(
        base.repo,
        patientId: base.patientId,
        siteId: base.siteId,
        staffId: base.staffId,
        areasCm2: [10.0], // solo basal -> sin datos
      );
      // Semana 4 (umbral oficial validado): cierre 50% / alerta 30%. Con
      // 35% de reduccion cae en el rango "extender observacion" (ni
      // cierra, ni reclasifica a C).
      final woundAmarilla = await createWoundWithMeasurements(
        base.repo,
        patientId: base.patientId,
        siteId: base.siteId,
        staffId: base.staffId,
        areasCm2: [10.0, 6.5],
        daysAgo: [28, 0],
      );

      final result = PatientProgressStatus.compute(
          base.repo, [woundSinDatos, woundAmarilla]);

      expect(result.worst, ProgressStatus.warning);
    });

    test('herida activa sin seguimiento -> esa herida se reporta como noData '
        'en byWound (no se fuerza un color)', () async {
      final base = await seedBase();
      final wound = await createWoundWithMeasurements(
        base.repo,
        patientId: base.patientId,
        siteId: base.siteId,
        staffId: base.staffId,
        areasCm2: [8.0],
      );

      final result = PatientProgressStatus.compute(base.repo, [wound]);
      expect(result.worst, ProgressStatus.noData);
      expect(result.byWound.single.status, ProgressStatus.noData);
      expect(result.byWound.single.checkpoint, isNull);
    });
  });

  group('PatientsViewPreferences (persistencia del filtro "Estatus de avance")', () {
    test('por default progressStatuses esta vacio y no activa hasActiveFilters', () {
      const prefs = PatientsViewPreferences();
      expect(prefs.progressStatuses, isEmpty);
      expect(prefs.hasActiveFilters, isFalse);
    });

    test(
        'save()/load() hace round-trip del filtro multi-seleccion de '
        'estatus de avance, independiente de statusFilter', () async {
      const prefs = PatientsViewPreferences(
        progressStatuses: {ProgressStatus.danger, ProgressStatus.noData},
      );

      await PatientsViewPreferencesStore.save(prefs);
      final loaded = await PatientsViewPreferencesStore.load();

      expect(loaded.progressStatuses, {ProgressStatus.danger, ProgressStatus.noData});
      expect(loaded.statusFilter, PatientsStatusFilter.all,
          reason: 'el nuevo filtro no debe pisar/confundirse con statusFilter existente');
      expect(loaded.hasActiveFilters, isTrue);
    });

    test('copyWith(progressStatuses: {}) permite limpiar explicitamente el filtro', () {
      const prefs = PatientsViewPreferences(progressStatuses: {ProgressStatus.good});
      final cleared = prefs.copyWith(progressStatuses: {});
      expect(cleared.progressStatuses, isEmpty);
      expect(cleared.hasActiveFilters, isFalse);
    });
  });
}
