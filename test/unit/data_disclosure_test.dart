import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:kuratracker/services/data_repository.dart';

/// Fase 1 (0101): el registro de divulgación deja constancia de cada salida de
/// datos y se puede listar por centro.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('recordDataDisclosure inserta y listDataDisclosures lo devuelve', () async {
    final repo = await DataRepository.instance();
    final orgId = repo.listAllPatients().first.organizationId!;

    final antes = repo.listDataDisclosures(organizationId: orgId).length;

    await repo.recordDataDisclosure(
      organizationId: orgId,
      actorId: 'user-1',
      actorEmail: 'admin@centro.mx',
      kind: 'expediente_paciente',
      scope: {'folio': 'EXP2025-0001'},
      recordCount: 7,
      patientCount: 1,
      photoCount: 3,
      missingCount: 1,
      fileName: 'expediente_EXP2025-0001_2026-08-31.zip',
    );

    final list = repo.listDataDisclosures(organizationId: orgId);
    expect(list.length, antes + 1);
    final d = list.first; // orden descendente
    expect(d.kind, 'expediente_paciente');
    expect(d.recordCount, 7);
    expect(d.photoCount, 3);
    expect(d.missingCount, 1);
    expect(d.actorEmail, 'admin@centro.mx');
    expect(d.kindLabel, 'Expediente de un paciente');

    // Filtro por otra organización no lo incluye.
    expect(repo.listDataDisclosures(organizationId: 'otra-org'), isEmpty);
  });

  test('sin organización no registra', () async {
    final repo = await DataRepository.instance();
    await repo.recordDataDisclosure(
      organizationId: null,
      actorId: 'x',
      actorEmail: 'x',
      kind: 'csv_mediciones',
    );
    expect(repo.listDataDisclosures().where((d) => d.actorId == 'x'), isEmpty);
  });
}
