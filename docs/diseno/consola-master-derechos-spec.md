# Consola master · Derechos — especificación

**Canvas aprobado:** "Consola master · Derechos" (5 artboards), 14-sep-2026.
**Decisiones de Carlos:** tipo explícito (comercial / cortesía); fecha de vigencia
obligatoria con "permanente" como casilla deliberada; alcance v1 = módulos + asientos
+ cuentas.

---

## 1. Por qué

La consola de `/platform` opera **interruptores y banderas legadas**
(`module_settings`, `organizations.premium_insumos`, `premium_protocolo_kura`).
La app decide por **derechos** (`org_entitlements`). Verificado: no existe una sola
escritura a `org_entitlements` en `lib/` ni en `supabase/functions/`. Los únicos
caminos hoy son el webhook de Stripe y el SQL Editor a mano.

Consecuencia concreta, y es la peor forma de una función administrativa: `0115` exime
al master de su candado, así que el master **puede** encender un módulo sin derecho,
**no recibe error**, y bajo el AND no se ve nada. Parece que funcionó.

Lo que este spec cambia: la consola pasa a operar derechos, y el interruptor queda al
lado como lo que es — una segunda condición, con su desacuerdo visible.

Lo que NO hay que construir, porque ya existe y está verificado:
- RLS de `org_entitlements`: `insert`/`update`/`delete` con `with check (public.is_master())` (0113).
- `profiles_update_own_or_admin` incluye `public.is_master()` (0017/0104) → activar y
  desactivar cuentas no necesita política nueva.
- Caducidad: `canWriteModule` (`data_repository.dart:893`) ya gatea por
  `current_period_end` **solo** cuando `source='master'`. Vencer deja el módulo en
  SOLO LECTURA, no lo oculta. No construir otro mecanismo de caducidad.
- El barrido de `apply_stripe_subscription_event` solo toca `source='stripe'` (0119),
  a propósito, para que un otorgamiento del master sobreviva la renovación.

---

## 2. Base de datos — migración `0132_master_grants.sql`

### 2.1 Columnas nuevas en `public.org_entitlements`

```
grant_type    text          -- 'comercial' | 'cortesia'; null si source='stripe'
reason        text          -- motivo; null si source='stripe'
granted_by    uuid          -- references public.profiles(id); null si source='stripe'
is_permanent  boolean not null default false
```

`is_permanent` NO duplica la caducidad: `canWriteModule` ya trata
`current_period_end = null` como "no vence". La columna existe para que el CHECK
pueda distinguir **permanente a propósito** de **fecha olvidada** — que es justo la
decisión que tomó Carlos. Nunca se lee para decidir acceso.

### 2.2 Relleno de las filas que ya existen

`0114` escribió filas `source='master'` sin estos campos. ANTES de agregar el CHECK:

```sql
update public.org_entitlements
   set grant_type = 'cortesia',
       reason = 'Backfill de licencias (0114): estado efectivo al migrar.',
       is_permanent = true
 where source = 'master' and grant_type is null;
```

### 2.3 CHECK, después del relleno

```sql
alter table public.org_entitlements add constraint ent_master_grant_shape check (
  (source = 'stripe'
     and grant_type is null and reason is null and granted_by is null
     and is_permanent = false)
  or (source = 'master'
     and grant_type in ('comercial','cortesia')
     and reason is not null and length(btrim(reason)) >= 10
     and (is_permanent or current_period_end is not null))
);
```

El mínimo de 10 caracteres en `reason` es deliberado: "ok" no es un motivo.

### 2.4 Bitácora `public.org_entitlement_log`

La unicidad `(organization_id, kind, key)` significa que otorgar dos veces
**sobrescribe**: sin bitácora se pierde el historial. Tabla append-only:

```
id, organization_id, kind, key, action ('grant'|'revoke'|'amend'),
grant_type, reason, quantity, current_period_end, is_permanent,
actor uuid, at timestamptz not null default now()
```

