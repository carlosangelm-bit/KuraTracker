// §10.1 (reja): NINGUNA pantalla migrada monta un FAB CRUDO. Tras el spec «la acción
// principal sale de los flotantes», cada FAB o (a) subió al encabezado como acción de
// sección/pantalla y solo se pinta SIN riel detrás de una guardia (`rail ? null :`,
// `showFab ? … : null`, `!hasNavRail(...) &&`), o (b) —el checkout de Reabasto, §8.2— se
// fue a una barra de acción inferior. En ningún caso queda `floatingActionButton:
// KuraPrimaryFab(...)` ni `floatingActionButton: FloatingActionButton(...)` SIN guardia.
//
// Es una reja de FUENTE (lee los .dart, no compila) → corre localmente pese a google_fonts.
// Si una pantalla nueva vuelve a poner un FAB crudo, este test lo caza.
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

/// Las pantallas del alcance (§7 + Reabasto §8.2). El riel las alcanza en escritorio.
const _targets = <String>[
  'lib/features/admin/users_screen.dart',
  'lib/features/admin/staff_screen.dart',
  'lib/features/admin/sites_screen.dart',
  'lib/features/agenda/agenda_screen.dart',
  'lib/features/comercial/comercial_screen.dart',
  'lib/features/dashboard/dashboard_screen.dart',
  'lib/features/patients/patient_labs_screen.dart',
  'lib/features/patients/patients_list_screen.dart',
  'lib/features/platform/platform_home_screen.dart',
  'lib/features/vac/vac_therapies_screen.dart',
  'lib/features/insumos/reabasto_screen.dart',
];

/// `floatingActionButton:` seguido (con espacios/saltos) DIRECTO de un FAB constructor. Es
/// el patrón «crudo»: sin un ternario/condición de guardia entre medias. Un FAB guardado se
/// ve como `floatingActionButton: rail ? null : KuraPrimaryFab(` — ahí lo que sigue a los
/// dos puntos es la CONDICIÓN, no el constructor, así que no casa.
final _rawFab = RegExp(
  r'floatingActionButton:\s*(KuraPrimaryFab|FloatingActionButton)\s*[.(]',
);

void main() {
  test('ninguna pantalla del alcance monta un FAB crudo (sin guardia)', () {
    final offenders = <String>[];
    for (final path in _targets) {
      final file = File(path);
      expect(file.existsSync(), isTrue, reason: 'no existe $path');
      final src = file.readAsStringSync();
      final m = _rawFab.firstMatch(src);
      if (m != null) offenders.add('$path → «${m.group(0)}»');
    }
    expect(offenders, isEmpty,
        reason: 'FAB crudo (debe ir tras guardia de riel o a barra inferior):\n'
            '${offenders.join('\n')}');
  });

  test('Reabasto cerró el checkout en barra inferior, no en FAB (§8.2)', () {
    final src = File('lib/features/insumos/reabasto_screen.dart').readAsStringSync();
    expect(src.contains('KuraBottomActionBar'), isTrue,
        reason: 'el checkout debe usar la barra de acción inferior de la casa');
    expect(src.contains('FloatingActionButton'), isFalse,
        reason: 'ya no debe quedar ningún FloatingActionButton en Reabasto');
  });
}
