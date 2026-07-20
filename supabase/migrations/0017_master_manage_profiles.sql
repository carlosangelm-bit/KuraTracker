-- 0017_master_manage_profiles.sql
--
-- Gestión de usuarios y roles desde el área de Plataforma (master) y el
-- panel de Administración (admin de centro).
--
-- Hallazgo: las policies RLS de `profiles` (0003_row_level_security.sql) usan
-- SOLO public.is_admin(), que evalúa `role = 'admin'` — NO incluye al master
-- (ver is_admin() en 0002 e is_master() en 0012). 0012 agregó la rama
-- "or public.is_master()" a organizations/sites/staff/note_option_catalog,
-- pero NO a `profiles`. Consecuencia: hoy un master NO puede LISTAR ni EDITAR
-- otros perfiles desde la app (su SELECT/UPDATE sobre profiles ajenos es
-- rechazado por RLS), aunque el trigger anti-escalada (0012) sí lo permita a
-- nivel de columnas role/premium_enabled. Es decir, faltaba el permiso de
-- fila para el master.
--
-- Esta migración cierra esa brecha replicando el MISMO patrón de 0012:
-- agrega "or public.is_master()" a las 4 policies de `profiles`, sin filtro
-- de organización (el master es cross-centro por diseño). El admin de centro
-- ya podía gestionar perfiles (is_admin()), no cambia para él.
--
-- No afecta el trigger prevent_profile_privilege_escalation (0006/0012): ese
-- ya exceptúa a admin y master, así que el cambio de role/premium sigue
-- permitido solo a admin/master y bloqueado para un clínico normal.

drop policy if exists profiles_select_own_or_admin on public.profiles;
create policy profiles_select_own_or_admin on public.profiles
  for select using (id = auth.uid() or public.is_admin() or public.is_master());

drop policy if exists profiles_update_own_or_admin on public.profiles;
create policy profiles_update_own_or_admin on public.profiles
  for update using (id = auth.uid() or public.is_admin() or public.is_master());

drop policy if exists profiles_admin_insert on public.profiles;
create policy profiles_admin_insert on public.profiles
  for insert with check (public.is_admin() or public.is_master() or id = auth.uid());

drop policy if exists profiles_admin_delete on public.profiles;
create policy profiles_admin_delete on public.profiles
  for delete using (public.is_admin() or public.is_master());
