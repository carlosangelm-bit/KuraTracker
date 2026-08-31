import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guardia de regresión del candado admin→master (0104). La lógica vive en
/// triggers/policies de Postgres, que NO corren en LocalStore, así que no se
/// puede probar el rechazo real aquí (eso se verifica con las consultas §4.4 y
/// un intento de escalada en una BD de PRUEBAS). Lo que sí se puede —y es lo que
/// más importa dado el modelo de amenaza— es DETECTAR UN REVERT SILENCIOSO: si
/// alguien borra o afloja estas cláusulas, este test se pone rojo y bloquea el
/// deploy (el CI ahora corre la suite).
void main() {
  final sql =
      File('supabase/migrations/0104_prevent_master_self_grant.sql')
          .readAsStringSync();

  test('el guard prohíbe otorgar/retirar master salvo a un master', () {
    // La comparación XOR de pertenencia de master entre new/old.roles + el raise.
    expect(sql, contains("not public.is_master()"));
    expect(
      sql.replaceAll(RegExp(r'\s+'), ' '),
      contains(
          "('master'::public.user_role = any(new.roles)) <> ('master'::public.user_role = any(old.roles))"),
    );
    expect(sql, contains('solo el master puede otorgar o retirar el rol master'));
  });

  test('candado equivalente en user_center_memberships', () {
    expect(sql, contains('prevent_membership_master_grant'));
    expect(sql, contains('trg_prevent_membership_master_grant'));
    expect(sql,
        contains('solo el master puede asignar el rol master en una membresía'));
  });

  test('la policy de UPDATE de profiles acota al admin a su propia organización',
      () {
    final oneLine = sql.replaceAll(RegExp(r'\s+'), ' ');
    expect(
      oneLine,
      contains(
          'public.is_admin() and organization_id = public.current_organization_id()'),
    );
  });
}
