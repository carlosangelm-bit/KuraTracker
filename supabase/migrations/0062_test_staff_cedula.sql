-- =============================================================================
-- 0062_test_staff_cedula.sql — Cédula de PRUEBA para carlos.angel@kuramas.com
-- =============================================================================
-- Para guardar notas de evolución, la app exige que el profesional en sesión
-- tenga un registro `staff` (ligado por profile_id) con `cedula_profesional`.
-- La cuenta carlos.angel@kuramas.com es de PRUEBA (jugar con "Paciente Prueba"),
-- así que se le asegura un registro staff con una cédula ficticia y evidente
-- ('PRUEBA-0000'): NO es una cédula real y no debe usarse en expedientes reales.
--
-- Idempotente: si ya hay staff ligado, sólo rellena la cédula cuando está vacía
-- (respeta un valor real si alguien lo puso después). Si no hay staff, lo crea
-- y lo liga al perfil.
-- =============================================================================

do $$
declare
  v_profile uuid;
  v_name    text;
  v_staff   uuid;
begin
  select id, full_name into v_profile, v_name
    from public.profiles
    where lower(email) = lower('carlos.angel@kuramas.com')
    limit 1;

  if v_profile is null then
    raise notice '0062: perfil carlos.angel@kuramas.com no encontrado; nada que hacer.';
    return;
  end if;

  select id into v_staff from public.staff where profile_id = v_profile limit 1;

  if v_staff is null then
    insert into public.staff
      (id, profile_id, folio, full_name, role_title, cedula_profesional, is_active)
    values (
      gen_random_uuid(),
      v_profile,
      'STAFF-' || substr(replace(v_profile::text, '-', ''), 1, 8),
      coalesce(v_name, 'Carlos Angel'),
      'Médico',
      'PRUEBA-0000',
      true
    );
    raise notice '0062: staff de prueba creado y ligado al perfil %.', v_profile;
  else
    update public.staff
      set cedula_profesional = 'PRUEBA-0000'
      where id = v_staff
        and (cedula_profesional is null or cedula_profesional = '');
    raise notice '0062: staff % ya existía; cédula de prueba asegurada.', v_staff;
  end if;
end $$;
