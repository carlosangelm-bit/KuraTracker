import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:kuratracker/models/app_user.dart';
import 'package:kuratracker/services/data_repository.dart';

/// Hueco #2 (8-sep, decisión de Carlos: BLOQUEAR). setUserRoles no debe dejar a
/// un centro sin NINGÚN usuario con rol clínico — nadie podría definir planes de
/// cuidado. Solo bloquea al QUITAR el último 'clinico'; no estorba en centros que
/// nunca tuvieron clínico.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('bloquea quitar el ÚLTIMO clínico del centro; permite si queda otro',
      () async {
    final repo = await DataRepository.instance();
    // Centro y usuarios ficticios: con organizationId explícito, setUserRoles
    // solo hace UPSERT de membresía (no toca perfiles), así que quedan aislados.
    const org = 'org-test-last-clinico';

    await repo.setUserRoles('u-a', {AppRole.admin, AppRole.clinico},
        organizationId: org);
    await repo.setUserRoles('u-b', {AppRole.admin, AppRole.clinico},
        organizationId: org);

    // Quitar clínico a A: B sigue siendo clínico → permitido.
    await repo.setUserRoles('u-a', {AppRole.admin}, organizationId: org);

    // Quitar clínico a B: sería el último del centro → BLOQUEA.
    expect(
      () => repo.setUserRoles('u-b', {AppRole.admin}, organizationId: org),
      throwsA(predicate((e) =>
          e.toString().contains('sin nadie que pueda definir planes'))),
    );

    // B sigue con clínico (el intento se rechazó antes de escribir).
    final memB = repo
        .listMembershipsForOrg(org)
        .firstWhere((m) => m.profileId == 'u-b');
    expect(memB.roles.contains(AppRole.clinico), isTrue);
  });

  test('no estorba un alta admin en un centro que nunca tuvo clínico', () async {
    final repo = await DataRepository.instance();
    const org = 'org-test-solo-admin';
    // Alta de un admin sin clínico en un centro vacío: NO debe bloquear.
    await repo.setUserRoles('u-solo', {AppRole.admin}, organizationId: org);
    final mems = repo.listMembershipsForOrg(org);
    expect(mems.any((m) => m.profileId == 'u-solo'), isTrue);
  });
}
