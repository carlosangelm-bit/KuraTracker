import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:kuratracker/engine/models/kura_engine_enums.dart';
import 'package:kuratracker/models/consultation.dart';
import 'package:kuratracker/services/data_repository.dart';
import 'package:kuratracker/services/export/record_export.dart';

/// Paquete de salida (entrega en carpetas): un paciente → árbol de archivos.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('sanitize quita caracteres inválidos y recorta longitud', () {
    expect(RecordExportService.sanitize('EXP/2025:01*?'), 'EXP_2025_01__');
    expect(RecordExportService.sanitize(''), '_');
    expect(RecordExportService.sanitize('a' * 200).length, 80);
  });

  test('buildPatientFiles arma el árbol por folio/herida/fecha con la foto',
      () async {
    final repo = await DataRepository.instance();
    final siteId = repo.listSites().first.id;
    final staffId = repo.listStaff().first.id;
    // Paciente NUEVO (sin heridas/fotos sembradas): conteos deterministas.
    final orgId = repo.listAllPatients().first.organizationId;
    final patient = await repo.createPatient(
        fullName: 'Paciente Export Test', organizationId: orgId);

    final wound = await repo.createWound({
      'patient_id': patient.id,
      'etiology': Etiologia.lpp.name,
      'body_location_primary': 'Sacro (export test)',
    });
    final c = await repo.createConsultation(
      patientId: patient.id,
      staffId: staffId,
      siteId: siteId,
      visitType: VisitType.seguimiento,
      visitDate: DateTime.parse('2026-03-14'),
      isDraft: false,
    );
    final m = await repo.createMeasurement({
      'wound_id': wound.id,
      'consultation_id': c.id,
      'measured_at': '2026-03-14',
      'length_cm': 3.0,
      'width_cm': 2.0,
      'area_cm2': 6.0,
      'depth_cm': 0.4,
    });
    // Foto con storage_path = data URL (autocontenida, sin Supabase).
    await repo.createPhoto({
      'wound_id': wound.id,
      'consultation_id': c.id,
      'measurement_id': m.id,
      'taken_at': '2026-03-14T09:00:00.000',
      'photo_stage': 'con_medicion',
      'storage_path': 'data:image/jpeg;base64,/9j/4AAQ',
    });

    final r = await RecordExportService.buildPatientFiles(repo, patient);
    final paths = r.files.map((f) => f.path).toList();
    final folio = RecordExportService.sanitize(patient.folio);

    expect(paths, contains('$folio/datos.csv'));
    expect(paths, contains('$folio/mediciones.csv'));
    expect(paths, contains('$folio/consultas.csv'));
    final wdir = '$folio/heridas/${RecordExportService.sanitize(wound.id)}_lpp';
    expect(paths, contains('$wdir/mediciones.csv'));
    // Foto nombrada con la fecha al inicio (serie evolutiva ordenable).
    expect(paths.any((p) => p.startsWith('$wdir/fotos/2026-03-14_') && p.endsWith('.jpg')),
        isTrue);
    expect(r.photoCount, 1);
    expect(r.photoMissing, 0);

    // El ZIP se arma y se puede volver a leer.
    final zip = RecordExportService.zip(r.files);
    expect(zip, isNotEmpty);
    final decoded = ZipDecoder().decodeBytes(zip);
    expect(decoded.files.any((f) => f.name == '$folio/datos.csv'), isTrue);
  });
}
