# KuraTracker — ¿Está lista la estructura para centros externos?

**Fecha:** 31-ago-2026 · **Base:** `main` en `22b74c1`
**Alcance:** solo lo que debe ser cierto **antes de que el primer centro externo entre**.
No incluye nada sobre el padrón de Kura+ (equipo interno en pruebas, no relevante).

---

## Listo

El **modelo de permisos** quedó terminado hoy y sirve para centros externos tal como está:

- `roles` como conjunto en `profiles`; RLS por `has_role()`; las 23 políticas hospitalarias
  set-aware (Fases A/B).
- `admin-create-user` escribe el conjunto explícito. `master` nunca otorgable por esa vía;
  `cuidador` exclusivo; conjunto no vacío. Validado en servidor, no solo en UI.
- UI multi-rol (casillas) para alta y edición.
- Compuerta de compra: solo admin del centro y master. 4 sitios + guardia de router.
- Consulta finalizada inmutable; descuento de inventario al cobrar; validación de
  conciliación de pagos.
- Regla de seguridad: **un centro no puede quedar sin admin** — el primer usuario de un
  centro se fuerza a admin (`data_repository.dart:430-444`).

---

## Bloquea al primer centro externo

### 1. El alta de centro no pasa por el RPC que preparamos. ⬅ el hueco principal

La pantalla de Plataforma llama `createOrganization` (`platform_home_screen.dart:940` →
`data_repository.dart:730`), que es un **INSERT directo**:

```dart
final data = {'id': _uuid.v4(), 'name': name, 'is_active': true};
await _store.insertRow(Collections.organizations, data);
```

`create_organization_with_admin` **no se llama desde ninguna parte de la app.** Tres
consecuencias:

**(a) Todo el trabajo del `0099` está dormido.** Los `roles = {admin}` explícitos y el
parámetro `p_admin_is_clinical` viven en una ruta que nadie invoca. Es correcto y está
desplegado, pero no protege el alta real.

**(b) `center_type` queda en su default y nadie lo nota.** `0040:27` lo define como
`not null default 'clinica_heridas'`. El INSERT no lo manda. Un **hospital externo nace
tipificado como clínica de heridas**, y `has_hospital_org_access` exige
`center_type = 'hospital'`: las 23 políticas hospitalarias quedan **inertes** hasta que el
master se acuerde de cambiar el tipo por `setCenterType`. Falla silenciosa: el centro
funciona, con la superficie de permisos equivocada.

**(c) El centro nace sin admin.** Lo cubre el guard del punto anterior, así que el flujo
real es "crear centro → crear primer usuario (forzado a admin)". Funciona, pero son dos
pasos que dependen de que el operador los haga en orden.

**Arreglo:** el alta de centro debe ser **atómica y tipada** — un solo paso que pida
nombre, **tipo de centro** y los datos del primer administrador, y que escriba
`center_type` y el conjunto de roles explícitos. Sea llamando al RPC (que ya hace lo
correcto, más el tipo) o extendiendo `createOrganization`. Lo que no puede quedarse es un
INSERT de tres campos como puerta de entrada de un cliente.

### 2. `set_active_center` sobreescribe el conjunto de roles

Detalle completo en `KuraTracker_roles_por_centro_brief.md`. **Por qué bloquea a centros
externos:** el personal de Kura+ va a tener membresía en los centros cliente. Desde el
momento en que exista uno, cambiar de centro reescribe `profiles.roles` desde un solo valor
de la membresía — sumando `clinico` donde la membresía solo dice `admin`, y perdiendo roles
en la otra dirección.

### 3. La membresía carga un solo rol

Un administrador de centro externo que **además atienda** no se puede representar: la
membresía tiene una sola columna `role`. El atajo del trigger lo fabrica, y en un centro
tipo `hospital` eso equivale a escritura clínica concedida por una membresía
administrativa.

**2 y 3 son una sola migración** (`roles` en `user_center_memberships` + `set_active_center`
copiando el conjunto). Ver §3 del brief citado.

### 4. Nada distingue lo real de lo de prueba

Hoy conviven 2 centros y 5 cuentas de prueba con los datos reales, sin marca. Con clientes
externos, toda métrica de adopción, uso y facturación los mezcla. `is_test boolean not null
default false` en `profiles`, `organizations` y `patients`, más el filtro en las consultas
de KPI.

---

## No bloquea (deuda, otra ronda)

- Los 31 sitios `admin`/`master` que comparan el espejo escalar (confiables por precedencia).
- Punto 8: `check` de `roles` no vacío (`role not null` ya lo impide de facto).
- Retirar el `case` de compat del `0098` — **después** de 2 y 3, nunca antes.
- El filtro `_roleFilter` del listado de usuarios.
- Lector de `audit_log` (el rastro existe en Postgres; ninguna pantalla lo lee).

---

## Pendientes previos que sí tocan al centro externo

Vienen de la auditoría del flujo comercial (28-ago) y siguen abiertos:

1. **El espejo de inventario Shopify nunca se validó contra un centro real.** Pagar en
   línea → correr sync → confirmar que el inventario sigue bajo. Es el único punto del
   flujo comercial que no se puede verificar leyendo código.
2. **Lealtad Rivo:** vínculo centro ↔ cliente de Shopify, y mostrar las condiciones del
   nivel en el catálogo. Sin esto, un centro externo miembro del programa ve precios de
   lista.
3. **Borradores huérfanos contados como sesiones** en los KPIs.

---

## Orden sugerido

1. **§1 — alta de centro atómica y tipada.** Es la puerta de entrada; hoy está abierta a
   una mala configuración silenciosa.
2. **§2 + §3 — una migración.** Roles por centro.
3. **§4 — `is_test`.** Antes del primer cliente, no después: retro-etiquetar es peor.
4. Pendientes previos 1 y 2 (Shopify / Rivo), que dependen de un centro real para probarse.
