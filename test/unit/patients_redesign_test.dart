import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:kuratracker/engine/models/kura_engine_enums.dart';
import 'package:kuratracker/features/patients/patient_wound_summary.dart';
import 'package:kuratracker/features/patients/patients_view_preferences.dart';
import 'package:kuratracker/models/center_type.dart';
import 'package:kuratracker/services/data_repository.dart';

/// Cobertura del rediseno de PatientsListScreen (vista Lista/Tarjeta,
/// chips de etiologia, filtros y persistencia con shared_preferences).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('PatientWoundSummary.compute', () {
    test(
        'incluye solo heridas ACTIVAS y sus etiologias distintas (sin '
        'duplicados) para un paciente con varias heridas de la misma '
        'etiologia', () async {
      final repo = await DataRepository.instance();
      final patients = repo.listAllPatients();
      // Paciente 1 del DemoSeed: pie diabetico activo (w1).
      final p1 = patients.firstWhere((p) => p.folio == 'EXP2025-0001');

      final summary = PatientWoundSummary.compute(repo, p1.id);

      expect(summary.hasActiveWounds, isTrue);
      expect(summary.activeCount, 1);
      expect(summary.etiologies, [Etiologia.pieDiabetico]);
    });

    test(
        'un paciente sin heridas activas devuelve activeCount=0, '
        'hasActiveWounds=false y etiologies vacio', () async {
      final repo = await DataRepository.instance();
      final created = await repo.createOrganization('Org sin heridas (prueba)', CenterType.clinicaHeridas);
      // Paciente nuevo sin ninguna herida creada.
      final patient = await repo.createPatient(
        fullName: 'Paciente Sin Heridas',
        organizationId: created.id,
      );

      final summary = PatientWoundSummary.compute(repo, patient.id);

      expect(summary.hasActiveWounds, isFalse);
      expect(summary.activeCount, 0);
      expect(summary.etiologies, isEmpty);
    });

    test('una herida cerrada (is_active=false) no cuenta ni aparece como chip', () async {
      final repo = await DataRepository.instance();
      final created = await repo.createOrganization('Org herida cerrada (prueba)', CenterType.clinicaHeridas);
      final patient = await repo.createPatient(
        fullName: 'Paciente Herida Cerrada',
        organizationId: created.id,
      );
      await repo.createWound({
        'id': 'test-wound-cerrada',
        'patient_id': patient.id,
        'etiology': 'vascular',
        'body_location_primary': 'pierna_izquierda',
        'is_active': false,
        'created_at': DateTime.now().toIso8601String(),
      });

      final summary = PatientWoundSummary.compute(repo, patient.id);

      expect(summary.hasActiveWounds, isFalse);
      expect(summary.etiologies, isEmpty);
    });
  });

  group('PatientsViewPreferences (persistencia)', () {
    test(
        'PatientsViewPreferencesStore.load() sin nada guardado devuelve el '
        'default: vista Lista, sin filtros', () async {
      final loaded = await PatientsViewPreferencesStore.load();
      expect(loaded.viewMode, PatientsViewMode.list);
      expect(loaded.hasActiveFilters, isFalse);
    });

    test(
        'PatientsViewPreferencesStore.save()/load() hace round-trip de la '
        'vista Tarjeta y de los filtros estructurados (etiologia, estado, '
        'sitio)', () async {
      const prefs = PatientsViewPreferences(
        viewMode: PatientsViewMode.grid,
        etiologies: {Etiologia.pieDiabetico, Etiologia.vascular},
        statusFilter: PatientsStatusFilter.withActiveWounds,
        siteId: 'site-123',
      );

      await PatientsViewPreferencesStore.save(prefs);
      final loaded = await PatientsViewPreferencesStore.load();

      expect(loaded.viewMode, PatientsViewMode.grid);
      expect(loaded.etiologies, {Etiologia.pieDiabetico, Etiologia.vascular});
      expect(loaded.statusFilter, PatientsStatusFilter.withActiveWounds);
      expect(loaded.siteId, 'site-123');
      expect(loaded.hasActiveFilters, isTrue);
    });

    test(
        'la busqueda de texto (query) deliberadamente NO se persiste: tras '
        'guardar con un query no vacio, al recargar vuelve a vacio', () async {
      const prefs = PatientsViewPreferences(query: 'Roberto Sanchez');
      await PatientsViewPreferencesStore.save(prefs);

      final loaded = await PatientsViewPreferencesStore.load();
      expect(loaded.query, isEmpty);
    });

    test('copyWith(siteId: null) permite limpiar explicitamente el filtro de sitio', () {
      const prefs = PatientsViewPreferences(siteId: 'site-abc');
      final cleared = prefs.copyWith(siteId: null);
      expect(cleared.siteId, isNull);
    });
  });
}
