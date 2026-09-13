# Sistema — los seis componentes compartidos

Guardar como `docs/diseno/sistema-componentes-spec.md`.

Esta es la base. Las especificaciones de cada pantalla la dan por leída y solo
describen lo propio. **Constrúyelos primero, como widgets compartidos en
`lib/core/widgets/`; después las pantallas.**

Todos los valores salen del canvas aprobado y existen ya en
`lib/core/design/tokens.dart`. **Tómalos de `BrandTokens`, `AppSpacing`,
`AppRadii` y `AppType` — nunca de `KuraColors`, nunca literales sueltos.**
Los hex de marca aquí son la marca clínica; hospital y cuidadores cambian solos
por tokens. Los de estado (#1B8A5A éxito, #E8A93A aviso, #C0392B peligro,
#3B82F6 info) son iguales en las tres marcas.

Superficie base de toda pantalla: fondo `background` (#F6F5FB), tarjetas
`surface` (#FFFFFF) con borde `1px border` (#E7E4F0), sin elevación.

---

## 1. `KuraDataTable` — tabla de datos

Hoy no existe ni una sola tabla en Insumos, Reportes, VAC ni Configuración:
todo es `ListView` de `Card`/`ListTile` con los campos unidos por " · " en un
subtítulo de 11px. Este componente los reemplaza.

**Encabezado de columna:** **11px w800**, `letter-spacing .06em`, MAYÚSCULAS,
color `textSecondary` (#6B6577), `padding 0 12px 10px 12px`,
`border-bottom: 1px #E7E4F0`. Alineado a la izquierda salvo columnas numéricas.

**Celda:** `padding 12px`, `border-bottom: 1px #F1EFF7`, **13px**,
color `textPrimary`, centrada verticalmente.

**Zebra:** filas pares con fondo `#FBFAFE`.

**Reglas, no sugerencias:**

- Los números van **a la derecha**, con cifras tabulares
  (`fontFeatures: [FontFeature.tabularFigures()]`) y su unidad en **11px
  `textDisabled`** (#AEA9BC) al lado: `24` + `pz`, `$1,104.00`.
- El texto va a la izquierda. **Nada se centra.**
- El color vive **en el dato**, no en la fila: la existencia se pinta
  `statusDanger` si ≤ 0, `statusWarning` si ≤ umbral, `statusSuccess` si no.
  La fila nunca se tiñe entera.
- Segunda línea bajo el nombre **solo para el identificador** (proveedor, folio,
  SKU, correo): **11px `textDisabled`**. Todo lo demás va en su columna.
- Encabezado clicable para ordenar; la columna activa lleva `↓`/`↑` en
  `brandPrimary`.
- **Celda de identidad** (primera columna): cuadro o avatar **30×30**
  (`radius 7` para cosas, `radius 30` para personas), fondo `chipBg` (#EFEDF7),
  `gap 11`; nombre **13px w600** y debajo el identificador.
- **Fila de totales** (`tfoot`): sin `border-bottom`, `padding-top 14`;
  etiquetas **12px w700 `textSecondary`**, el total en **15px w800**.

**Selección múltiple:** casilla **17×17**. Apagada: `radius 5`, borde
`1.5px #C9C3DB`, fondo blanco. Encendida: `radius 5`, fondo `brandPrimary`,
palomita 11px blanca `stroke-width 3.4`. La casilla del encabezado selecciona todo.

**Pastilla de celda** (origen, estado, rol): `padding 3px 9px`, `radius 30`,
**11px w700**. Normal: fondo `chipBg`, texto `textPrimary`. Atenuada:
fondo `background`, texto `textSecondary`, borde `1px dashed border`.

---

## 2. `KuraModuleLock` — bloqueo de módulo

Hoy hay **cuatro variantes distintas** del mismo bloqueo y **ninguna tiene botón
de compra**: todas dicen "solicítalo a tu administrador de plataforma", que es la
misma persona que está mirando la pantalla. La pantalla de compra está a un clic.

Un solo componente, tres densidades. Las tres **dicen el precio y llevan a
Licencias** (`context.go('/admin')`, pestaña Licencias). El precio se lee de
`billing_catalog`, nunca escrito a mano.

### a) Banda en línea — cuando el resto de la pantalla sí funciona

`radius 12`, fondo `#FAF7FF`, borde `1px border`, `padding 14px 16px`, `gap 12`.
Candado 18px `brandPrimary` (`stroke-width 2.2`). Texto en dos líneas:
**13px w700** con el nombre del módulo y el precio, y **11px `textSecondary`**
con lo que incluye. A la derecha, botón `Ver Licencias`: fondo `brandPrimary`,
texto blanco **12px w700**, `radius 30`, `padding 8px 16px`.

### b) Acción bloqueada — un botón que no se puede usar

Hoy un botón bloqueado se ve **idéntico** a uno libre (mismo color, habilitado,
solo cambia el ícono) y al tocarlo sale un snackbar que se va solo. Debe verse
apagado **antes** de tocarlo:

fondo `background`, texto `textDisabled` **12px**, borde `1px dashed border`,
`radius 30`, `padding 9px 15px`, candado 13px `textDisabled` a la izquierda.
Al tocarlo abre la densidad (c) en un diálogo — nunca un snackbar.

### c) Sección completa

`radius 12`, fondo `background`, borde `1px dashed border`, `padding 20`,
centrado, `gap 10`: cuadro **38×38** `radius 10` fondo `chipBg` con candado 19px
`brandPrimary`; nombre de la función **14px w700**; una frase **12px
`textSecondary`** `line-height 1.5` de **qué se gana** (nunca qué está bloqueado);
botón `Agregar por $X al mes` — fondo `brandPrimary`, blanco, **12px w700**,
`radius 30`, `padding 9px 18px`.

---

## 3. `KuraEmptyState` — estado vacío

Hoy todos son un `Text` gris centrado dentro de un `Padding(32)` y **ninguno
ofrece la acción que lo resolvería**.

Centrado, `gap 12`: cuadro **56×56** `radius 16` fondo `chipBg` con ícono 26px
`brandPrimary` (`stroke-width 1.8`); título **17px w700** que nombra la
situación; una o dos frases **13px `textSecondary`** `line-height 1.55`,
`max-width 380`; y **los botones que la resuelven** (`gap 10`, `padding-top 6`):
el primario con fondo `brandPrimary` y texto blanco, el secundario con fondo
`chipBg` y texto `brandPrimary`, ambos **13px w700**, `radius 30`,
`padding 10px 18px`.

El vacío es el mejor momento para enseñar el producto: siempre lleva salida.

---

## 4. `KuraErrorState` — error

Hoy se vuelca `Error: $e` crudo en cinco pantallas, sin reintentar.

Tarjeta, `padding 28px 32px`, `gap 16`:

- Fila (`gap 14`, arriba): cuadro **38×38** `radius 10` fondo `#FBEDEB` con ícono
  19px `statusDanger`; al lado (`gap 5`) título **15px w700** que dice **qué
  pasó en español** ("No pudimos cargar el inventario") y una frase **13px
  `textSecondary`** `line-height 1.55` que dice **qué está a salvo**
  ("Puede ser tu conexión. Tus datos están a salvo: nada se perdió ni se guardó a medias.").
- Botones (`gap 10`): `Reintentar` primario; `Ver detalle técnico` como texto
  plano `textSecondary` sin relleno lateral izquierdo.
- Detalle plegado: caja `background`, borde `1px border`, `radius 8`,
  `padding 11px 13px`, con el mensaje de la excepción en **monoespaciada 11px
  `textSecondary`**. Cerrada por defecto.

La excepción cruda nunca es el mensaje. Va adentro, para soporte.

---

## 5. `KuraActionBar` — barra de acciones

Hoy Configuración tiene **once botones idénticos en un renglón** e Inventario
esconde sus cuatro acciones pesadas en `IconButton` sin etiqueta — que en móvil
no tienen tooltip, así que ahí son invisibles.

Fila, `gap 12`:

1. **Buscador**, ocupa el espacio libre: fondo `background`, borde `1px border`,
   `radius 30`, `padding 10px 17px`, lupa 16px `textDisabled`, texto **13px**
   con placeholder que dice por qué campos busca
   ("Buscar por nombre, SKU o proveedor").
2. **Una sola acción primaria**: fondo `brandPrimary`, blanco, **13px w700**,
   `radius 30`, `padding 10px 18px`.
3. **`Más acciones`**: fondo `chipBg`, texto `brandPrimary`, misma métrica, con
   chevron 13px. Abre un menú con las acciones pesadas **con nombre completo**.

Debajo, **fila de filtros** (`gap 9`, `flex-wrap`): pastillas `padding 7px 14px`,
`radius 30`, **12px w700**. Activa: fondo `brandPrimary`, texto blanco.
Inactiva: fondo `chipBg`, texto `textPrimary`. **Cada pastilla trae su conteo**
(`Bajo umbral · 7`). A la derecha del todo, **12px `textDisabled`**:
`Mostrando N de M`.

---

## 6. `KuraStat` — cifra con contexto

Hoy "Valor $38,420" no dice si es a costo o a precio; "+14" en Reabasto nunca
explica que sale de umbral × 2 − existencia.

Tarjeta `padding 20px 22px`, `gap 5`, tres piezas **siempre**:

1. **Etiqueta** — **11px w700 `textSecondary`**.
2. **Cifra** — **28px w800**, `letter-spacing -.02em`, `line-height 1.1`.
   La unidad, si la hay, en **15px w700 `textDisabled`** pegada.
3. **Qué significa** — **11px `textDisabled`**: el periodo, la fórmula, la
   comparación (`MXN · existencia × costo`, `bajo su umbral · 2 agotados`,
   `−8% contra agosto`).

**Variante de alarma**, cuando la cifra pide acción: borde y fondo teñidos, y
los tres textos en el tono oscuro del estado —
aviso: borde `#F2DCB0`, fondo `#FFFBF3`, textos `#8A5A0B` / `#A9812F`;
peligro: borde `#EBC4BF`, fondo `#FDF4F3`, textos `#C0392B` / `#B4675C`.

**Regla:** toda cifra derivada enseña su fórmula en una línea, y toda cifra de
dinero dice su moneda. Ninguna cifra se queda sola.

---

## Orden de trabajo

1. Los seis componentes, en `lib/core/widgets/`, con sus propias pruebas de widget.
2. Las pantallas, cada una según su `docs/diseno/<pantalla>-spec.md`.

Antes de reportar cualquier pantalla: **cero usos de `KuraColors`** en los
archivos tocados, y `flutter analyze` en 0.
