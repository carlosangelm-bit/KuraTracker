# KuraTracker — Un admin de centro puede auto-promoverse a `master`

**Fecha:** 31-ago-2026 · **Base:** `main` en `9f53d7b`
**Va ANTES del `0104`.** El `0104` toca exactamente esta área; sin esto, la ensancha.
**Exposición hoy: cero** (los 4 admins son cuentas de Kura+, 3 de prueba). Esto es un
"arreglar antes del primer centro externo", no una emergencia.

---

## 1. La cadena

**(a) Policy de UPDATE sobre `profiles`** — última definición en `0017_master_manage_profiles.sql:30`:

```sql
create policy profiles_update_own_or_admin on public.profiles
  for update using (id = auth.uid() or public.is_admin() or public.is_master());
```

Cualquiera puede actualizar **su propia fila**. Y un admin puede actualizar **cualquier
fila de la base** — la policy no tiene restricción de organización.

**(b) El guard anti-escalada** — última definición en `0096_profile_roles_set.sql:100`:

```sql
if auth.uid() is not null and not public.is_admin() and not public.is_master() then
  if new.role is distinct from old.role
     or new.roles is distinct from old.roles
     or new.premium_enabled is distinct from old.premium_enabled then
    raise exception 'No autorizado: ...';
  end if;
end if;
```

Solo levanta excepción cuando el llamador **no** es admin. **Un admin pasa de largo.**

**(c) No hay nada más en el camino.** El único otro trigger sobre `profiles` en todas las
migraciones es `trg_profiles_updated_at` (`0002:62`). Y **ninguna migración prohíbe otorgar
`master` a nivel de base de datos**:

```
$ grep -rn "master" supabase/migrations/*.sql | grep -iE "raise|check \(|<> 'master'"
(solo restricciones de licencias premium y parámetros clínicos — ninguna sobre el rol)
```

La única validación que impide otorgar `master` vive en la Edge Function
`admin-create-user/index.ts:87` — es decir, **en el camino que usa la app, no en el
límite**.

## 2. La consecuencia

> Un usuario con `admin` en su conjunto de roles puede hacer un `PATCH` a
> `/rest/v1/profiles?id=eq.<él mismo>` con `{"roles": ["master"]}` y **la base lo acepta.**

`is_master()` se usa en ~133 políticas. Un master ve y administra **todas** las
organizaciones. Es decir: **el administrador de un centro cliente puede escalar a
administrador de plataforma y leer los expedientes de todos los demás centros.**

Que la UI no ofrezca ese botón es irrelevante: en una app Flutter Web la clave anon está en
el cliente, y cualquier usuario autenticado puede llamar a PostgREST directo. **La RLS
*es* el límite de seguridad de este sistema** — por eso existe.

## 3. Lo que verifiqué y lo que NO

**Verificado:** el texto de las políticas y del trigger vigentes en las migraciones, y la
ausencia de cualquier otro guard. Es una lectura del esquema, y es concluyente sobre lo que
las migraciones definen.

**NO hecho:** ejecutar la escalada. No tengo acceso a producción y no probaría una escalada
de privilegios contra una base clínica en vivo.

**Cómo confirmar sin arriesgar nada** — consulta de solo lectura, para verificar que
producción coincide con las migraciones:

```sql
-- a) La policy de UPDATE de profiles, tal como está en prod:
select policyname, cmd, qual
from pg_policies
where schemaname = 'public' and tablename = 'profiles' and cmd = 'UPDATE';
-- Esperado (el problema): qual contiene "is_admin()" sin condición de organización.

-- b) Los triggers vivos sobre profiles:
select tgname, tgenabled
from pg_trigger
where tgrelid = 'public.profiles'::regclass and not tgisinternal;
-- Esperado: solo trg_profiles_updated_at y trg_prevent_profile_privilege_escalation
--           y trg_sync_profile_roles. Ninguno restringe 'master'.

-- c) El cuerpo del guard, para confirmar que exime a los admins:
select pg_get_functiondef('public.prevent_profile_privilege_escalation'::regproc);
```

**No intentes la escalada en producción para comprobarlo.** Si quieres verlo funcionar, va
en una base de pruebas, no en la que tiene pacientes.

