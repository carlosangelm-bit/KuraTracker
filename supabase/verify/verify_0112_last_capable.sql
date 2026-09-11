-- =============================================================================
-- verify_0112_last_capable.sql — VERIFICACIÓN de la guardia "último con capacidad
-- de definir planes" (0111 + 0112). NO aplica nada: es una transacción que
-- termina en ROLLBACK. No deja datos, no altera el esquema ni el historial.
-- =============================================================================
-- CÓMO SE CORRE (lo hace el workflow sandbox-verify.yml contra el SANDBOX, como
-- usuario `postgres` del Session pooler → superusuario, RLS APAGADA para que un
-- WHERE que afecte 0 filas no se confunda con "no bloqueó"). Se ejecuta SIN
-- ON_ERROR_STOP: los casos que RECHAZAN imprimen su excepción y el script sigue;
-- cada uno vive en su propio SAVEPOINT para que un rechazo no tumbe a los demás.
--
-- CÓMO LEERLO: cada caso imprime su etiqueta con \echo. Debajo verás, del propio
-- Postgres:
--   • PERMITE → "UPDATE 1" / "DELETE 1" (confirma que afectó 1 fila, no 0).
--   • RECHAZA → "ERROR:  No autorizado: el centro se quedaría sin personal ...".
-- Compara caso por caso contra la tabla del brief. El caso 7 es el que con 0111
-- PASABA (bug) y con 0112 debe RECHAZAR.
--
-- INTERACCIÓN DE TRIGGERS (montaje): al INSERTAR el perfil B (role=admin,
-- roles='{}'), el trigger 0098 rellena roles→{admin,clinico} (gerencia clínica),
-- así que B es CAPAZ. La membresía de B se inserta con roles={admin} y el sync de
-- 0106 NO la rellena → queda SIN 'clinico'. Ese desajuste es justo lo que hacía
-- inerte a 0111. profile_can_define_plans lo confirma en el estado inicial.
--
-- AJUSTA los INSERT si tu esquema real tiene columnas NOT NULL que no están aquí;
-- no inventes columnas. Si no puedes garantizar el ROLLBACK, NO lo corras.
-- =============================================================================

begin;

-- UUIDs fijos del escenario (se revierten con el ROLLBACK final).
--   org = ...aa   A = ...a1 (clinico)   B = ...b1 (admin, capaz por rellenado)
insert into auth.users (id, instance_id, aud, role, email, encrypted_password, created_at, updated_at)
values
  ('00000000-0000-4000-a000-0000000000a1','00000000-0000-0000-0000-000000000000','authenticated','authenticated','verifyA@sandbox.invalid','',now(),now()),
  ('00000000-0000-4000-a000-0000000000b1','00000000-0000-0000-0000-000000000000','authenticated','authenticated','verifyB@sandbox.invalid','',now(),now());

insert into public.organizations (id, name, is_test)
values ('00000000-0000-4000-a000-0000000000aa','VERIFY 0112 (rollback)', true);

-- B con roles='{}' → 0098 lo rellena a {admin,clinico} (capaz por gerencia clínica).
insert into public.profiles (id, role, roles, full_name, email, is_active, organization_id)
values
  ('00000000-0000-4000-a000-0000000000a1','clinico', array['clinico']::public.user_role[], 'Verif A','verifyA@sandbox.invalid', true, '00000000-0000-4000-a000-0000000000aa'),
  ('00000000-0000-4000-a000-0000000000b1','admin',   '{}'::public.user_role[],             'Verif B','verifyB@sandbox.invalid', true, '00000000-0000-4000-a000-0000000000aa');

-- Membresías activas. La de B con roles={admin} (SIN clinico): 0106 no rellena.
insert into public.user_center_memberships (id, profile_id, organization_id, role, roles, is_active, created_at)
values
  (gen_random_uuid(),'00000000-0000-4000-a000-0000000000a1','00000000-0000-4000-a000-0000000000aa','clinico', array['clinico']::public.user_role[], true, now()),
  (gen_random_uuid(),'00000000-0000-4000-a000-0000000000b1','00000000-0000-4000-a000-0000000000aa','admin',   array['admin']::public.user_role[],   true, now());

