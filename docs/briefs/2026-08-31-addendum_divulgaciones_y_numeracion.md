# KuraTracker — Addendum: integridad del actor en `data_disclosures` + numeración

**Fecha:** 31-ago-2026 · **Base:** `main` en `3d6cd60`
**Para:** agente de desarrollo. Dos correcciones cortas, no bloquean la Fase 3.

---

## 1. El actor del registro es asertado por el cliente

`0101_data_disclosures.sql`:

```sql
actor_id uuid references auth.users(id),
...
create policy data_disclosures_insert on public.data_disclosures
  for insert with check (organization_id = public.current_organization_id());
```

La policy verifica la organización, pero **nada obliga a que `actor_id` sea quien realmente
llama.** El cliente manda `actor_id` y `actor_email` libremente.

En un registro cuyo propósito completo es "quién se llevó los datos", un campo de actor
falsificable es peor que no tenerlo: **se ve autoritativo y no lo es.** Un miembro del centro
puede registrar una exportación atribuida a un colega.

Es una combinación rara con lo que ya hiciste bien: las filas son **inmutables después** del
insert, pero el contenido **del** insert es palabra del cliente.

### Arreglo

Trigger `BEFORE INSERT` que **imponga** el actor, ignorando lo que venga del cliente:

```sql
create or replace function public.force_disclosure_actor()
returns trigger language plpgsql security definer
set search_path = public, pg_temp as $$
begin
  new.actor_id := auth.uid();
  new.actor_email := coalesce(
    (select email from public.profiles where id = auth.uid()),
    new.actor_email);          -- fallback: no perder el dato si no hay perfil
  return new;
end; $$;

create trigger trg_force_disclosure_actor
  before insert on public.data_disclosures
  for each row execute function public.force_disclosure_actor();
```

Con eso la app **ya no necesita mandar** `actor_id` ni `actor_email` — puede seguir
mandándolos y se ignoran. No rompe nada de lo desplegado.

**Nota de alcance, que no cambia:** esto endurece la *atribución* de los registros que sí se
escriben. No hace inevitable la escritura — sigue siendo un registro de uso legítimo, como
dice §4 de la spec. Que quien decide no dejar rastro pueda omitir el insert es distinto de que
pueda dejar un rastro falso; lo segundo sí se cierra aquí.

---

## 2. Numeración: la migración de membresías es `0102`, no `0101`

Estado real de `supabase/migrations/`:

```
0099_org_admin_roles_explicit.sql
0100_premium_requires_org_addon.sql
0101_data_disclosures.sql
```

El brief `KuraTracker_migracion_membresias_consolidada.md` propone la migración de
**roles-por-centro + asientos** como `0101`. Ese número ya está tomado. **Va como `0102`**
(o `0103` si el trigger de §1 se hace en migración propia, que es lo más limpio).

---

## 3. Recordatorio de lo que sigue pendiente para centros externos

El épico de entrega en carpetas avanzó cuatro despliegues. **Ninguno de los tres puntos que
bloquean a un centro externo se ha movido:**

1. **`center_type` en el formulario de alta** — hoy todo centro nuevo nace
   `clinica_heridas` por el default del `0040:27`. Un hospital externo nace mal tipificado y
   sus 23 políticas quedan inertes. Es un campo.
2. **Roles por centro + asientos** (`0102`) — `set_active_center` sigue sobreescribiendo el
   conjunto de roles desde un escalar de la membresía.
3. **`is_test`** en `profiles`, `organizations` y `patients`.

No es una crítica del trabajo de exportación —era necesario y quedó bien— pero conviene tener
presente que la pregunta original era la preparación para centros externos, y esos tres siguen
donde estaban.
