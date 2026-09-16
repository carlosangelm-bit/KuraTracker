// El login estaba MUDO ante el error de Supabase (enlace de restablecimiento caducado/usado): el
// mensaje llegaba por query string y la pantalla no lo miraba, así que el usuario concluía que el
// producto estaba roto (defecto real en producción, primer uso del restablecimiento). Esta prueba
// fija la lectura contra la URL EXACTA de producción para que no vuelva a quedar muda.
import 'package:flutter_test/flutter_test.dart';
import 'package:kuratracker/features/auth/login_screen.dart' show authLinkErrorMessage;

/// Extrae los queryParameters tal como los ve go_router para una URL dada.
Map<String, String> _q(String url) => Uri.parse(url).queryParameters;

void main() {
  test('URL EXACTA de producción → dice que el enlace caducó/se usó', () {
    // https://app.kuramas.com/login?from=/?error=access_denied&error_code=otp_expired&error_description=...
    final q = _q(
        '/login?from=/?error=access_denied&error_code=otp_expired&error_description=Email+link+is+invalid+or+has+expired');
    final msg = authLinkErrorMessage(q);
    expect(msg, isNotNull);
    expect(msg, contains('caducó o ya se usó'));
  });

  test('todo anidado dentro de ?from= (params no promovidos arriba)', () {
    final q = {
      'from': '/?error=access_denied&error_code=otp_expired',
    };
    expect(authLinkErrorMessage(q), contains('caducó o ya se usó'));
  });

  test('access_denied sin error_code también se dice', () {
    expect(authLinkErrorMessage({'error': 'access_denied'}),
        contains('caducó o ya se usó'));
  });

  test('sin error → null (login normal, sin banner)', () {
    expect(authLinkErrorMessage(const {}), isNull);
    expect(authLinkErrorMessage(const {'from': '/dashboard'}), isNull);
  });

  test('otro error con descripción → se muestra la descripción', () {
    final msg = authLinkErrorMessage(
        const {'error_description': 'Something else went wrong'});
    expect(msg, 'Something else went wrong');
  });
}
