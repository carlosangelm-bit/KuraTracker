# KuraTracker — Migración consolidada: roles por centro + asientos de licencia

**Fecha:** 31-ago-2026 · **Base:** `main` en `a5f3b16` (§4 premium AND fusionado)
**Para:** agente de desarrollo
**Consolida** `KuraTracker_roles_por_centro_brief.md` y `KuraTracker_modelo_licencias_brief.md`
§2-§3 en **una sola migración**. Usa este documento; los otros dos quedan como antecedente.

---

## 0. Por qué es una sola migración

`user_center_memberships` necesita dos cosas a la vez:

- **`roles`** (conjunto), porque una persona tiene roles distintos por centro y hoy la
  columna es un solo valor.
- **el conteo de asientos**, que se calcula precisamente sobre ese conjunto (todo rol excepto
  `cuidador` consume 1 por persona por centro).

Hacerlas por separado obliga a escribir `consumed_seats` contra `m.role` escalar y
reescribirla después. Van juntas.

---

## 1. Contexto: los dos defectos que esto cierra

### (a) `set_active_center` sobreescribe el conjunto de roles

`supabase/migrations/0040_center_types_memberships.sql:188-191`

```sql
update public.profiles
set organization_id = target_org,
    role = v_role                  -- ← escalar, nunca `roles`
where id = auth.uid();
```

Nunca fue redefinida. Cae en el atajo de compat del `0098`
(`new.role is distinct from old.role` → `roles := {admin, clinico}` si es admin), y por eso:

| conjunto antes | membresía del destino | conjunto después |
|---|---|---|
| `{admin, clinico}` | `clinico` | `{clinico}` — **pierde admin** |
| `{clinico}` | `admin` | `{admin, clinico}` — **gana clínico fabricado** |
| `{clinico, enfermeria}` | `clinico` | `{clinico}` — pierde enfermería |

Verificado en datos: `maria.amaya@kuramas.com` tiene `roles_perfil = {clinico}` y
`rol_membresia = 'admin'` en dos centros. Al pararse ahí, el atajo le fabrica `clinico`.

**Por qué importa más en hospital:** post-Fase B las 23 políticas de escritura hospitalaria
gatean por `has_role('clinico')`. Una membresía **administrativa** en un centro tipo
`hospital` produce **escritura clínica a nivel de base de datos**. Eso es el hallazgo del
punto 7, vivo, por esta cuarta vía.

### (b) No hay dónde contar asientos

`profiles` tiene una fila por persona y un solo centro activo. Una persona con membresía en
tres centros aparece una vez. Contar desde ahí daría 1 en lugar de 3. El contrato es del
centro, así que la fuente tiene que ser la membresía.

---

## 2. Migración `0101` — esquema

```sql
-- 1) Roles como conjunto en la membresía.
alter table public.user_center_memberships
  add column if not exists roles public.user_role[] not null default '{}';

-- 2) Backfill SIN el caso especial de admin: la membresía dice lo que dice.
--    Si además atiende pacientes, se marca explícito después (ver §5).
update public.user_center_memberships
set roles = array[role]
where roles = '{}';

-- 3) Asientos: membresías que NO consumen licencia del centro.
alter table public.user_center_memberships
  add column if not exists seat_exempt boolean not null default false;

comment on column public.user_center_memberships.seat_exempt is
  'true = esta membresia NO consume licencia del centro. Dos casos: personal de '
  'plataforma (master) y personal de Kura+ prestando servicio dentro de un centro '
  'cliente (no debe ocupar un asiento que el cliente pago). Explicito, no inferido '
  'del rol: inferirlo del master cubre el primer caso pero no el segundo.';

-- 4) Capacidad contratada, en el centro.
alter table public.organizations
  add column if not exists seats_contracted integer;   -- null = sin limite (Kura+, contratos a la medida)
```

## 3. Trigger espejo en la membresía

Mismo patrón que `sync_profile_roles`, para que un writer legacy que toque `role` siga
funcionando durante la transición:

```sql
create or replace function public.sync_membership_roles()
returns trigger language plpgsql set search_path = public, pg_temp as $$
begin
  if tg_op = 'INSERT' then
    if new.roles is null or new.roles = '{}' then
      new.roles := array[new.role];          -- SIN el caso especial de admin
    else
      new.role := public.primary_role(new.roles);
    end if;
  else
    if new.roles is distinct from old.roles then
      new.role := public.primary_role(new.roles);
    elsif new.role is distinct from old.role then
      new.roles := array[new.role];          -- SIN el caso especial
    end if;
  end if;
  return new;
end; $$;

drop trigger if exists trg_sync_membership_roles on public.user_center_memberships;
create trigger trg_sync_membership_roles
  before insert or update of role, roles on public.user_center_memberships
  for each row execute function public.sync_membership_roles();
```