\echo '=== ESTADO INICIAL (se espera capaz=t en A y en B) ==='
select p.id, p.role, p.roles, p.is_active,
       public.profile_can_define_plans(p.roles, p.role) as capaz
from public.profiles p
where p.id in ('00000000-0000-4000-a000-0000000000a1',
               '00000000-0000-4000-a000-0000000000b1')
order by p.id;

\echo ''
\echo '=== CASO 1: quitar clinico a A (B sigue capaz) → PERMITE (UPDATE 1) ==='
savepoint c1;
update public.profiles set roles = array['enfermeria']::public.user_role[]
  where id = '00000000-0000-4000-a000-0000000000a1';
rollback to savepoint c1;

\echo ''
\echo '=== CASO 2: B ya NO capaz, luego quitar clinico a A → RECHAZA (trigger profiles) ==='
savepoint c2;
update public.profiles set roles = array['admin']::public.user_role[]
  where id = '00000000-0000-4000-a000-0000000000b1';   -- B pierde capacidad (permitido: A capaz)
update public.profiles set roles = array['enfermeria']::public.user_role[]
  where id = '00000000-0000-4000-a000-0000000000a1';   -- <== debe RECHAZAR
rollback to savepoint c2;

\echo ''
\echo '=== CASO 3: B no capaz, desactivar la MEMBRESÍA de A → RECHAZA (trigger membresías) ==='
savepoint c3;
update public.profiles set roles = array['admin']::public.user_role[]
  where id = '00000000-0000-4000-a000-0000000000b1';
update public.user_center_memberships set is_active = false
  where profile_id = '00000000-0000-4000-a000-0000000000a1';   -- <== debe RECHAZAR
rollback to savepoint c3;

\echo ''
\echo '=== CASO 4: B no capaz, BORRAR la MEMBRESÍA de A → RECHAZA (trigger membresías, delete) ==='
savepoint c4;
update public.profiles set roles = array['admin']::public.user_role[]
  where id = '00000000-0000-4000-a000-0000000000b1';
delete from public.user_center_memberships
  where profile_id = '00000000-0000-4000-a000-0000000000a1';   -- <== debe RECHAZAR
rollback to savepoint c4;

\echo ''
\echo '=== CASO 5: B no capaz, desactivar el PERFIL de A → RECHAZA (trigger profiles, is_active) ==='
savepoint c5;
update public.profiles set roles = array['admin']::public.user_role[]
  where id = '00000000-0000-4000-a000-0000000000b1';
update public.profiles set is_active = false
  where id = '00000000-0000-4000-a000-0000000000a1';   -- <== debe RECHAZAR
rollback to savepoint c5;

\echo ''
\echo '=== CASO 6: B no capaz, BORRAR el PERFIL de A → RECHAZA POR CASCADA (FK ON DELETE CASCADE) ==='
savepoint c6;
update public.profiles set roles = array['admin']::public.user_role[]
  where id = '00000000-0000-4000-a000-0000000000b1';
delete from public.profiles
  where id = '00000000-0000-4000-a000-0000000000a1';   -- <== cascada borra membresía → RECHAZA
rollback to savepoint c6;

\echo ''
\echo '=== CASO 7 (EL DECISIVO): A ya NO capaz, desactivar el PERFIL de B → RECHAZA ==='
\echo '    B es capaz sólo por el rellenado; su MEMBRESÍA tiene roles={admin}. Con 0111 esto PASABA.'
savepoint c7;
update public.profiles set roles = array['enfermeria']::public.user_role[]
  where id = '00000000-0000-4000-a000-0000000000a1';   -- A pierde capacidad (permitido: B capaz)
update public.profiles set is_active = false
  where id = '00000000-0000-4000-a000-0000000000b1';   -- <== debe RECHAZAR
rollback to savepoint c7;

\echo ''
\echo '=== FIN: ROLLBACK (no se deja rastro) ==='
rollback;

-- Comprobación fuera de la transacción: la organización de prueba NO debe existir.
select 'org_de_prueba_restante=' || count(*) as limpieza
from public.organizations
where id = '00000000-0000-4000-a000-0000000000aa';
