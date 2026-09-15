// §13.2 — Los diálogos/hojas se visten desde el TEMA (tokens), no en los ~87 sitios de
// llamada, para que cambien de color con el tipo de centro. El test de render (montar un
// AlertDialog bajo el tema real de un centro y leer el Material) es CI-only —KuraTheme.forType
// arrastra google_fonts— y resultó frágil; se cubre LOCAL con una reja de fuente que hace
// cumplir lo NO negociable: (a) el tema declara dialogTheme y bottomSheetTheme sacados de
// tokens; (b) los tres overrides locales que lo hacían a mano SE FUERON, así el tema es la
// única fuente. Lee los .dart → local y determinista.
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

String _read(String p) => File(p).readAsStringSync();

void main() {
  test('kura_theme declara dialogTheme y bottomSheetTheme desde tokens', () {
    final t = _read('lib/core/theme/kura_theme.dart');
    expect(t.contains('dialogTheme:'), isTrue);
    expect(t.contains('bottomSheetTheme:'), isTrue);
    // El diálogo sale de tokens (surface + borde), radio de tarjeta (mdR), sin tinte.
    final dialog = t.substring(t.indexOf('dialogTheme:'));
    expect(dialog.contains('backgroundColor: tokens.surface'), isTrue,
        reason: 'fondo desde token');
    expect(dialog.contains('side: BorderSide(color: tokens.border)'), isTrue,
        reason: 'borde desde token');
    expect(dialog.contains('borderRadius: AppRadii.mdR'), isTrue,
        reason: 'radio 16 (mdR), no el 28 de Material');
    expect(dialog.contains('surfaceTintColor: Colors.transparent'), isTrue,
        reason: 'sin tinte de elevación');
  });

  test('los tres overrides locales de diálogo se fueron (el tema es la única fuente)', () {
    const files = <String>[
      'lib/core/widgets/kura_module_lock.dart',
      'lib/features/platform/derechos/grant_entitlement_dialog.dart',
      'lib/features/admin/note_catalog_screen.dart',
    ];
    for (final f in files) {
      final src = _read(f);
      // Ya no debe fijar fondo/forma en el sitio de llamada del Dialog.
      expect(src.contains('backgroundColor: t.surface'), isFalse,
          reason: '$f todavía fija el fondo a mano');
      expect(
          RegExp(r'shape:\s*(const\s+)?RoundedRectangleBorder\(borderRadius: AppRadii\.mdR\)')
              .hasMatch(src),
          isFalse,
          reason: '$f todavía fija la forma a mano');
    }
  });
}
