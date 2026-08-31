# KuraTracker — El `0104` no cierra la escalada: la ruta del espejo escalar sigue abierta

**Fecha:** 31-ago-2026 · **Base:** `main` en `5548c31`
**Va antes del `0105`.** Es un cambio de tres líneas.

---

## 1. El orden de disparo de los triggers

Postgres dispara los triggers `BEFORE` de una tabla **en orden alfabético por nombre**. Los
`BEFORE UPDATE` sobre `profiles`, en ese orden, son:

```
1. trg_enforce_premium_requires_org_addon
2. trg_prevent_profile_privilege_escalation   ← el candado del 0104
3. trg_profiles_updated_at
4. trg_sync_profile_roles                     ← el que deriva roles desde role
```

("prevent" < "profiles" < "sync": comparación de cadenas, `e` < `o`, `p` < `s`.)

**El candado corre ANTES de que `roles` se derive del escalar.**

## 2. La consecuencia

El candado del `0104` solo inspecciona el conjunto:

```sql
if not public.is_master()
   and ( ('master'::public.user_role = any(new.roles))
      <> ('master'::public.user_role = any(old.roles)) ) then
  raise exception 'No autorizado: solo el master puede otorgar o retirar el rol master.';
end if;
```

Si un admin escribe **solo el escalar** — `PATCH /rest/v1/profiles?id=eq.<él mismo>` con
`{"role": "master"}` — entonces en el momento en que corre el candado:

- `new.roles` **es igual** a `old.roles` (nadie lo tocó) → el XOR es falso → **no levanta
  excepción**.
- La rama de no-admin, que sí compara `new.role is distinct from old.role`, se salta porque
  el llamador **es** admin.

Y después corre `trg_sync_profile_roles`, cuya rama de UPDATE (`0098`) hace:

```sql
elsif new.role is distinct from old.role then
  new.roles := array[new.role];    -- → {master}
```

**Resultado: la auto-promoción admin → master sigue siendo posible, escribiendo `role` en
lugar de `roles`.** El `0104` cerró la puerta y dejó la ventana.

## 3. El arreglo mínimo (tres líneas)

El candado tiene que mirar **las dos columnas**:

```sql
if not public.is_master()
   and ( ('master'::public.user_role = any(new.roles))
      <> ('master'::public.user_role = any(old.roles))
     or (new.role = 'master'::public.user_role)
      <> (old.role = 'master'::public.user_role) ) then
  raise exception 'No autorizado: solo el master puede otorgar o retirar el rol master.';
end if;
```

## 4. El arreglo estructural (recomendado además del anterior)

Depender de "acordarse de todas las columnas de entrada" es frágil — es exactamente el error
que produjo esto. La forma robusta es que **el candado valide el estado final**, después de que
las derivaciones ya corrieron. Se consigue con el nombre:

```sql
drop trigger if exists trg_prevent_profile_privilege_escalation on public.profiles;
create trigger trg_zz_prevent_profile_privilege_escalation
  before update on public.profiles
  for each row execute function public.prevent_profile_privilege_escalation();
```

Con `zz_` el candado corre al final, después de `trg_sync_profile_roles`, y ve los valores
definitivos. La rama de no-admin sigue funcionando igual (después del sync, ambas columnas
aparecen cambiadas, así que sigue rechazando).

**Haz los dos.** El de §3 corrige el agujero ya; el de §4 evita que la próxima columna
derivada lo reabra.

## 5. Lo mismo aplica al candado de membresías

`prevent_membership_master_grant` (`0104:58`) revisa hoy el escalar `role` de la membresía, que
es lo único que existe. Cuando el `0105` agregue `roles` **y su trigger espejo**, se reproduce
exactamente esta situación al revés: el candado mirará el escalar y la escritura podrá venir por
el conjunto.

**Regla para el `0105`: el candado de membresías revisa AMBAS columnas, y su trigger se nombra
para correr después del espejo** (`trg_zz_prevent_membership_master_grant`).

## 6. Para `CLAUDE.md`

Vale dejarlo escrito, porque no es obvio y ya costó una iteración:

> **Orden de triggers.** Postgres dispara los `BEFORE` en orden alfabético por nombre de
> trigger. Un candado llamado `trg_prevent_*` corre **antes** que una derivación llamada
> `trg_sync_*`, así que valida la entrada cruda y no el estado final. Los triggers de
> validación se nombran `trg_zz_*` para que corran al final, y comparan **todas** las columnas
> que representan el mismo dato (p. ej. `role` y `roles`).

## 7. Sobre el doc consolidado que el agente no encuentra

No está en el repo: está en OneDrive. Pero **el agente corre en tu máquina**, así que puede
leerlo directo:

```
/Users/carlosangel/Library/CloudStorage/OneDrive-ProgramaciónComercialAplicadaS.A.deC.V/Documentos/Claude/Projects/Kuratracker/KuraTracker_migracion_membresias_consolidada.md
```

Ha estado buscando en el repositorio. Ahí también están todos los demás briefs del día.

**Y la solución durable:** commitear estos documentos al repo, en `docs/`. Con eso el agente
los tiene siempre, quedan versionados junto al código que describen, y dejamos de perder un
turno por documento.