**Ojo:** aquí **no** se replica el atajo `admin → {admin, clinico}`. El atajo del `0098`
existe para no romper `handle_new_user`; en la membresía no hay writer equivalente que lo
necesite, y replicarlo reintroduciría el defecto que esta migración cierra.

## 4. `set_active_center` reescrito

```sql
-- Copia el CONJUNTO de la membresía al perfil. Nunca toca `role` directamente:
-- el trigger sync_profile_roles deriva el espejo. Con esto el atajo de compat
-- del 0098 deja de estar en la ruta del cambio de centro.
update public.profiles
set organization_id = target_org,
    roles = v_roles
where id = auth.uid();
```

Donde `v_roles` es el `roles` de la membresía validada (la función ya valida membresía activa
antes de escribir — conservar esa validación tal cual).

## 5. `consumed_seats`

```sql
create or replace function public.consumed_seats(p_org uuid)
returns integer language sql stable security definer
set search_path = public, pg_temp
as $$
  select count(*)::int
  from public.user_center_memberships m
  join public.profiles p on p.id = m.profile_id
  where m.organization_id = p_org
    and m.is_active
    and p.is_active
    and not m.seat_exempt
    and exists (select 1 from unnest(m.roles) r
                where r <> 'cuidador'::public.user_role);
$$;

comment on function public.consumed_seats(uuid) is
  'Licencias consumidas por un centro. Regla (Carlos, 31-ago-2026): la licencia es '
  'POR PERSONA y admite multiples roles al mismo costo; los cuidadores NO consumen. '
  'Se cuenta por persona POR CENTRO (el contrato es del centro), de ahi que la fuente '
  'sea la membresia y no profiles (que tiene una sola fila y un solo centro activo).';
```

Nota: `master` no queda exento automáticamente por esta función — se marca con `seat_exempt`
en su membresía. Deliberado (ver el comentario de la columna).

## 6. Datos: lo que hay que marcar después de migrar

Consulta para que Carlos decida qué marcar `seat_exempt` y qué membresías necesitan `clinico`
explícito:

```sql
select p.email, o.name, o.center_type, m.roles, m.seat_exempt
from public.user_center_memberships m
join public.profiles p on p.id = m.profile_id
join public.organizations o on o.id = m.organization_id
where m.is_active
order by o.name, p.email;
```

Casos conocidos hoy: `carlosangelm@procomsa.com.mx` (`{master}`) y las membresías de
`maria.amaya@kuramas.com` en centros que no son Kura+ → candidatas a `seat_exempt`.
**No lo apliques tú:** deja la consulta y que Carlos decida, son datos, no código.

## 7. App

- `setUserRoles` (punto 6 §1) debe escribir la **membresía del centro seleccionado**, no
  `profiles`. Hoy escribe el conjunto correcto en el lugar equivocado: el siguiente
  `set_active_center` lo sobreescribe.
- La UI de casillas edita la membresía; el perfil se actualiza como consecuencia del cambio
  de centro activo.
- Mostrar asientos usados / contratados en la pantalla del centro (master), para que un alta
  que va a fallar por límite se vea antes de intentarla.

## 8. Verificación

```sql
-- a) Ningún perfil pierde roles al cambiar de centro: correr set_active_center
--    ida y vuelta con una cuenta de prueba multirol y comparar `roles` antes/después.
-- b) El espejo es consistente en las dos tablas:
select 'profiles' t, count(*) from public.profiles
  where role is distinct from public.primary_role(roles)
union all
select 'memberships', count(*) from public.user_center_memberships
  where role is distinct from public.primary_role(roles);
-- Esperado: 0 en ambas.

-- c) Ninguna membresía ganó `clinico` en el backfill:
select count(*) from public.user_center_memberships
where role = 'admin'::public.user_role
  and 'clinico'::public.user_role = any(roles);
-- Esperado: 0 (el backfill NO replica el atajo).
```

## 9. Lo que sigue NO tocando

**No retirar el `case` de compat del `0098`.** Sigue sosteniendo `handle_new_user`
(`0011:173-181`), que inserta el profile con `role` desde `raw_user_meta_data` en todo alta de
cuenta. Después de esta migración quedará **un solo** writer legacy dependiendo de él, lo que
sí hace planeable su retiro — pero en otra ronda y con su propia verificación.
