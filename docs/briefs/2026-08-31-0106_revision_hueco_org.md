# KuraTracker — Revisión de `0106`: correcto, pero un admin puede mudarse de centro

**Fecha:** 31-ago-2026 · **Rama:** `feat/membership-roles-seats-0106` (`68a508c`)
**Veredicto: no fusionar todavía.** Un cambio acotado y ya.

---

## 1. Lo que revisé y está bien

- **La pieza inferida es correcta.** Busqué específicamente el hueco de "adoptar los roles de
  un centro estando en otro": la línea `m.organization_id = new.organization_id` lo cierra. La
  igualdad de conjuntos por doble `<@` es la comparación adecuada.
- **El renombre `trg_zz` del `0105` es lo que la hace sólida.** Como el candado corre *después*
  del espejo, una escritura que solo toque el escalar `role` ya llega con `roles` derivado, así
  que la exención lo ve. Las dos piezas encajan.
- **El candado de `master` quedó a nivel superior**, aplica también a los admins, y compara
  ambas columnas.
- **`set_active_center`** copia el conjunto y conserva la validación de membresía activa.
- **`consumed_seats`** implementa la regla acordada.
- El backfill **no** replica el atajo `admin → clinico`. Correcto.

## 2. El hueco: el requisito de membresía solo aplica a los no-admin

La exención vive **dentro** de esta rama:

```sql
if not public.is_admin() and not public.is_master() then
  ...
  if new.roles is distinct from old.roles
     or new.organization_id is distinct from old.organization_id then
    if not exists ( ... membresía válida ... ) then raise exception ...
  end if;
end if;
```

**Un admin se salta el bloque completo.** Y nada más lo alcanza: el candado de `master` solo
mira el rol master; los otros triggers de `profiles`
(`trg_enforce_premium_requires_org_addon`, `trg_sync_profile_roles`, `trg_audit_profiles`) no
restringen la organización.

### Por qué eso es acceso entre inquilinos

`current_organization_id()` (`0011:189`) es literalmente:

```sql
select organization_id from public.profiles where id = auth.uid();
```

Es decir: **el alcance de inquilino de un usuario lo determina su propia fila.** Y
`profiles_update_own_or_admin` permite `id = auth.uid()` sin restricción de columnas. (No tiene
`with check` explícito, pero eso no ayuda: Postgres usa el `using` como `with check` por
defecto, y `id = auth.uid()` también se cumple en la fila nueva.)

Entonces:

> El administrador del centro A hace `PATCH /rest/v1/profiles?id=eq.<él mismo>` con
> `{"organization_id": "<centro B>"}`. Ahora `current_organization_id()` devuelve B, y
> `patients_select` —`is_admin() and organization_id = current_organization_id()`— le abre
> **los expedientes del centro B.**

No otorga `master`, así que el candado del `0104`/`0105` no lo ve. No es no-admin, así que la
exención del `0106` no lo ve. Sobrevive las tres migraciones.

Exposición hoy sigue siendo cero (los 4 admins son cuentas tuyas). Y sigue siendo exactamente
el escenario de centros externos: el admin de un cliente leyendo los expedientes de otro.

## 3. El arreglo

Que el requisito de membresía aplique a **todos salvo el master** (que no está atado a una
organización, ver la regla de oro del `0012`):

```sql
  -- premium: solo no-admin queda bloqueado (igual que hoy)
  if not public.is_admin() and not public.is_master() then
    if new.premium_enabled is distinct from old.premium_enabled then
      raise exception 'No autorizado: solo un administrador puede modificar premium_enabled';
    end if;
  end if;

  -- Centro/roles: exige membresía activa coincidente. Aplica a TODOS salvo master.
  if not public.is_master()
     and ( new.roles is distinct from old.roles
        or new.organization_id is distinct from old.organization_id ) then
    if not exists (
      select 1 from public.user_center_memberships m
      where m.profile_id = new.id
        and m.organization_id = new.organization_id
        and m.is_active = true
        and m.roles <@ new.roles and new.roles <@ m.roles
    ) then
      raise exception 'No autorizado: cambio de centro/roles sin membresía válida';
    end if;
  end if;
```

El efecto es una invariante limpia y fácil de razonar: **el centro activo y el conjunto de
roles de un perfil solo pueden reflejar una membresía que un admin o el master ya
concedieron.** El camino legítimo sigue siendo `set_active_center`.

## 4. Dos rutas legítimas que hay que verificar antes de fusionar

Este cambio es más restrictivo, así que puede romper flujos válidos. Revísalos:

1. **`create_organization_with_admin` (`0099`).** Actualiza el perfil del llamador con
   `roles = {admin}` y el nuevo `organization_id`. Es `SECURITY DEFINER`, pero `auth.uid()`
   sigue siendo el llamador, así que **el trigger dispara**. Si el RPC no crea también la
   membresía, el `raise` lo va a bloquear. **Arreglo: que el RPC inserte la membresía ANTES de
   actualizar el perfil.** Verifícalo; es la ruta de alta de centros del autoservicio.
2. **`setUserRoles` (§7 del `0106`).** Escribe la membresía y luego el perfil si es el centro
   activo. Con este cambio el orden **importa**: la membresía primero, el perfil después. Si
   está al revés, falla. Confírmalo en el código de la rama.
3. **`admin-create-user`** usa service role: el JWT no tiene `sub` de usuario, así que
   `auth.uid()` es null y el trigger retorna temprano (línea 1 de la función). No afectado —
   pero vale confirmarlo con una alta real en pruebas.

## 5. Nota menor, no bloqueante

Si un master concede a alguien una membresía con `master` en los roles, esa persona **no podrá
cambiarse a ese centro**: el candado de `master` (nivel superior, `not is_master()`) rechaza que
gane el rol. En la práctica no importa —el `master` se asigna en el perfil, no por membresía—
pero si algún día se quiere ese flujo, hay que preverlo.

## 6. Verificación adicional a la §8 del doc

Además de las tres consultas del doc, en la base de pruebas:

```
d) Con una cuenta ADMIN: intentar PATCH de su propio `organization_id` a otro centro.
   Esperado ANTES del arreglo: lo acepta. DESPUÉS: 'cambio de centro/roles sin membresía válida'.
e) Con esa misma cuenta admin: `set_active_center` a un centro donde SÍ tiene membresía.
   Esperado: funciona (es la ruta legítima).
f) Alta de un centro nuevo por `create_organization_with_admin`. Esperado: funciona
   (si falla, es el punto §4.1).
```

Y un test en la suite que afirme que el requisito de membresía **no** está dentro de la rama
`if not is_admin()` — es el revert silencioso que importa aquí.

## 7. Sobre `docs/`

Sí, copia los briefs del día al repo. Son documentos de trabajo del proyecto y su lugar es
junto al código que describen. Sugerencia de nombre: `docs/briefs/2026-08-31-*.md`, para que la
fecha ordene y se vea de un golpe qué se decidió cuándo.