## 4. El arreglo (migración `0104`, junto con roles-por-centro)

### 4.1 Nadie otorga `master` salvo un master

```sql
create or replace function public.prevent_profile_privilege_escalation()
returns trigger language plpgsql security definer
set search_path = public, pg_temp as $$
begin
  if auth.uid() is null then return new; end if;   -- alta por trigger de Auth

  -- Un no-admin no cambia nada de esto (conducta original, intacta).
  if not public.is_admin() and not public.is_master() then
    if new.role is distinct from old.role
       or new.roles is distinct from old.roles
       or new.premium_enabled is distinct from old.premium_enabled then
      raise exception 'No autorizado: solo un administrador puede modificar role/roles o premium_enabled';
    end if;
  end if;

  -- NUEVO: el rol `master` solo lo otorga o retira un master.
  if not public.is_master()
     and ( ('master'::public.user_role = any(new.roles))
        <> ('master'::public.user_role = any(old.roles)) ) then
    raise exception 'No autorizado: solo el master puede otorgar o retirar el rol master.';
  end if;

  return new;
end; $$;
```

### 4.2 El mismo candado en `user_center_memberships`

`ucm_insert` / `ucm_update` (`0040:76-87`) permiten a **cualquier admin del centro** escribir
membresías de su organización, sin restricción sobre el valor del rol. Como el `0104` va a
hacer que `set_active_center` copie el conjunto de la membresía al perfil, **sin este candado
el `0104` abre una segunda ruta a lo mismo**: poner `roles = {master}` en su propia membresía
y cambiar de centro.

Trigger equivalente sobre `user_center_memberships`: `master` en los roles de una membresía
solo si quien escribe es master.

### 4.3 Acotar los UPDATE de admin a su propia organización

`profiles_update_own_or_admin` no tiene condición de organización: **el admin del centro A
puede modificar perfiles del centro B** (desactivarlos, cambiarles roles). Es un segundo
hueco, independiente del de `master`.

```sql
drop policy if exists profiles_update_own_or_admin on public.profiles;
create policy profiles_update_own_or_admin on public.profiles
  for update using (
    id = auth.uid()
    or public.is_master()
    or (public.is_admin() and organization_id = public.current_organization_id())
  );
```

**Cuidado al aplicarlo:** revisa que ninguna ruta legítima dependa de que un admin escriba
fuera de su organización — el alta de usuarios pasa por la Edge Function con service role, que
no está sujeta a RLS, así que no debería afectarla. Verifícalo antes de fusionar.

### 4.4 Verificación

```sql
-- Con una cuenta admin de prueba, intentar la escalada por PostgREST y confirmar
-- que la base la RECHAZA con el mensaje nuevo. En base de PRUEBAS, no en prod.
-- Y confirmar que un admin sigue pudiendo otorgar admin/clinico/enfermeria/cuidador
-- dentro de su organización.
```

Y un test en la suite (que ahora sí bloquea el deploy) que afirme que otorgar `master` desde
una cuenta admin falla.

## 5. Sobre las tres opciones que planteó el agente

- **"probablemente la que escribe la otra máquina"** — **no hay otra máquina.** El historial
  tiene dos identidades, ambas de Carlos (`carlosangelm-bit` y `Carlos Angel
  <carlosangelm@gmail.com>`), y los cambios que atribuyó a un tercero son commits del 23 de
  julio (`93addc4`, folios) y del 3 de agosto (`5b3586a`, master fuera de la demo, con mensaje
  explicando que cierra un backdoor del login en demo). Su copia de trabajo estaba un mes
  atrasada.
- **"'asientos' no tiene spec"** — sí la tiene:
  `KuraTracker_migracion_membresias_consolidada.md`, en la carpeta de Kuratracker de Carlos.
  Trae el esquema (`roles`, `seat_exempt`, `seats_contracted`), el trigger espejo,
  `set_active_center` reescrito, `consumed_seats`, y tres consultas de verificación. La
  *aplicación* del límite (rechazar altas al llenarse) queda deliberadamente fuera de ese
  documento y puede esperar: no hay centros externos todavía.
- **Ninguna de las tres opciones.** Va §4 de este documento, dentro del `0104`, y con el doc
  consolidado en mano para hacerlo de una sola vez.
