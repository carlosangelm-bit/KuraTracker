import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guardia de regresión del candado de `/admin` (auditoría 1-sep, punto 1). En
/// web una URL no es candado: un `clinico` tecleando `/admin` abría el panel
/// completo (padrón de usuarios, toggles Premium, catálogo, marca). El fix son
/// DOS capas: el redirect del router y una guarda de rol dentro de la pantalla.
/// Estas capas son lógica de UI que no se ejercita en LocalStore, pero sí se
/// puede DETECTAR UN REVERT SILENCIOSO: si alguien afloja cualquiera de las dos,
/// este test se pone rojo y bloquea el deploy (el CI corre la suite).
void main() {
  String flat(String path) =>
      File(path).readAsStringSync().replaceAll(RegExp(r'\s+'), ' ');

  test('capa 1: el router redirige /admin a / si no es admin ni master', () {
    final router = flat('lib/core/router/app_router.dart');
    expect(
      router,
      contains("!canPurchase && location.startsWith('/admin')"),
      reason: 'El redirect de /admin desapareció: un clinico entraría por URL.',
    );
    // canPurchase = isAdmin || isMaster (definido arriba en el mismo redirect).
    expect(router, contains('final canPurchase = isAdmin || isMaster'));
  });

  test('capa 2: AdminHomeScreen tiene guarda de rol propia', () {
    final screen = flat('lib/features/admin/admin_home_screen.dart');
    expect(
      screen,
      contains('!sessionUser.isAdmin && !sessionUser.isMaster'),
      reason: 'La guarda de rol de la pantalla desapareció.',
    );
    expect(screen, contains('No tienes acceso a esta sección.'));
  });
}
