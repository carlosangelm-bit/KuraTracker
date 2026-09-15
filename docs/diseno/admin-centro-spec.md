# Administración del centro — Usuarios, Personal y Sitios

**Canvas aprobados:** "Personal y Sitios" (14-sep-2026) para Personal y Sitios;
"Consola master · Derechos", tablero *Centro · Personas*, para Usuarios.
**Alcance:** las tres pantallas de `/admin` que seguían con el diseño viejo. Es
contenido; el cromo (riel, encabezado) ya está y no se toca.

Las medidas estructurales —tarjetas, filas de tabla, píldoras, botones, tintes— son
las de **§4 del spec de la consola master** (`consola-master-derechos-spec.md`). No se
repiten aquí; si algo choca, manda aquel. Todo color desde `BrandTokens`;
`KuraColors` prohibido y el escaneo de la prueba de fuente cubre estos archivos.

**Cada sección es un CUERPO, no una pantalla.** `AdminSectionsShell` ya pinta el ÚNICO
`KuraContentHeader` («Administración › X») y el ÚNICO `KuraNavRail` (con la cuenta en el
pie). Las secciones **NO se envuelven en `KuraScreen`**: eso daría un SEGUNDO encabezado
—la familia de defecto que ya costó dos rieles y dos menús de cuenta—. El `Scaffold` de
cada sección es solo para hospedar el `KuraPrimaryFab`.

---

## 1. Usuarios (`/admin/usuarios`)

Es el tablero *Centro · Personas* del canvas de la consola master, visto por el admin
del centro. Se quita lo que era del master (selector de centro) y **se conserva todo lo
demás**, porque todo aplica igual: el admin necesita entender sus asientos tanto como
el master.

**Tres medidores arriba:** asientos clínicos (uso / tope), cupos administrativos
(uso / 3 si hay `module:admin`, si no 0) y "No consumen".

**Columna "Qué consume"**, derivada, nunca capturada:
`Asiento clínico` si `consumes_clinical_seat(p.roles, p.role)`; `Cupo administrativo`
si es admin puro; `Nada` en los demás; `Nada (inactiva)` si `is_active = false`.

**Marca ámbar "También está en otro centro"** cuando la persona tiene más de una
membresía activa. Razón, que va en el spec para que no se borre por parecer adorno: los
contadores leen `p.roles`, que es **un solo valor global por persona**, así que su
clasificación de asiento en este centro depende de qué centro abrió al último.

**El interruptor de cuenta activa se deshabilita** si la persona es la última capaz de
definir planes (`0111`/`0112` ya lo bloquean en la base; aquí se anticipa). El motivo va
en la columna Nota, **no en un tooltip** — un tooltip no existe en táctil.

---

## 2. Personal (`/admin/personal`)

**Qué es la pantalla, y hay que decirlo en la pantalla:** el personal es la *identidad
sanitaria* del centro —folio y cédula, lo que firma una nota— y la cuenta es con lo que
*entran a la app*. Son dos cosas distintas en el modelo y hoy nadie lo adivina.

**«Sin cuenta»** sale del texto corrido del subtítulo a una **etiqueta** (estado que pide
acción, no un dato más), con el mismo lenguaje visual que las etiquetas de rol de
Usuarios. El interruptor de activo va **con rótulo**, como en Usuarios y Sitios.

**Corrección del avatar.** Mostraba `s.folio.substring(1, 3)` —los caracteres 2 y 3 del
folio—. Con `K2026-0001` eso da "20", y como todos los folios del año empiezan igual,
**todo el personal salía con el mismo par de dígitos**; sobre un folio corto/vacío,
`.substring` lanzaba un `RangeError` que tumbó la pantalla del master. Va SIEMPRE con
`avatarInitial(s.fullName)`. El folio ya sale en el subtítulo.

---

## 3. Sitios (`/admin/sitios`)

**El tipo de sitio** (Clínica · Domicilio · Hospital · Otro) sale del texto corrido a una
**etiqueta**, con el mismo lenguaje que las de Usuarios y Personal. La dirección, cuando
existe, va como línea secundaria.

