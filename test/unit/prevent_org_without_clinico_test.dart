import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guardia de regresión de 0111 (huecos #2/#3, server-side). La lógica vive en
/// triggers de Postgres que NO corren en LocalStore; aquí solo se DETECTA UN
/// REVERT SILENCIOSO. La capacidad de definir planes la decide el PERFIL (con el
/// rellenado de gerencia clínica admin→{admin,clinico}), no la membresía. La
/// verificación de comportamiento va en staging (6 casos).
void main() {
  // La corrección basada en PERFIL vive en 0112 (0111 es inmutable porque ya se
  // aplicó en staging; 0112 lo reemplaza). El estado final que se verifica es 0112.
  final m0111 = File(
          'supabase/migrations/0112_capable_clinico_by_profile.sql')
      .readAsStringSync();
  String flat(String s) => s.replaceAll(RegExp(r'\s+'), ' ');

  test('la capacidad se lee del PERFIL con rellenado admin, no de la membresía',
      () {
    final s = flat(m0111);
    expect(s, contains('function public.profile_can_define_plans'));
    // Rellenado de gerencia clínica: roles vacío + role admin ⇒ capaz.
    expect(s, contains("p_role::text in ('admin', 'clinico')"));
    expect(s, contains("'clinico' = any(p_roles::text[])"));
    // El conteo cruza membresía activa Y perfil activo, y usa la capacidad.
    expect(s, contains('join public.profiles pr on pr.id = m.profile_id'));
    expect(s, contains('public.profile_can_define_plans(pr.roles, pr.role)'));
  });

  test('puerta 1: membresía (pertenencia) en update/delete, trg_zz_*', () {
    expect(
        m0111,
        contains(
            'create trigger trg_zz_prevent_membership_removes_last_capable'));
    expect(flat(m0111),
        contains('before update or delete on public.user_center_memberships'));
  });

  test('puerta 2: perfil (capacidad) en update, trg_zz_*', () {
    expect(m0111,
        contains('create trigger trg_zz_prevent_profile_removes_last_capable'));
    expect(flat(m0111), contains('before update on public.profiles'));
    // Cubre perder la capacidad O desactivar el perfil (compara antes/después).
    expect(m0111, contains('v_was'));
    expect(m0111, contains('v_now'));
  });

  test('el mensaje de rechazo explica el motivo', () {
    expect(m0111, contains('sin personal sanitario'));
  });
}
