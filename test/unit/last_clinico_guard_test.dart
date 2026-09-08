import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:kuratracker/models/app_user.dart';
import 'package:kuratracker/services/data_repository.dart';

/// Invariante "el centro nunca se queda sin quien defina planes de cuidado"
/// (huecos #2 y #3, 8-sep). Un clínico EFECTIVO = membresía activa con 'clinico'
/// + perfil activo. Las dos puertas: quitar el rol (setUserRoles) y desactivar el
/// perfil (setUserActive). Ambas deben bloquear al ÚLTIMO clínico efectivo.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('setUserRoles bloquea quitar el ÚLTIMO clínico; permite si queda otro',
      () async {
    final repo = await DataRepository.instance();
    const org = 'org-test-roles';
    // El primer usuario del centro debe ser admin (regla de createUserWithLogin).
    final a = await repo.createUserWithLogin(
        email: 'a@t.mx',
        fullName: 'Dra A',
        roles: {AppRole.admin, AppRole.clinico},
        organizationId: org);
    final b = await repo.createUserWithLogin(
        email: 'b@t.mx',
        fullName: 'Dr B',
        roles: {AppRole.clinico},
        organizationId: org);

    // Quitar clínico a A: B sigue siendo clínico efectivo → permitido.
    await repo.setUserRoles(a.uid, {AppRole.admin}, organizationId: org);

    // Quitar clínico a B: sería el último del centro → BLOQUEA.
    expect(
      () => repo.setUserRoles(b.uid, {AppRole.enfermeria}, organizationId: org),
      throwsA(predicate((e) =>
          e.toString().contains('sin nadie que pueda definir planes'))),
    );
  });

  test('setUserActive bloquea desactivar al ÚLTIMO clínico efectivo', () async {
    final repo = await DataRepository.instance();
    const org = 'org-test-active';
    final a = await repo.createUserWithLogin(
        email: 'a2@t.mx',
        fullName: 'Dra A',
        roles: {AppRole.admin, AppRole.clinico},
        organizationId: org);
    final b = await repo.createUserWithLogin(
        email: 'b2@t.mx',
        fullName: 'Dr B',
        roles: {AppRole.clinico},
        organizationId: org);

    // Desactivar A: B sigue siendo clínico efectivo → permitido.
    await repo.setUserActive(a.uid, false);

    // Desactivar B: sería el último clínico efectivo → BLOQUEA.
    expect(
      () => repo.setUserActive(b.uid, false),
      throwsA(predicate((e) =>
          e.toString().contains('único personal') ||
          e.toString().contains('definir planes de cuidado'))),
    );
    // B sigue activo (el intento se rechazó antes de escribir).
    expect(repo.listUsers().firstWhere((u) => u.id == b.uid).isActive, isTrue);
  });

  test('reactivar (active=true) nunca bloquea', () async {
    final repo = await DataRepository.instance();
    const org = 'org-test-reactivar';
    final a = await repo.createUserWithLogin(
        email: 'a3@t.mx',
        fullName: 'Dra A',
        roles: {AppRole.admin, AppRole.clinico},
        organizationId: org);
    // Activar de nuevo no valida la invariante (solo la pérdida la rompe).
    await repo.setUserActive(a.uid, true);
    expect(repo.listUsers().firstWhere((u) => u.id == a.uid).isActive, isTrue);
  });
}
