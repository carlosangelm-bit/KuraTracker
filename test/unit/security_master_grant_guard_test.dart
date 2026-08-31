import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guardia de regresión del candado admin→master (0104 + 0105). La lógica vive
/// en triggers/policies de Postgres, que NO corren en LocalStore, así que no se
/// puede probar el rechazo real aquí (eso se verifica con las consultas §4.4 y
/// un intento de escalada en una BD de PRUEBAS). Lo que sí se puede —y es lo que
/// más importa dado el modelo de amenaza— es DETECTAR UN REVERT SILENCIOSO: si
/// alguien borra o afloja estas cláusulas, este test se pone rojo y bloquea el
/// deploy (el CI corre la suite).
void main() {
  final m0104 =
      File('supabase/migrations/0104_prevent_master_self_grant.sql')
          .readAsStringSync();
  final m0105 = File(
          'supabase/migrations/0105_master_grant_both_columns_trigger_order.sql')
      .readAsStringSync();
  String flat(String s) => s.replaceAll(RegExp(r'\s+'), ' ');

  test('el guard prohíbe master mirando AMBAS columnas (role y roles)', () {
    final s = flat(m0105);
    // Conjunto (roles) Y espejo escalar (role): escribir cualquiera queda cubierto.
    expect(
      s,
      contains(
          "('master'::public.user_role = any(new.roles)) <> ('master'::public.user_role = any(old.roles))"),
    );
    expect(
      s,
      contains(
          "(new.role = 'master'::public.user_role) <> (old.role = 'master'::public.user_role)"),
    );
    expect(m0105,
        contains('solo el master puede otorgar o retirar el rol master'));
  });

  test('el candado corre AL FINAL (trigger trg_zz_*, tras las derivaciones)', () {
    // El nombre viejo (que corría antes del sync) se elimina; queda el zz.
    expect(m0105,
        contains('drop trigger if exists trg_prevent_profile_privilege_escalation'));
    expect(m0105, contains('create trigger trg_zz_prevent_profile_privilege_escalation'));
  });

  test('candado equivalente en user_center_memberships (0104)', () {
    expect(m0104, contains('prevent_membership_master_grant'));
    expect(m0104, contains('trg_prevent_membership_master_grant'));
    expect(m0104,
        contains('solo el master puede asignar el rol master en una membresía'));
  });

  test('la policy de UPDATE de profiles acota al admin a su propia organización (0104)',
      () {
    expect(
      flat(m0104),
      contains(
          'public.is_admin() and organization_id = public.current_organization_id()'),
    );
  });

  // ---- 0106: roles por centro + asientos ----
  final m0106 =
      File('supabase/migrations/0106_membership_roles_and_seats.sql')
          .readAsStringSync();

  test('candado de membresía mira AMBAS columnas y corre AL FINAL (zz)', () {
    // Reemplaza el candado escalar del 0104 por uno que mira role Y roles.
    expect(m0106, contains('new_has_master'));
    expect(m0106, contains('old_has_master'));
    expect(m0106,
        contains('drop trigger if exists trg_prevent_membership_master_grant'));
    expect(m0106,
        contains('create trigger trg_zz_prevent_membership_master_grant'));
  });

  test('set_active_center copia el CONJUNTO de roles, no el escalar', () {
    final s = flat(m0106);
    expect(s, contains('select roles into v_roles'));
    expect(s, contains('roles = v_roles'));
    // No debe volver a escribir el escalar `role` directamente en el perfil.
    expect(s.contains('set organization_id = target_org, role = '), isFalse);
  });

  test('el switch legítimo sigue permitido: exención por membresía en el guard',
      () {
    // Un no-admin puede cambiar org+roles si coincide con una membresía activa.
    expect(m0106,
        contains('cambio de centro/roles sin membresía válida'));
    expect(flat(m0106),
        contains('m.roles <@ new.roles and new.roles <@ m.roles'));
  });
}
