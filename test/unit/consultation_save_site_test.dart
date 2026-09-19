// GUARDA (Carlos, 19-sep): el sitio con el que se GUARDA una consulta —y que hereda el cobro
// (charges.site_id, dinero)— no puede ser un sitio AJENO. Antes la consulta se creaba con el sitio
// primario de la paciente SIN validar y con `listSites().first` GLOBAL de respaldo (una lotería que
// podía estampar un sitio de OTRA organización). La regla única vive en DataRepository.resolveSaveSite:
// el primario SOLO si es un sitio activo del centro; si no, el primer sitio activo del centro; null si
// no hay. Dos partes: comportamiento (mira el sitio resultante) y fuente (las pantallas que crean
// consulta rutean por la regla, no por el patrón lotería).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kuratracker/services/data_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('resolveSaveSite — nunca estampa un sitio de otra organización', () {
    late DataRepository repo;
    late String orgA;
    late String siteA;
    late String orgB;
    late String siteB;

    setUp(() async {
      repo = await DataRepository.instance();
      final withSites = repo
          .listOrganizations()
          .where((o) =>
              repo.listSites(organizationId: o.id).any((s) => s.isActive))
          .toList();
      orgA = withSites[0].id;
      siteA =
          repo.listSites(organizationId: orgA).firstWhere((s) => s.isActive).id;
      orgB = withSites[1].id;
      siteB =
          repo.listSites(organizationId: orgB).firstWhere((s) => s.isActive).id;
    });

    test('primario del propio centro ⇒ ese sitio', () {
      expect(repo.resolveSaveSite(organizationId: orgA, patientPrimarySiteId: siteA),
          siteA);
    });

    test('primario de OTRO centro ⇒ un sitio del centro activo, NUNCA el ajeno', () {
      final r =
          repo.resolveSaveSite(organizationId: orgA, patientPrimarySiteId: siteB);
      expect(r, isNot(siteB),
          reason: 'no debe estampar el sitio de otra organización en la consulta/cobro');
      expect(repo.listSites(organizationId: orgA).map((s) => s.id), contains(r));
    });

    test('sin primario ⇒ primer sitio activo del centro (no un global)', () {
      final r =
          repo.resolveSaveSite(organizationId: orgA, patientPrimarySiteId: null);
      expect(repo.listSites(organizationId: orgA).map((s) => s.id), contains(r));
    });

    test('centro sin sitios ⇒ null (el guardado avisa, no estampa basura)', () {
      expect(repo.resolveSaveSite(organizationId: 'org-inexistente-xyz'), isNull);
    });
  });

  test('las pantallas que crean consulta rutean el sitio por resolveSaveSite (no la lotería global)',
      () {
    const screens = [
      'lib/features/follow_up/follow_up_capture_screen.dart',
      'lib/features/consultation/consultation_hub_screen.dart',
    ];
    for (final f in screens) {
      final src = File(f).readAsStringSync();
      expect(src.contains('resolveSaveSite('), isTrue,
          reason: '$f debe resolver el sitio del guardado por la regla única');
      // No debe quedar el patrón lotería `primarySiteId ?? (sites … .first)`.
      expect(RegExp(r'primarySiteId \?\? \(sites').hasMatch(src), isFalse,
          reason: '$f no debe caer a listSites().first global (sitio ajeno)');
    }
  });
}
