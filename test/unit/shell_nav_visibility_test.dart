import 'package:flutter_test/flutter_test.dart';
import 'package:kuratracker/core/router/shell_nav_visibility.dart';

/// En /platform el único riel debe ser el de la consola (KuraNavRail): AppShell NO
/// pinta el suyo. Así, a cualquier ancho, existe exactamente UN riel y ninguna
/// etiqueta ("Plataforma") queda marcada como activa dos veces.
///
/// Conducta: dejar la tira externa (que AppShell muestre su nav en /platform) pone
/// esto en rojo — verificado revirtiendo appShellShowsOwnNav a `=> true`.
void main() {
  test('AppShell NO pinta su nav en /platform ni /admin (ni sus subrutas)', () {
    expect(appShellShowsOwnNav('/platform'), isFalse);
    expect(appShellShowsOwnNav('/platform/centros'), isFalse);
    expect(appShellShowsOwnNav('/platform/licencia'), isFalse);
    expect(appShellShowsOwnNav('/admin'), isFalse);
    expect(appShellShowsOwnNav('/admin/usuarios'), isFalse);
    expect(appShellShowsOwnNav('/admin/licencias'), isFalse);
  });

  test('AppShell SÍ pinta su nav en el resto de las rutas', () {
    expect(appShellShowsOwnNav('/'), isTrue);
    expect(appShellShowsOwnNav('/patients'), isTrue);
    expect(appShellShowsOwnNav('/import-export'), isTrue);
    expect(appShellShowsOwnNav('/caregiver'), isTrue);
  });
}
