# Insumos › Inventario

Guardar como `docs/diseno/inventario-spec.md`.
Da por leído `sistema-componentes-spec.md`.

**Pantalla:** `lib/features/insumos/inventario_screen.dart`.

## El problema que resuelve

Es el peor caso de dato tabular servido como lista: artículo × origen ×
existencia × umbral × costo × precio × valor, todo aplastado en un subtítulo de
11px unido con " · ". Sin buscador, sin filtros, sin orden, sin totales. Un
centro con 200 SKU hace scroll infinito. Y las cuatro acciones pesadas viven en
`IconButton` sin etiqueta del AppBar, invisibles en móvil.

---

## Encabezado

`padding 30px 40px 44px`, `gap 20` entre bloques.

Izquierda (`gap 8`): migaja — flecha 17px `textSecondary` + **13px w600
`textSecondary`** `Insumos`; debajo título **28px w800** `letter-spacing -.02em`
→ `Inventario`.

Derecha: **selector de sitio** — fondo `surface`, borde `1px border`,
`radius 30`, `padding 9px 16px`, `gap 9`: pin 15px `brandPrimary`, nombre del
sitio **13px w700**, chevron 13px `textSecondary`. Solo si hay más de un sitio
y el alcance es por sitio.

## Fila de cifras — cuatro `KuraStat`

| Etiqueta | Cifra | Qué significa | Variante |
|---|---|---|---|
| `Artículos` | conteo | `en esta sede` | normal |
| `Por reordenar` | conteo bajo umbral | `bajo su umbral · N agotados` | aviso |
| `Valor a costo` | suma | `MXN · existencia × costo` | normal |
| `Consumo del mes` | piezas + `pz` | `−8% contra agosto` | normal |

"Valor" **tiene que decir a costo**, y su fórmula: hoy no dice si es a costo o a
precio de venta, ni de qué periodo.

## Barra de acciones (`KuraActionBar`)

Tarjeta `padding 18px 22px`, `gap 16`.

- Buscador: `Buscar por nombre, SKU o proveedor`.
- Primaria: `Agregar artículo`.
- `Más acciones` abre, **con nombre completo** (hoy son cuatro íconos sin
  etiqueta): `Sincronizar existencias con Shopify`,
  `Fijar umbral de reorden en lote`, `Descargar catálogo en CSV`, `Cargar CSV`.
- Filtros con conteo: `Todos · 48`, `Bajo umbral · 7`, `Agotados · 2`,
  `Tienda Kura+ · 37`, `Externos · 11`, `Sin umbral · 5`.
  A la derecha `Mostrando 48 de 48`.

## Tabla (`KuraDataTable`)

Tarjeta `padding 22px 24px 8px 24px`.

| Columna | Ancho | Alineación | Contenido |
|---|---|---|---|
| Artículo | 30% | izq | cuadro 30×30 `radius 7` + nombre **13px w600** + proveedor · SKU en **11px `textDisabled`** |
| Origen | 13% | izq | pastilla `Tienda Kura+` (normal) / `Externo` (atenuada, punteada) |
| Existencia | 11% | der | **15px w800** coloreada + `pz` en 11px |
| Umbral | 9% | der | **13px `textSecondary`**; sin fijar → `sin fijar` en **12px `textDisabled`** cursiva |
| Costo | 10% | der | 13px |
| Precio | 10% | der | **13px `textSecondary`** |
| Valor | 10% | der | **13px w700** |
| — | 7% | der | acción rápida `Entrada`/`Salida` en **12px w700 `brandPrimary`** |

Color de la existencia: `statusDanger` si ≤ 0, `statusWarning` si ≤ umbral,
`statusSuccess` si no. Un artículo **sin umbral no se pinta de aviso**: no tiene
contra qué compararse.

**Fila de totales:** `N artículos` · total de piezas · y el **Valor** sumado en
**15px w800**.

## Avisos al pie

Dos, en fila de dos columnas `gap 16`:

1. **Aviso (variante de alarma, tono aviso)** — `radius 12`, fondo `#FFFBF3`,
   borde `1px #F2DCB0`, `padding 15px 18px`: título **13px w700 `#8A5A0B`** →
   `N artículos no tienen umbral fijado`; **11px `#A9812F`** →
   `Sin umbral nunca aparecen en Reabasto, aunque se agoten.`;
   botón `Fijarlo en lote` fondo `#8A5A0B`, blanco, **12px w700**.
   **Esto es una fuga silenciosa que hoy nadie ve**: sin umbral, el artículo
   nunca entra a Reabasto.
2. **Estado de Shopify** — tarjeta normal: `Sincronizado con Shopify hace 14 min`
   **13px w700** y `El stock es el mismo para todo el centro.` **11px
   `textSecondary`**; a la derecha `Sincronizar` en **12px w700 `brandPrimary`**.
   Solo si el centro usa espejo.

## Estados

- **Vacío** (`KuraEmptyState`): título `Todavía no hay artículos en esta sede`;
  texto `Agrega productos de tu tienda o captura los que compras con otro proveedor. Si ya los tienes en una hoja, súbelos de una vez.`;
  botones `Agregar artículo` y `Cargar CSV`.
- **Error**: `KuraErrorState` con `No pudimos cargar el inventario`.
- **Sin módulo**: densidad (c) del `KuraModuleLock`, con el precio de Insumos de
  `billing_catalog` y botón a Licencias. Hoy es una línea de texto gris suelta
  sin ícono ni salida.
- **Sin rol de compra**: se mantiene el mensaje actual, pero con el layout del
  `KuraEmptyState`.

## Pendientes

- **Marca de tiempo del sync de Shopify.** El aviso "Estado de Shopify" quiere decir
  `Sincronizado con Shopify hace 14 min`, pero hoy el repositorio **no expone un
  `synced_at`** del último sync. Implementado con **texto genérico de respaldo**
  (`Sincronizado con Shopify`, sin "hace N min"). Para el "hace N min" hace falta
  persistir la hora del último `syncShopifyInventory` (columna/al vuelo) y leerla aquí.
- **"Sin rol de compra"** sigue usando `purchaseDeniedScaffold` (compartido con Tienda /
  Reabasto / Consumo / Mapeo). Migrarlo al layout de `KuraEmptyState` es un cambio
  transversal a esas pantallas → su propio hilo, no este.
