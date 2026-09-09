import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:kuratracker/models/license_summary.dart';
import 'package:kuratracker/services/data_repository.dart';
import 'package:kuratracker/services/local_db/local_store.dart';

/// Panel de licencias (Fase 2): el resumen que ve el admin y los cinco estados.
LicenseSummary _summary({
  required int cUsed,
  required int cContracted,
  int aUsed = 0,
  int aContracted = 3,
  int caregivers = 0,
  int pUsed = 0,
  int pContracted = -1,
  String plan = 'basico',
  bool pastDue = false,
  int patients = 0,
}) =>
    LicenseSummary(
      clinicalSeats: LicenseCounter(used: cUsed, contracted: cContracted),
      adminSlots: LicenseCounter(used: aUsed, contracted: aContracted),
      caregivers: caregivers,
      protocolo: LicenseCounter(used: pUsed, contracted: pContracted),
      plan: plan,
      pastDue: pastDue,
      patientsUsed: patients,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('los cinco estados del panel', () {
    // Holgado: "4 de 5", 1 disponible.
    expect(_summary(cUsed: 4, cContracted: 5).state, LicenseState.holgado);
    // Lleno pero por debajo del techo (contratado < 5): aún cabe autoservicio.
    expect(_summary(cUsed: 3, cContracted: 3).state, LicenseState.lleno);
    // Techo del autoservicio: 5 de 5, ya no se compra solo.
    expect(_summary(cUsed: 5, cContracted: 5).state, LicenseState.techoAutoservicio);
    // Impago manda sobre todo.
    expect(_summary(cUsed: 4, cContracted: 5, pastDue: true).state,
        LicenseState.impago);
    // Plan gratuito es su propia etapa.
    expect(_summary(cUsed: 0, cContracted: 0, plan: 'gratuito').state,
        LicenseState.gratuito);
  });

  test('resumen calculado desde la semilla + solicitud auditada', () async {
    SharedPreferences.setMockInitialValues({});
    final store = await LocalStore.instance();
    final repo = await DataRepository.instance(); // siembra el demo

    // Un centro con derechos sembrados (seat:protocolo sólo lo tienen los Kura+).
    final ent = store.getAll(Collections.orgEntitlements).firstWhere(
        (e) => e['kind'] == 'seat' && e['key'] == 'protocolo');
    final orgId = ent['organization_id'] as String;

    final s = repo.licenseSummaryFor(orgId);
    // La semilla otorga module:admin (3 cupos) y seat:protocolo=10.
    expect(s.adminSlots.contracted, 3);
    expect(s.hasProtocoloAddon, isTrue);
    expect(s.protocolo.contracted, 10);
    // Con seat:clinico holgado (50), no está lleno → holgado.
    expect(s.clinicalSeats.full, isFalse);
    expect(s.state, LicenseState.holgado);

    // Solicitar más deja una fila auditada (no un derecho).
    final admin = repo.listUsers().firstWhere((u) => u.isAdmin);
    await repo.requestLicenses(
        organizationId: orgId, kind: 'seat_clinico', requestedQuantity: 3, by: admin);
    final reqs = store
        .getAll(Collections.licenseRequests)
        .where((r) => r['organization_id'] == orgId)
        .toList();
    expect(reqs, isNotEmpty);
    expect(reqs.first['status'], 'open');
    expect(reqs.first['requested_quantity'], 3);
  });
}
