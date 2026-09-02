import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kuratracker/models/module_key.dart';

/// El CHECK de module_settings (0041) se quedó con 5 claves mientras el enum
/// ModuleKey creció a 8: apagar Insumos/Comercial/VAC contra Postgres lanzaba
/// una violación de constraint (23514) que la demo —sin constraints— no podía
/// detectar. 0107 amplió el CHECK a las 8. Este test cierra el ciclo: recorre
/// TODAS las claves del enum y exige que cada una aparezca en algún CHECK de
/// module_settings. Si mañana alguien agrega un noveno módulo al enum y olvida
/// ampliar el CHECK, este test se pone rojo ANTES de que el master reciba el
/// error en producción.
void main() {
  test('cada ModuleKey.dbValue está en el CHECK de module_settings', () {
    final migrations = Directory('supabase/migrations')
        .listSync()
        .whereType<File>()
        .where((f) => f.path.contains('module_settings'))
        .map((f) => f.readAsStringSync())
        .join('\n');

    expect(migrations, isNotEmpty,
        reason: 'No se encontró ninguna migración de module_settings.');

    for (final m in ModuleKey.values) {
      expect(
        migrations,
        contains("'${m.dbValue}'"),
        reason:
            'La clave "${m.dbValue}" del enum ModuleKey no está en ningún CHECK '
            'de module_settings. El master no podrá configurar ese módulo contra '
            'Postgres (violación de constraint). Amplía el CHECK en una migración.',
      );
    }
  });
}