RLS: `select` para master; sin `insert` para `authenticated` (solo escriben las RPC
`security definer`). Nunca se borra ni se actualiza.

### 2.5 RPCs (`security definer`, `set search_path = public, pg_temp`)

**`master_grant_entitlement(p_org uuid, p_kind text, p_key text, p_quantity int, p_grant_type text, p_reason text, p_until timestamptz, p_permanent boolean) returns uuid`**

Guardias, en este orden, cada una con su mensaje propio:
1. `if not public.is_master() then raise exception 'MASTER_ONLY'`.
2. Si ya existe una fila `(p_org, p_kind, p_key)` con `source='stripe'`:
   `raise exception 'GRANT_STRIPE_OWNED: ese derecho lo gobierna Stripe.'`
   **Esta es la guardia que más importa** — sobrescribirla rompería el barrido del webhook.
3. `p_kind='seat'` y `p_key='clinico'` con `p_quantity < public.consumed_seat_demand(p_org)`:
   `raise exception 'GRANT_BELOW_DEMAND: el centro ya usa % asientos.'`
4. `not p_permanent and p_until is null` → `raise exception 'GRANT_NO_EXPIRY'`.
5. `p_permanent and p_until is not null` → `raise exception 'GRANT_AMBIGUOUS_EXPIRY'`.

Escribe con `granted_by = auth.uid()` (NUNCA del cliente), `source='master'`,
`status='active'`, `current_period_end = case when p_permanent then null else p_until end`,
upsert sobre `(organization_id, kind, key)`, y una fila en la bitácora con
`action = 'grant'` si no existía, `'amend'` si sí.

**`master_revoke_entitlement(p_org uuid, p_kind text, p_key text, p_reason text) returns void`**
Mismas guardias 1 y 2. Pone `status='canceled'` (no borra: el rastro importa) y
escribe la bitácora con `action='revoke'`.

**`master_set_profile_active(p_profile uuid, p_active boolean) returns void`**
Guardia 1, luego `update public.profiles set is_active = p_active where id = p_profile`.
Los triggers de `0111`/`0112` siguen siendo la autoridad: si dejaría al centro sin
quien defina planes, revientan solos y el mensaje se propaga tal cual.

`grant execute` de las tres SOLO a `authenticated` (la guardia 1 hace el resto).

---

## 3. Repositorio (`lib/services/data_repository.dart`)

```dart
Future<void> masterGrantEntitlement({
  required String organizationId, required String kind, required String key,
  int? quantity, required String grantType, required String reason,
  DateTime? until, required bool permanent,
});
Future<void> masterRevokeEntitlement({
  required String organizationId, required String kind, required String key,
  required String reason,
});
Future<void> masterSetProfileActive(String profileId, bool active);

/// Derechos del centro con sus campos de otorgamiento, para el panel.
List<OrgEntitlement> entitlementsFor(String organizationId);
/// Todos los derechos con source='master', de todos los centros, ordenados por
/// vencimiento (los vencidos primero, los permanentes al final).
List<ManualGrant> manualGrants();
```

Cada una llama su RPC por nombre y **traduce los códigos de error a español**:
`GRANT_STRIPE_OWNED` → "Ese derecho lo gobierna Stripe: cámbialo en la suscripción,
no aquí."; `GRANT_BELOW_DEMAND` → "El centro ya usa N asientos; no puedes bajar el
tope por debajo."; `MASTER_ONLY` → "Solo el master puede otorgar derechos."

**Importes:** SIEMPRE de `billing_catalog` vía `unitAmountCents(kind, key, interval)`,
formateados con `lib/core/format/money.dart`. Cero importes escritos a mano en la UI.
Si `unitAmountCents` devuelve `null`, la celda muestra "—", nunca `$0`.

---

## 4. Tokens — leer esto antes de escribir un color

Todo sale de `BrandTokens.of(context)`. **`KuraColors` está prohibido en estas
pantallas** (es el alias legado, siempre morado: en un hospital pinta mal).

