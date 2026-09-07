-- =============================================================================
-- rls_wound_vision_corrections_sandbox.sql
-- Prueba de RLS de public.wound_vision_corrections (capa 2 del motor de visión).
-- =============================================================================
-- QUÉ prueba (el camino de ESCRITURA, que es donde se esconde el bug silencioso):
--   1) staff ASIGNADO al paciente de la herida SÍ puede INSERTAR una corrección.
--   3) staff NO asignado NO puede insertar (RLS lo bloquea).           [0109]
--   4a) otro staff asignado, que NO es el autor, NO puede borrar la ajena.[0110]
--   4b) el AUTOR sí puede borrar la suya.                              [0110]
--   C1/C2) los CHECK de forma disparan (points vacío; 'otro' sin nota).[0109]
-- (Los escenarios 1-app y 2-huérfano -measurement_id NULL- se prueban en el
--  dispositivo: requieren la UI corriendo; esto cubre la capa de base + RLS.)
--
-- DÓNDE: editor SQL de Supabase, proyecto SANDBOX, con el seed sintético cargado.
-- NO deja datos: todo corre en un DO block que termina lanzando una excepción
-- para forzar el ROLLBACK. El RESULTADO llega COMO EL MENSAJE DE ESA EXCEPCIÓN
-- (el editor lo muestra). Es esperado ver un "error" rojo cuyo texto empieza con
-- "ROLLBACK INTENCIONAL" seguido del reporte PASS/FAIL. Eso significa éxito y que
-- no quedó basura. Si TODAS las líneas dicen PASS, la RLS está bien.
-- =============================================================================

do $$
declare
  v_wound      uuid;
  v_patient    uuid;
  v_author     uuid;  -- staff.id autor (asignado)
  v_author_uid uuid;  -- su profiles.id (= auth.uid())
  v_other      uuid;  -- staff.id de otro staff (lo asignamos abajo)
  v_other_uid  uuid;
  v_out        uuid;  -- staff.id NO asignado a este paciente
  v_out_uid    uuid;
  v_row        uuid;
  v_deleted    int;
  r            text := E'=== Test RLS wound_vision_corrections (sandbox) ===\n';
