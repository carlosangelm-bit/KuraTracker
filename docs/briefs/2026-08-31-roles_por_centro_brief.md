# KuraTracker — Los roles son POR CENTRO. `profiles.roles` es una caché, no la autoridad.

**Fecha:** 31-ago-2026 · **Base:** `main` en `22b74c1`
**Estado:** hallazgo confirmado con datos de producción. Redefine el alcance del tema roles.
**Depende de:** `KuraTracker_cuarta_via_set_active_center.md` (§2 y §3 de ese doc)

---

## 1. El dato que lo resuelve

```
email                     roles_perfil       centro                          tipo              rol_membresia
maria.amaya@kuramas.com   {clinico}          Kura+                           clinica_heridas   clinico
maria.amaya@kuramas.com   {clinico}          Centro hospitalario de prueba   hospital          admin
maria.amaya@kuramas.com   {clinico}          Cuidador de prueba              cuidadores        admin
```

**Una misma persona tiene roles distintos en centros distintos, y eso es correcto** — no es
un dato sucio. María es clínica en Kura+ y administradora en los otros dos.

Por lo tanto: **`profiles.roles` no puede ser la autoridad.** Es, y solo puede ser, una
**caché del conjunto vigente en el centro activo**. La autoridad es
`user_center_memberships`.

Eso reencuadra todo el trabajo de las Fases A/B y los puntos 6-7: fue correcto (el
conjunto gobierna en lugar del escalar), pero se aplicó a la tabla equivocada. Falta subir
el mismo cambio un nivel.

---

## 2. El defecto concreto, con la ruta completa

`user_center_memberships.role` es **un solo rol por centro**. `set_active_center`
(`0040:188-191`) copia ese escalar a `profiles.role`, lo que cae en el atajo de compat del
`0098`:

```
membresía dice 'admin'  →  profiles.role = 'admin'  →  trigger  →  roles = {admin, clinico}
```

**El `clinico` es fabricado.** La membresía nunca lo concedió.

Y el centro donde eso importa más es el hospital: post-Fase B, las 23 políticas de
escritura hospitalaria gatean por `has_role('clinico')`. Es decir:

> **Una membresía administrativa en un centro tipo `hospital` produce escritura clínica
> a nivel de base de datos.**

Es exactamente el hallazgo del punto 7, vivo, por la cuarta vía, en el único tipo de
centro donde esas políticas están activas. En el caso de María es inocuo —es clínica de
verdad— pero el mecanismo no la está consultando: se lo da a cualquier admin de hospital.

### El clobber, en la otra dirección

| María se para en | `set_active_center` escribe | `profiles.roles` queda |
|---|---|---|
| Kura+ | `role = 'clinico'` | `{clinico}` |
| Hospital de prueba | `role = 'admin'` | `{admin, clinico}` ← gana clínico fabricado |
| Cuidador de prueba | `role = 'admin'` | `{admin, clinico}` |

Mientras está parada en un centro de prueba, **pasa la compuerta de compra de insumos**
(`isAdmin`) que acabamos de instalar. La compuerta es franqueable cambiando de centro.
Atenuante real: la compra se hace contra su centro activo, que en ese momento es el centro
de prueba — así que hoy no hay daño. Pero el candado no depende de lo que quisimos, sino
de en qué centro esté parada la persona.

---

## 3. El arreglo

**Migración nueva (`0100`):**

1. `alter table public.user_center_memberships add column roles public.user_role[] not null default '{}';`
2. Backfill: `roles = array[role]` — **sin** el caso especial de admin. La membresía dice
   lo que dice; si además atiende pacientes, se marca explícito (misma decisión que el
   punto 7 tomó para el alta de centros).
3. `set_active_center` reescrito:
   ```sql
   update public.profiles
   set organization_id = target_org,
       roles = v_roles          -- conjunto de la membresía; el trigger deriva `role`
   where id = auth.uid();
   ```
   Nunca vuelve a tocar `role` directamente. Con eso el atajo de compat deja de estar en
   la ruta del cambio de centro.
4. Trigger espejo en `user_center_memberships`, igual al de `profiles`, para que un writer
   legacy que toque `role` siga funcionando durante la transición.

**App:**

5. La UI de casillas del punto 6 pasa a editar la membresía del centro seleccionado, no el
   perfil global. El perfil se actualiza como consecuencia del cambio de centro activo.
6. `setUserRoles` (punto 6 §1) debe apuntar a la membresía, no a `profiles`. Hoy escribe el
   conjunto correcto en el lugar equivocado: el siguiente `set_active_center` lo sobreescribe.

**Punto de decisión para Carlos:** ¿María debe ser `{admin}` o `{admin, clinico}` en el
centro hospitalario? El backfill del paso 2 la dejaría en `{admin}`, lo que le **quitaría**
la escritura clínica que hoy tiene ahí de forma fabricada. Si en ese centro también
atiende, hay que marcarlo explícito. Aplica igual a los otros dos casos de membresía admin.

---

## 4. Lo que NO hay que hacer

- **No retirar el `case` de compat del `0098` antes de esto.** Sigue sosteniendo
  `handle_new_user` (`0011:173-181`), que inserta el profile con `role` desde
  `raw_user_meta_data` en todo alta de cuenta. Y retirarlo tampoco arreglaría el clobber:
  el clobber está en el `update` de `set_active_center`, no en el atajo.
- **No tratar los roles distintos por centro como dato sucio que hay que normalizar.** Es
  el modelo real del negocio.

---

## 5. Higiene de datos de prueba — ya con números

De los 15 perfiles con membresía activa, **5 son cuentas de prueba**: `carlos.angel@kuramas.com`,
`ktqaverify2026@gmail.com`, `smoketest@curamas.mx`, `audittest.kura2026@gmail.com`,
`prueba.clinico@kuramas.com`. Y **2 de los 3 centros** se llaman "de prueba".

Un tercio del padrón de personas y dos tercios del de centros son andamio, y nada en la
base los distingue. Sugerido, subiendo de prioridad: `is_test boolean not null default false`
en `profiles`, `organizations` y `patients`, más el filtro correspondiente en las consultas
de KPI.