El canvas usa dos colores de texto sobre tinte que **hoy no son tokens**:
`#8A6111` (texto sobre tinte ámbar) y `#116B44` (texto sobre tinte verde).
`statusWarning` (`#E8A93A`) y `statusSuccess` (`#1B8A5A`) no tienen contraste
suficiente como texto sobre blanco.

**No los escribas a mano.** Agrégalos a `BrandTokens` como `statusWarningText` y
`statusSuccessText`, con valor en las TRES marcas (kura, hospital, cuidadores) — el
semáforo de estado es clínico y es igual en todas. Es exactamente el mismo error que
`chipBg` en el spec de Licencias: un color de sistema fijado en un solo archivo.

Fondos con tinte: `Tints.<rol>(t, opacidad)`, nunca `Color.fromRGBO` a mano. Si no
existe el helper para un rol de estado, agrégalo con la misma forma que `Tints.brand`.

Valores estructurales del canvas, exactos:
- Barra superior 52 px, fondo `surface`, borde inferior 1 px `border`.
- Pestañas del centro: `padding: 12px 0 10px`, activa `font-size 13 / w800 /
  brandPrimary` con subrayado 2 px; inactiva `w600 / textSecondary`.
- Tarjetas: `surface`, borde 1 px `border`, radio `AppRadii.md` (16).
- Tarjetas de cifra: padding `18px 20px`, gap 4; etiqueta 12/w700/`textSecondary`;
  cifra 28/w800 `line-height 1.1`; pie 11/`textSecondary`.
- Filas de tabla: padding `14px 20px`, separador 1 px `border`; encabezado 11/w800/
  `textSecondary`.
- Píldoras: radio `AppRadii.pill` (30), `padding 3px 9px`, 10 u 11 px, w700/w800.
- Botón primario: `brandPrimary`, `onBrand`, radio pill, `padding 11px 20px`, 13/w700.
- Fila con acento: fondo `Tints` al 4–6 % del color del estado.

---

## 5. Pantallas

Las cinco están en el canvas y ESE es el detalle fino: proporciones, columnas, orden y
copy salen de ahí, no de este texto. Lo que este spec fija es la conducta.

### 5.1 Plataforma · Centros (`Main`)
Sustituye el selector de centro actual. Columnas: Centro · Tipo · Plan · Módulos con
derecho · Asientos clínicos · Origen · Requiere atención.
- "Módulos con derecho": una píldora por módulo. **Rellena** = derecho activo;
  **contorno punteado `textDisabled`** = sin derecho. Se pinta desde
  `org_entitlements`, no desde `module_settings`.
- "Origen": `Stripe` si todos los derechos son de Stripe; `A mano` si todos son del
  master; `Mixto` si hay de los dos.
- "Requiere atención": el vencimiento más próximo a menos de 30 días, o un desacuerdo
  entre derecho e interruptor. Vacío = "—", nunca una fila inventada.

### 5.2 Centro · Licencia (`Licencia`)
Dos grupos: **Módulos** y **Asientos**. Cada fila lleva origen, tipo, quién otorgó,
motivo entre comillas, vigencia, estado del interruptor y el importe.
**La regla que justifica la pantalla:** por cada módulo se comparan derecho e
interruptor y se muestran los cuatro casos:
| Derecho | Interruptor | Qué se muestra |
|---|---|---|
| sí | encendido | normal |
| sí | apagado | aviso ámbar "Con derecho, apagado en el centro." |
| no | encendido | **rojo** "Encendido en el centro, pero sin derecho: nadie lo ve." |
| no | apagado | fila gris, píldora "Sin derecho" |
Columna derecha: "Qué paga y qué no" (Stripe / a mano / valor de lista), próximo
vencimiento con su consecuencia en palabras, y solicitudes del centro.

