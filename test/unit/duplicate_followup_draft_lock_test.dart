// GUARDA (Carlos, 19-sep): candado DURABLE de duplicación del seguimiento. Antes, la memoria local de
// la pantalla (_createdConsultationId) evitaba el doble guardado dentro de una sesión de captura, pero
// salir y re-entrar a "registrar seguimiento" de la MISMA herida el MISMO día creaba un segundo
// borrador sin que nadie lo notara. El candado vive en la base: findOpenDraftForWound busca un
// borrador sin terminar de esa herida para hoy ANTES de crear. No reutiliza en silencio ni bloquea
// (dos curaciones el mismo día son un caso real); el clínico decide. Esta prueba MIRA EL RESULTADO:
// qué borrador (si alguno) detecta el candado en cada configuración.
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:kuratracker/engine/models/kura_engine_enums.dart';
import 'package:kuratracker/models/consultation.dart';
import 'package:kuratracker/services/data_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  late DataRepository repo;
  late String siteId;
  late String staffId;
  late String patientId;

  setUp(() async {
    repo = await DataRepository.instance();
    siteId = repo.listSites().first.id;
    staffId = repo.listStaff().first.id;
    patientId = repo.listAllPatients().first.id;
  });

  Future<String> addFollowUp(String woundId,
      {required bool isDraft, required int daysAgo}) async {
    final c = await repo.createConsultation(
      patientId: patientId,
      staffId: staffId,
      siteId: siteId,
      visitType: VisitType.seguimiento,
      visitDate: DateTime.now().subtract(Duration(days: daysAgo)),
      isDraft: isDraft,
    );
    await repo.createMeasurement({
      'wound_id': woundId,
      'consultation_id': c.id,
      'measured_at': c.visitDate.toIso8601String().substring(0, 10),
      'length_cm': 3.0,
      'width_cm': 2.0,
      'area_cm2': 6.0,
      'depth_cm': 0.4,
    });
    return c.id;
  }

  Future<String> newWound(String label) async {
    final w = await repo.createWound({
      'patient_id': patientId,
      'etiology': Etiologia.pieDiabetico.name,
      'body_location_primary': label,
    });
    return w.id;
  }

  test('detecta el borrador SIN TERMINAR de esta herida para HOY', () async {
    final woundId = await newWound('Talón (candado hoy)');
    final draftId = await addFollowUp(woundId, isDraft: true, daysAgo: 0);
    final found = repo.findOpenDraftForWound(woundId);
    expect(found?.id, draftId,
        reason: 'antes de crear otro, el candado debe encontrar el borrador de hoy');
  });

  test('un seguimiento FINALIZADO no cuenta como borrador abierto', () async {
    final woundId = await newWound('Talón (finalizado hoy)');
    await addFollowUp(woundId, isDraft: false, daysAgo: 0);
    expect(repo.findOpenDraftForWound(woundId), isNull,
        reason: 'una consulta finalizada no es un borrador sin terminar');
  });

  test('un borrador de OTRO día no dispara el candado (dos curaciones distintas)', () async {
    final woundId = await newWound('Talón (borrador de ayer)');
    await addFollowUp(woundId, isDraft: true, daysAgo: 1);
    expect(repo.findOpenDraftForWound(woundId), isNull,
        reason: 'el candado es por herida Y día: un borrador de ayer no es el de hoy');
  });

  test('el borrador de OTRA herida no se confunde con el de esta', () async {
    final woundA = await newWound('Herida A (candado)');
    final woundB = await newWound('Herida B (candado)');
    final draftA = await addFollowUp(woundA, isDraft: true, daysAgo: 0);
    expect(repo.findOpenDraftForWound(woundA)?.id, draftA);
    expect(repo.findOpenDraftForWound(woundB), isNull,
        reason: 'el candado no debe cruzar heridas');
  });

  test('excludeConsultationId omite el borrador que ya se está editando', () async {
    final woundId = await newWound('Talón (excluye propio)');
    final draftId = await addFollowUp(woundId, isDraft: true, daysAgo: 0);
    expect(
        repo.findOpenDraftForWound(woundId, excludeConsultationId: draftId), isNull,
        reason: 'reabrir el propio borrador no debe volver a preguntar por él');
  });

  // La pantalla usa la variante que REFRESCA antes (para ver un borrador de otro dispositivo). En la
  // demo (LocalStore) el refresh es no-op, pero el camino real de la pantalla queda cubierto.
  test('findOpenDraftForWoundRefreshed (el que usa la pantalla) detecta el borrador de hoy',
      () async {
    final woundId = await newWound('Talón (refreshed)');
    final draftId = await addFollowUp(woundId, isDraft: true, daysAgo: 0);
    final found = await repo.findOpenDraftForWoundRefreshed(woundId);
    expect(found?.id, draftId,
        reason: 'la variante con refresh debe detectar el mismo borrador que la síncrona');
  });
}
