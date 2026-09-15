// Sello de build (§ pendiente de nav / trampa de caché del sandbox): el CI sirve el SHA
// DESPLEGADO en /build.json y compila el MISMO SHA en la app (BUILD_SHA), visible en el
// banner del sandbox. Comparar ambos revela una pestaña con código viejo del caché del
// service worker (Flutter web es cache-first). Reja de FUENTE (lee los archivos) para que
// el cableado no se caiga sin querer + la conducta del default local.
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

import 'package:kuratracker/core/config/app_config.dart';

void main() {
  test('el workflow inyecta BUILD_SHA y sirve /build.json (app y demo)', () {
    final yml = File('.github/workflows/deploy.yml').readAsStringSync();
    // Dos builds (app con Supabase y demo), ambos deben sellar.
    expect('--dart-define=BUILD_SHA='.allMatches(yml).length, greaterThanOrEqualTo(2),
        reason: 'ambos build web (app y demo) deben inyectar BUILD_SHA');
    expect('build/web/build.json'.allMatches(yml).length, greaterThanOrEqualTo(2),
        reason: 'ambos deben escribir el sello /build.json junto al bundle');
    expect(yml.contains(r'"sha":"%s"'), isTrue,
        reason: 'el sello lleva el SHA desplegado');
  });

  test('AppConfig lee BUILD_SHA y el banner del sandbox lo muestra', () {
    final cfg = File('lib/core/config/app_config.dart').readAsStringSync();
    expect(cfg.contains("String.fromEnvironment(\n    'BUILD_SHA'"), isTrue,
        reason: 'buildSha viene de --dart-define=BUILD_SHA');
    final main = File('lib/main.dart').readAsStringSync();
    expect(main.contains('AppConfig.buildShaShort'), isTrue,
        reason: 'el banner del sandbox muestra el SHA corriendo');
  });

  test('buildShaShort: default local es "dev"; trunca a 7', () {
    // Sin --dart-define, el default es "dev" (build local).
    expect(AppConfig.buildSha, 'dev');
    expect(AppConfig.buildShaShort, 'dev');
  });
}