begin
  -- 0) Localizar entidades desde el seed. Herida cuyo paciente tenga staff asignado.
  select w.id, w.patient_id
    into v_wound, v_patient
  from public.wounds w
  join public.staff_patient_assignments spa on spa.patient_id = w.patient_id
  join public.staff s on s.id = spa.staff_id and s.profile_id is not null
  order by w.created_at
  limit 1;
  if v_wound is null then
    raise exception 'No hay herida con staff asignado. ¿Corriste el seed del sandbox?';
  end if;

  -- Autor: un staff asignado a ese paciente, con perfil.
  select s.id, s.profile_id into v_author, v_author_uid
  from public.staff s
  join public.staff_patient_assignments spa on spa.staff_id = s.id
  where spa.patient_id = v_patient and s.profile_id is not null
  order by s.id limit 1;

  -- Otro staff (no admin/master) con perfil, distinto del autor: lo ASIGNAREMOS.
  select s.id, s.profile_id into v_other, v_other_uid
  from public.staff s
  join public.profiles p on p.id = s.profile_id
  where s.profile_id is not null and s.id <> v_author
    and not ('admin'::public.user_role = any(p.roles))
    and not ('master'::public.user_role = any(p.roles))
  order by s.id limit 1;

  -- Staff NO asignado a este paciente (para el deny), distinto de autor y otro.
  select s.id, s.profile_id into v_out, v_out_uid
  from public.staff s
  join public.profiles p on p.id = s.profile_id
  where s.profile_id is not null
    and s.id <> v_author
    and s.id is distinct from v_other
    and not exists (select 1 from public.staff_patient_assignments a
                    where a.staff_id = s.id and a.patient_id = v_patient)
    and not ('admin'::public.user_role = any(p.roles))
    and not ('master'::public.user_role = any(p.roles))
  order by s.id limit 1;

  r := r || format('Entidades: wound=%s autor=%s otro=%s no_asignado=%s%s',
                   v_wound, v_author, v_other, v_out, E'\n');
  if v_author_uid is null then
    raise exception 'No hay staff asignado con perfil para actuar de autor.';
  end if;

  -- Asegurar que "otro" queda asignado (para el escenario 4). Rollback lo deshace.
  if v_other is not null then
    insert into public.staff_patient_assignments (staff_id, patient_id)
    values (v_other, v_patient) on conflict do nothing;
  end if;

  -- ---------------------------------------------------------------------------
  -- 1) INSERT permitido para el staff ASIGNADO (autor).
  perform set_config('request.jwt.claims',
    json_build_object('sub', v_author_uid::text, 'role', 'authenticated')::text, true);
  set local role authenticated;
  begin
    insert into public.wound_vision_corrections
      (wound_id, clinician_class, engine_version, calibration_mode, mm_per_px,
       rectified_size, points, created_by, created_by_role)
    values (v_wound, 'granulacion', 'test-rls', 'card', 0.25,
      '[1000,750]'::jsonb,
      '[{"x":10,"y":10,"engine_class":0,"lab":[50,0,0]}]'::jsonb,
      v_author_uid, 'clinico')
    returning id into v_row;
    r := r || format('PASS 1 · staff ASIGNADO insertó (id=%s)%s', v_row, E'\n');
  exception when others then
    r := r || format('FAIL 1 · staff asignado NO pudo insertar: %s%s', sqlerrm, E'\n');
  end;
  reset role;

  -- ---------------------------------------------------------------------------
  -- 3) INSERT denegado para el staff NO asignado.
  if v_out_uid is null then
    r := r || E'SKIP 3 · no hay staff NO asignado con perfil en el seed.\n';
  else
    perform set_config('request.jwt.claims',
      json_build_object('sub', v_out_uid::text, 'role', 'authenticated')::text, true);
    set local role authenticated;
    begin
      insert into public.wound_vision_corrections
        (wound_id, clinician_class, engine_version, points, created_by, created_by_role)
      values (v_wound, 'granulacion', 'test-rls',
        '[{"x":1,"y":1,"engine_class":0,"lab":[50,0,0]}]'::jsonb,
        v_out_uid, 'clinico');
      r := r || E'FAIL 3 · staff NO asignado LOGRÓ insertar (RLS no bloqueó).\n';
    exception
      when insufficient_privilege then
        r := r || E'PASS 3 · RLS bloqueó el INSERT del staff NO asignado.\n';
      when others then
        r := r || format('PASS? 3 · INSERT bloqueado con error inesperado: %s%s', sqlerrm, E'\n');
    end;
    reset role;
  end if;

  -- ---------------------------------------------------------------------------
  -- 4a) Otro staff ASIGNADO (no autor) NO puede borrar la corrección ajena.
  if v_row is null then
    r := r || E'SKIP 4 · no se creó la fila base (falló el paso 1).\n';
  elsif v_other_uid is null then
    r := r || E'SKIP 4a · no hay un segundo staff con perfil para probar autor-vs-no-autor.\n';
  else
    perform set_config('request.jwt.claims',
      json_build_object('sub', v_other_uid::text, 'role', 'authenticated')::text, true);
    set local role authenticated;
    delete from public.wound_vision_corrections where id = v_row;
    get diagnostics v_deleted = row_count;
    reset role;
    if v_deleted = 0 then
      r := r || E'PASS 4a · otro staff asignado NO borró la corrección ajena.\n';
    else
      r := r || format('FAIL 4a · otro staff BORRÓ corrección ajena (%s fila).%s', v_deleted, E'\n');
    end if;
  end if;

  -- 4b) El AUTOR sí puede borrar la suya.
  if v_row is not null then
    perform set_config('request.jwt.claims',
      json_build_object('sub', v_author_uid::text, 'role', 'authenticated')::text, true);
    set local role authenticated;
    delete from public.wound_vision_corrections where id = v_row;
    get diagnostics v_deleted = row_count;
    reset role;
    if v_deleted = 1 then
      r := r || E'PASS 4b · el autor SÍ borró la suya.\n';
    else
      r := r || format('FAIL 4b · el autor no pudo borrar la suya (%s filas).%s', v_deleted, E'\n');
    end if;
  end if;

  -- ---------------------------------------------------------------------------
  -- C1/C2) Los CHECK de forma disparan (como autor asignado, para pasar RLS).
  perform set_config('request.jwt.claims',
    json_build_object('sub', v_author_uid::text, 'role', 'authenticated')::text, true);
  set local role authenticated;
  begin
    insert into public.wound_vision_corrections
      (wound_id, clinician_class, engine_version, points, created_by)
    values (v_wound, 'granulacion', 'test-rls', '[]'::jsonb, v_author_uid);
    r := r || E'FAIL C1 · points vacío se aceptó (corr_points_shape no disparó).\n';
  exception
    when check_violation then r := r || E'PASS C1 · points vacío rechazado.\n';
    when others then r := r || format('PASS? C1 · rechazado con: %s%s', sqlerrm, E'\n');
  end;
  begin
    insert into public.wound_vision_corrections
      (wound_id, clinician_class, engine_version, points, created_by)
    values (v_wound, 'otro', 'test-rls',
      '[{"x":1,"y":1,"engine_class":0,"lab":[50,0,0]}]'::jsonb, v_author_uid);
    r := r || E'FAIL C2 · clinician_class=otro sin nota se aceptó.\n';
  exception
    when check_violation then r := r || E'PASS C2 · otro sin nota rechazado.\n';
    when others then r := r || format('PASS? C2 · rechazado con: %s%s', sqlerrm, E'\n');
  end;
  reset role;

  -- Forzar rollback: el reporte viaja como mensaje de esta excepción.
  raise exception E'ROLLBACK INTENCIONAL (no es un error real; no se dejaron datos).\n\n%', r;
end $$;
