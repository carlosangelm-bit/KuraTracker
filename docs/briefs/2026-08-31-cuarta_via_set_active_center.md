# KuraTracker — Cuarta vía legacy: `set_active_center` sobreescribe el conjunto de roles

**Fecha:** 31-ago-2026 · **Base:** `main` en `22b74c1` (puntos 5, 6, 7 y Fases A/B en prod)
**Estado:** hallazgo nuevo, en producción. **Bloquea el retiro del `case` de compat del `0098`.**

---

## 1. Verificación del punto 6 — correcto

- `isRestrictedNurse = hasRole(enfermeria) && !canDiagnose && !isAdmin && !isMaster`
  (`app_user.dart:97`) e `isCaregiverOnly = hasRole(cuidador) && effectiveRoles.length == 1`
  (`:103`). Es la forma de §0 del brief, bien aplicada.
- `risk_board:119` no se migró y quedó comentado. Correcto.
- `setUserRoles` escribe `roles` (`data_repository.dart:406`), llamado desde
  `admin_home_screen.dart:302`. Tercera vía cerrada.
- El insert de `data_repository.dart:492` escribe **ambos** y es solo modo demo
  (`LocalStore`, sin trigger). Está bien así.

---

## 2. El hallazgo: `set_active_center` (migración `0040`)

`supabase/migrations/0040_center_types_memberships.sql:188-191`

```sql
update public.profiles
set organization_id = target_org,
    role = v_role                  -- ← escalar, nunca `roles`
where id = auth.uid();
```

Nunca fue redefinida por una migración posterior. Se llama en producción desde
`data_repository.dart:setActiveCenter` → `store.callRpc('set_active_center', ...)`.

`v_role` viene de la membresía del usuario en el centro destino
(`user_center_memberships.role`, que es **un solo rol**, no un conjunto).

### Por qué es peor que las tres vías anteriores

Las tres que cerramos **añadían** `clinico` sin que nadie lo pidiera. Esta, además,
**borra roles**. Al caer en la rama de compat del trigger:

| conjunto antes | membresía del centro destino | conjunto después |
|---|---|---|
| `{admin, clinico}` | `clinico` | **`{clinico}`** — pierde admin |
| `{clinico}` | `admin` | **`{admin, clinico}`** — gana clínico sin pedirlo |
| `{admin}` | `admin` | **`{admin, clinico}`** — el atajo de siempre |
| `{clinico, enfermeria}` | `clinico` | **`{clinico}`** — pierde enfermería |

O sea: **cada cambio de centro reescribe el conjunto de roles completo desde un solo
valor.** Ahora que `roles` es la autoridad, esto no es una fuga del atajo: es una pérdida
de datos silenciosa.

### Por qué retirar el `case` de compat NO lo arregla

Si se quita el `admin → {admin, clinico}` del trigger, la tabla de arriba queda:

| conjunto antes | membresía | conjunto después |
|---|---|---|
| `{admin, clinico}` | `admin` | **`{admin}`** — sigue perdiendo clínico |

El clobber es del `update`, no del atajo. Retirar el `case` cambia *qué* se pierde, no
que se pierda.

---

## 3. La raíz es de modelo, no de código

`user_center_memberships.role` es **un solo rol por centro**. La pregunta de producto:

> **¿El conjunto de roles de una persona varía por centro?**

Es un caso real: la Mtra. María podría ser `{admin, clinico}` en Kura+ y `{clinico}` en un
centro cliente donde solo atiende. Si la respuesta es sí —y creo que sí— entonces
`user_center_memberships` necesita `roles` (conjunto), igual que `profiles`, y
`set_active_center` debe copiar ese conjunto:

```sql
update public.profiles
set organization_id = target_org,
    roles = v_roles          -- conjunto de la membresía; el trigger deriva `role`
where id = auth.uid();
```

Si la respuesta fuera no (los roles son de la persona, no del centro), entonces
`set_active_center` **no debe tocar el rol en absoluto** — solo `organization_id` — y la
columna `role` de la membresía se deprecia.

**Cualquiera de las dos salidas es correcta; la mezcla actual no lo es.** Y la decisión
la toma Carlos, no el código.

---

## 4. Urgencia: depende de un dato que no tengo

El impacto real depende de cuántas personas tienen más de una membresía. Consulta de solo
lectura, para Carlos:

```sql
select p.email, p.roles, count(*) as membresias
from public.user_center_memberships m
join public.profiles p on p.id = m.profile_id
where m.is_active
group by p.email, p.roles
having count(*) > 1
order by 3 desc;
```

- **Cero filas** → nadie puede disparar el clobber hoy. Queda como deuda a pagar antes
  del segundo centro, no urgente. Muy probable, dado que solo existe una organización.
- **Alguna fila** → esas personas pierden roles cada vez que cambian de centro, y hay que
  arreglarlo antes de seguir.

---

## 5. Respuesta a "¿retiramos el atajo del trigger?"

**No todavía.** El `case` de compat es hoy la red que sostiene dos writers legacy:

1. `set_active_center` (§2) — producción, y con el problema de fondo de §3.
2. `handle_new_user` (`0011:173-181`) — el trigger de Auth inserta el profile con `role`
   desde `raw_user_meta_data` y **nunca** escribe `roles`. Dispara en **todo** alta de
   cuenta, incluida la de `admin-create-user` (que pasa `user_metadata: { role: primaryRole }`
   en `index.ts:149` y corrige el conjunto en el upsert posterior).

Sobre el punto 2, ojo con la precisión de lo que se retira: **la derivación `role → roles`
debe quedarse**; lo único retirable es el caso especial `admin → {admin, clinico}`. Si se
quita la derivación completa, `handle_new_user` deja perfiles en `roles = '{}'`, el trigger
calcula `primary_role('{}') = null` y el insert **falla** contra `role not null` del `0001`.
Falla ruidosamente, que es lo bueno, pero rompe todo alta de cuenta.

## 6. Sobre el punto 8

Sigue siendo de baja prioridad, y ahora con una razón más: el `check
(array_length(roles,1) >= 1)` es compatible con el `default '{}'` porque el trigger
`BEFORE INSERT` rellena antes de que se evalúe el check. No hay conflicto — pero tampoco
hay hueco que tape, porque `role not null` ya impide el conjunto vacío de facto.
Hazlo cuando toque tocar esa tabla por otra razón.