**Candado comercial, sin cambios:** el PRIMER sitio va incluido; del segundo en adelante
exige el módulo Administración (avanzado), y sin él el FAB cambia a candado y abre el
mensaje de venta.

**Nota de comportamiento:** desactivar un sitio lo oculta para nuevas altas; los
pacientes y las notas que ya viven ahí no se tocan.

### 3.1 REGLA NUEVA — no se puede desactivar un sitio que rompe el centro

**Esto no existía.** Verificado: `setSiteActive` (`data_repository.dart`) escribía
`is_active` sin revisar nada. Desactivar un sitio (transición `true → false`) se RECHAZA
en **tres casos**, cada uno con un mensaje que dice qué hacer:

1. **Es el único sitio activo del centro.** `Consultation.siteId` es **requerido, no
   nulable** (`consultations.site_id NOT NULL`): sin ningún sitio activo el centro no
   puede registrar una sola consulta.
2. **Tiene personal ACTIVO** con `primary_site_id` apuntando a él.
3. **Tiene existencias de inventario distintas de cero** (algún artículo con neto `<> 0`).

**Las dos capas, y no es opcional:** guardia en el repositorio Dart **y** trigger en base
de datos (`0134_prevent_site_deactivation.sql`). El precedente exacto es
`0111_prevent_org_without_clinico.sql`: ahí la app ya validaba en cliente y aun así se
cerró del lado servidor «para el acceso directo por PostgREST». Una guardia que solo vive
en la app no está cuando importa. La forma de `0111`: función `security definer` con
`search_path` fijo, trigger `trg_zz_*` para correr al final, comparaciones no atadas a
literales frágiles, y actuar solo en la transición `true → false` (reactivar y los no-ops
pasan). **La base es la autoridad; la UI se anticipa.** Reactivar siempre se permite.

**Los mensajes dicen qué hacer, y el del servidor y el del cliente dicen LO MISMO:**

- «No puedes desactivar este sitio: es el único activo del centro y toda consulta
  necesita un sitio. Da de alta otro antes de desactivar este.»
- «No puedes desactivar este sitio: N personas lo tienen como sitio principal.
  Reasígnalas en Personal antes de desactivarlo.»
- «No puedes desactivar este sitio: tiene existencias en inventario. Trasládalas o
  ajústalas a cero antes.»

La pantalla solo los muestra con el patrón `_showRepoError` que ya usan Usuarios y
Personal (SnackBar que quita el prefijo `Exception:`).

---

## 4. Pruebas — de conducta, y sobre el camino real

Criterio de siempre: **romper la regla pone la prueba en rojo**, verificado a mano antes
de darla por verde.

Por cada sección (etapas 1-3): la ruta monta la pantalla nueva (router real); a 1200 px
hay **un solo** `KuraContentHeader` y **un solo** `KuraAccountMenu`; y el archivo no
contiene `KuraColors`.

Específicas:

1. Usuarios: "Qué consume" para los cuatro tipos de persona; y el interruptor de cuenta
   activa deshabilitado para la última persona capaz de definir planes, con el motivo en
   la fila.
2. Personal: el avatar rinde **iniciales del nombre**, no los dígitos del folio (con el
   código viejo salía "20"); y un folio vacío **no lanza `RangeError`**.
3. Sitios (la regla nueva, en las dos capas):
   - **Dart** (`test/unit/site_deactivation_guard_test.dart`): los tres rechazos, uno por
     caso, verificando el mensaje; **y el caso positivo** —un sitio que no cae en ninguno
     de los tres SÍ se desactiva—, porque una guardia que bloquea todo también "pasaría"
     los tres rechazos.
   - **SQL** (`supabase/tests/local/`, Docker): los tres rechazos EJECUTADOS contra la
     base (no solo que la función exista) **y** el caso positivo. Corre con
     `run_site_guard.sh`.

---

## 5. Etapas

1. **Usuarios** — la que más regla tiene y ya estaba diseñada.
2. **Personal** — incluida la corrección del avatar.
3. **Sitios** — incluida la migración de la guardia (`0134`).

Una etapa por entrega, verificada contra la app servida antes de la siguiente, como en
Fase 3 y en la consola de derechos.
