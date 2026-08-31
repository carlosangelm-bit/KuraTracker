# KuraTracker — Punto 7: cerrar el atajo legacy antes del primer centro cliente

**Fecha:** 31-ago-2026 · **Base:** `main` en `ce4d1a2`, `0098` aplicada y verificada
**Para:** agente de desarrollo

**Verificación de la Fase B, cerrada:** consulta A → 0 filas; consulta B → las 23
políticas de escritura con `has_role`, sin duplicados ni huecos. `current_user_role()`
ya no decide en ninguna política.

---

## 1. Corrección a mi brief anterior (punto 6)

Dije "52 sitios comparando el espejo escalar" como si todos fueran igual de sospechosos.
No lo son, y la diferencia cambia el orden de urgencia.

`primary_role` es por precedencia: `master > admin > clinico > enfermeria > cuidador`.
De ahí:

| comparación | ¿confiable? | por qué |
|---|---|---|
| `role == master` (12) | **sí** | master es la precedencia más alta: si está en el conjunto, es el espejo |
| `role == admin` (37) | **casi** | falla solo si alguien tiene `{master, admin}` a la vez |
| `role == clinico` (6) | **NO — roto hoy** | `{admin, clinico}` espeja a `admin`; las 4 cuentas de Kura+ están así |
| `role == enfermeria` (4) | **NO** | falla combinado con clinico/admin/master |
| `role == cuidador` (7) | **NO** | precedencia más baja: falla combinado con cualquier cosa |

**Los 17 sitios de `clinico`/`enfermeria`/`cuidador` son los que tienen bug real.** Los 49
de `admin`/`master` conviene migrarlos igual por higiene semántica, pero no son urgentes.
El caso vivo sigue siendo `risk_board_screen.dart:119`.

---

## 2. El hallazgo del punto 7, confirmado en código

Dos vías de alta escriben **solo `role`**, nunca `roles`, y por lo tanto caen en el `case`
de compatibilidad del trigger `sync_profile_roles`, que reparte `clinico` sin que nadie
lo pida:

**(a) `create_organization_with_admin` — `0011_organizations.sql`**
```sql
update public.profiles
   set role = 'admin'::public.user_role, ...
```
Rama UPDATE del trigger: `new.role is distinct from old.role` → `new.roles := {admin, clinico}`.
**El administrador de todo centro cliente nuevo nace con rol clínico.**

**(b) Edge Function `admin-create-user` — `index.ts:130`**
```js
{ role, ... }   // escribe el escalar; nunca roles
```
Mismo camino. Un admin dado de alta desde la UI del centro nace en `{admin, clinico}`.

**Lo que ya está bien y NO hay que reimplementar:** `index.ts:87` ya rechaza `master` por
esta vía (`role debe ser 'admin', 'clinico', 'cuidador' o 'enfermeria'`). El requisito
"un admin no puede otorgar master" está cubierto; solo hay que preservarlo al cambiar la
firma a conjunto.

---

## 3. Trabajo del punto 7

1. **`admin-create-user` acepta `roles: string[]`** y lo escribe en el insert/upsert del
   profile. Deja que el trigger derive el espejo `role` (rama "alta con `roles`", que ya
   existe en `0098`). Validaciones del lado del servidor:
   - `master` nunca por esta vía (ya está — mantenerlo sobre el arreglo).
   - conjunto no vacío.
   - `cuidador` exclusivo: si viene `cuidador`, no puede venir nada más.
   - Mantener `roles` compatible hacia atrás: si el body trae `role` y no `roles`,
     seguir aceptándolo (la UI vieja todavía lo manda).
2. **`create_organization_with_admin` escribe `roles` explícito.** Nueva migración `0099`:
   `set roles = '{admin}'` por defecto, y un parámetro (p. ej. `p_admin_is_clinical
   boolean default false`) que produce `{admin, clinico}` para el caso del profesional
   independiente que hace todo. El `update` debe tocar `roles`, no `role`, para caer en la
   rama correcta del trigger.
3. **La creación de staff** (`index.ts:145`) hoy pregunta `role === 'clinico' || ...`.
   Cambiar a "el conjunto contiene clinico o enfermeria". Ojo: si un admin nace en
   `{admin}` sin fila de `staff`, `ensureAdminStaffId` se la crea al vuelo la primera vez
   que la necesita — pero como ya no tendrá `clinico`, `canDiagnose` será falso y no
   llegará a ese punto. Es el comportamiento deseado; solo hay que confirmar que la UI se
   lo diga con un mensaje claro y no con una pantalla en blanco.
4. **Candado de compra a `isAdmin`** — tres sitios, no uno:
   - `lib/features/insumos/purchase_guard.dart:11`
   - `lib/features/insumos/inventario_screen.dart:351`
   - `lib/features/insumos/inventario_screen.dart:563`
   (Hoy `purchase_guard` rescata al master con `|| isMaster` y los otros dos no: un master
   puede comprar pero no editar precios.)
5. **NO tocar el `case` de compat del trigger todavía.** Se retira cuando ninguna vía de
   alta dependa de él — es decir, después de que 1 y 2 estén en producción y verificados.

### Criterio de aceptación

Dar de alta un centro nuevo con su administrador por el flujo real y verificar:

```sql
select p.email, p.role, p.roles, o.name
from public.profiles p join public.organizations o on o.id = p.organization_id
where o.name = '<centro de prueba>';
```

Esperado: el admin en `roles = {admin}` y `role = 'admin'`. Si sale `{admin, clinico}`,
alguna vía sigue escribiendo el escalar.

---

## 4. Decisión de producto que hay que tomar antes de codificar el punto 2

Cuando se da de alta un centro, **¿su administrador atiende pacientes?**

- Centro con equipo (administrador + clínicos): **no** → `{admin}`.
- Profesional independiente que es su propio centro: **sí** → `{admin, clinico}`.

Es la distinción que Carlos ya planteó: la plataforma es la misma, lo que cambia son los
permisos. Por eso debe ser **una pregunta explícita en el onboarding**, no un valor
heredado de un atajo. Hoy el atajo contesta "sí" siempre, que es la respuesta correcta
para el caso menos común.
