import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guardia de regresión de 0108 (huecos #2/#3, server-side). La lógica vive en
/// triggers de Postgres que NO corren en LocalStore, así que aquí solo se DETECTA
/// UN REVERT SILENCIOSO: si alguien afloja una de las dos puertas, su orden o el
/// cruce con perfil activo, este test se pone rojo y bloquea el deploy. La
/// verificación de comportamiento va en staging.
void main() {
  final m0108 = File(
          'supabase/migrations/0111_prevent_org_without_clinico.sql')
      .readAsStringSync();
  String flat(String s) => s.replaceAll(RegExp(r'\s+'), ' ');

  test('la función única cruza membresía activa Y perfil activo', () {
    final s = flat(m0108);
    expect(s, contains('function public.org_has_other_effective_clinico'));
    // Cruce con profiles.is_active: un perfil inactivo no cuenta como clínico.
    expect(s, contains('join public.profiles pr on pr.id = m.profile_id'));
    expect(s, contains('pr.is_active = true'));
    expect(s, contains("'clinico' = any(m.roles::text[])"));
  });

  test('puerta 1: trigger en membresías (update/delete), trg_zz_*', () {
    expect(m0108,
        contains('create trigger trg_zz_prevent_org_without_clinico'));
    expect(flat(m0108),
        contains('before update or delete on public.user_center_memberships'));
  });

  test('puerta 2: trigger en profiles al desactivar, trg_zz_*', () {
    expect(
        m0108,
        contains(
            'create trigger trg_zz_prevent_profile_deactivation_without_clinico'));
    expect(flat(m0108), contains('before update on public.profiles'));
    // Solo al desactivar (activo → inactivo).
    expect(flat(m0108), contains('old.is_active and not new.is_active'));
  });

  test('el mensaje de rechazo explica el motivo', () {
    expect(m0108, contains('sin personal sanitario'));
  });
}
