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

  test('TODAS las pantallas que eligen sitio para una paciente rutean por resolveSaveSite (sin lotería global)',
      () {
    // Enumeradas (Carlos, "arregla a todos los que tocan el dato"): las pantallas que fijan el sitio
    // de una consulta, un cobro, un consumo o el sitio principal del expediente.
    const screens = [
      'lib/features/follow_up/follow_up_capture_screen.dart',
      'lib/features/consultation/consultation_hub_screen.dart',
      'lib/features/patients/patient_form_screen.dart',
      'lib/features/insumos/consumo_screen.dart',
    ];
    for (final f in screens) {
      // Se ignoran las líneas de comentario (mencionan el patrón viejo a propósito): solo cuenta el
      // código.
      final code = File(f)
          .readAsLinesSync()
          .where((l) => !l.trimLeft().startsWith('//'))
          .join('\n');
      expect(code.contains('resolveSaveSite('), isTrue,
          reason: '$f debe resolver el sitio por la regla única resolveSaveSite');
      // La lotería del sitio: `sites.first` como default, o el primario sin validar `primarySiteId ??`.
      expect(code.contains('sites.first'), isFalse,
          reason: '$f no debe elegir/preseleccionar el sitio con sites.first (lotería)');
      expect(code.contains('primarySiteId ??'), isFalse,
          reason: '$f no debe usar el sitio primario sin validarlo contra el centro');
    }
  });
}