### 5.3 Otorgar derecho (`Otorgar`)
Modal 620 px. Campos en el orden del canvas. Reglas:
- **Otorgar** deshabilitado mientras falte tipo, motivo (≥10 caracteres) o vigencia.
- La casilla "Permanente" **deshabilita** el campo de fecha y lo vacía.
- La banda de consecuencia recalcula en vivo: importe mensual del catálogo y el total
  del periodo entre hoy y la fecha elegida. Con "Permanente" marcada, el total
  desaparece y queda solo el mensual.
- La línea de solo lectura al vencer NO es opcional ni colapsable.

### 5.4 Centro · Personas (`Personas`)
Tres medidores arriba: asientos clínicos (uso / tope), cupos administrativos (uso / 3
si hay `module:admin`, si no 0), y "No consumen".
Columna **"Qué consume"**, derivada, no capturada:
`Asiento clínico` si `consumes_clinical_seat(p.roles, p.role)`; `Cupo administrativo`
si es admin puro; `Nada` en los demás; `Nada (inactiva)` si `is_active = false`.
Marca ámbar **"También está en otro centro"** cuando la persona tiene más de una
membresía activa — los contadores leen `p.roles`, que es un solo valor global, así que
su clasificación depende de qué centro abrió al último.
El interruptor de cuenta activa se deshabilita si la persona es la última capaz de
definir planes; el motivo va en la columna Nota, no en un tooltip.

### 5.5 Otorgados a mano (`Manuales`)
Todos los centros. Orden fijo: vencidos primero, luego por vencimiento ascendente,
permanentes al final. Filtros por tipo. Cuatro cifras arriba, incluido **valor
condonado al mes** (suma del catálogo de todos los derechos manuales activos).

---

## 6. Pruebas — de invocación, no de forma

El criterio de aceptación de cada una es de CONDUCTA: **si borras la línea, la prueba
se pone en rojo.** Verificarlo a mano borrando la línea antes de darla por buena.

1. `master_grant_entitlement` rechaza una fila `source='stripe'` (prueba de SQL con
   una fila sembrada). Sin esto, un otorgamiento a mano puede romper el barrido del webhook.
2. Rechaza `seat:clinico` por debajo de `consumed_seat_demand`.
3. Rechaza motivo de menos de 10 caracteres y vigencia ausente sin "permanente".
4. `granted_by` sale de `auth.uid()` y NO de un parámetro: llamar con otro id no cambia el registro.
5. **La tabla de los cuatro casos de 5.2**: cuatro casos, y el de "encendido sin
   derecho" exige el texto rojo. Es la razón de ser del rediseño; sin prueba se cae sola.
6. El diálogo deja `Otorgar` deshabilitado con motivo corto, y habilitado al completarlo.
7. Marcar "Permanente" vacía y deshabilita la fecha.
8. La columna "Qué consume" devuelve los cuatro valores para los cuatro tipos de persona.
9. Un test de fuente que exija que ningún archivo de la consola mencione `KuraColors`
   (mismo patrón que el escaneo de `_gatedScreens`).

---

## 7. Etapas

1. **Base**: `0132` + las tres RPC + los métodos del repo + tokens
   `statusWarningText`/`statusSuccessText` en las tres marcas. Sin UI. Pruebas 1–4 y 9.
2. **Centro · Licencia** (5.2) — la pantalla que justifica todo. Prueba 5.
3. **Otorgar derecho** (5.3). Pruebas 6 y 7.
4. **Plataforma · Centros** (5.1).
5. **Centro · Personas** (5.4). Prueba 8.
6. **Otorgados a mano** (5.5).

Entregar y revisar etapa por etapa, como en Fase 3. No empezar la siguiente sin que la
anterior esté verificada contra la app servida.

---

## 8. Límite consciente de la v1

No se diseñó el alta de cliente de punta a punta (crear centro + admin + módulos +
asientos en un paso). Queda para después; la bitácora de §2.4 es lo que hace que
agregarla luego no pierda historia.
