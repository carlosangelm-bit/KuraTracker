# Insumos › Reabasto

Guardar como `docs/diseno/reabasto-spec.md`.
Da por leído `sistema-componentes-spec.md`.

**Pantalla:** `lib/features/insumos/reabasto_screen.dart`.

## Los dos problemas de fondo

1. **La cantidad sugerida nunca explica de dónde sale.** Dice "+10" y la fórmula
   (`umbral × 2 − existencia`, mínimo 1) no aparece en ninguna parte de la
   pantalla. El admin no sabe si confiar en ella.
2. **Hay dos caminos para recibir mercancía** y conviven sin distinguirse
   visualmente: "Confirmar recepción" por artículo, que registra la entrada
   **sin ligarla al pedido y deja el pedido abierto indefinidamente**, y
   "Recibir" contra el pedido. Se queda **uno solo**: contra el pedido.

Además, los externos hoy no tienen stepper (su cantidad no es editable) mientras
los de tienda sí, sin razón.

---

## Encabezado

Igual que Inventario: migaja `Insumos`, título **28px w800** → `Reabasto`,
y el selector de sitio a la derecha.

## Pedidos por recibir

Tarjeta `padding 22px 24px`, `gap 16`. Solo si hay pedidos abiertos.

Encabezado (`gap 3`): **17px w700** → `Pedidos por recibir`; **12px
`textSecondary`** →
`Cierra la recepción contra el pedido, no artículo por artículo: así el pedido se cierra solo.`

Una caja por pedido: borde `1px border`, `radius 12`, `padding 16px 18px`,
`gap 20`, en fila:

- Izquierda (`gap 6`): fila con **14px w700** `Pedido del 9 de septiembre` y
  pastilla `Parcial` (fondo `#FFF6E6`, texto `#8A5A0B`, **11px w700**) cuando
  aplique; **12px `textSecondary`** con las partidas
  (`Mepilex Border Flex 10/10 · Alginato de calcio 4/12 · Película barrera 0/6`);
  **barra de avance** alto **6px**, `radius 30`, riel `chipBg`, relleno
  `brandPrimary` al porcentaje de piezas recibidas, `margin-top 2`; y
  **11px `textDisabled`** → `14 de 28 piezas recibidas`.
- Derecha (`gap 9`): `Cancelar` como texto plano `textSecondary` **12px w700**;
  `Recibir` primario **12px w700**, `padding 9px 16px`.

## Bajo su umbral — la tabla del pedido nuevo

Tarjeta `padding 22px 24px 8px 24px`, `gap 16`.

Encabezado (`justify: space-between`, base inferior): izquierda (`gap 3`)
**17px w700** → `Bajo su umbral`, y **12px `textSecondary`** →
`La cantidad sugerida te devuelve al doble del umbral: umbral × 2 − existencia. Puedes cambiarla.`
con la fórmula en **w700 `textPrimary`**. Derecha: **12px `textDisabled`** →
`7 artículos · 2 agotados`.

Tabla (`KuraDataTable`) con selección múltiple:

| Columna | Ancho | Alineación | Contenido |
|---|---|---|---|
| casilla | 34px | — | selección; el encabezado selecciona todo |
| Artículo | 30% | izq | cuadro 30×30 + nombre **13px w600** + proveedor **11px `textDisabled`** |
| Origen | 13% | izq | pastilla `Tienda Kura+` / `Externo` |
| Existencia | 10% | der | **15px w800** coloreada |
| Umbral | 9% | der | **13px `textSecondary`** |
| Pedir | 15% | izq | stepper `−` / cantidad / `+` |
| Costo | 10% | der | 13px |
| Subtotal | 11% | der | **13px w700** |

**Stepper de fila:** botones **28×28**, `radius 8`, borde `1px border`, fondo
`surface`, texto **15px w700**; cantidad **15px w800**, `min-width 20`,
centrada; `gap 8`. Mínimo 1. **Los externos llevan stepper igual que los de
tienda** — hoy no lo tienen.

Una fila **no seleccionada** se atenúa: nombre en `textSecondary`, cuadro de
ícono con fondo `background` y borde.

**Fila de totales:** `3 de 7 seleccionados · 42 piezas` en **12px w700
`textSecondary`**, y a la derecha `Total` + la suma en **15px w800**.

## Pie de la pantalla

Fila `gap 16`:

- Nota (ocupa el espacio libre): tarjeta `radius 12`, `padding 15px 18px`,
  ícono 18px `textSecondary`, texto **12px `textSecondary`** `line-height 1.5` →
  `Los externos no salen en el carrito: se compran con su proveedor. Van en el pedido para que no se te olviden y para cerrar su recepción aquí mismo.`
  con **externos** en **w700 `textPrimary`**.
- Botón primario, no se encoge: **15px w700**, `padding 15px 26px` →
  `Armar pedido · $3,304.00` (el total de lo seleccionado, en el propio botón).

Debajo, el mismo **aviso de artículos sin umbral** que en Inventario, con el
mismo copy y el mismo botón `Fijarlo en lote`. Es el aviso más importante de la
pantalla: sin umbral, el artículo **nunca aparece aquí aunque se agote**.

## Estados

- **Vacío feliz** (`KuraEmptyState`, con ícono de palomita `statusSuccess`):
  título `Todo con existencia suficiente`; texto
  `No hay artículos bajo su umbral de reorden.` Si hay artículos sin umbral,
  el aviso sigue visible debajo — es precisamente el caso en que el vacío puede
  ser mentira.
- **Error**, **sin módulo** y **sin rol**: igual que Inventario.

## Comportamiento

- Al armar el pedido: los de tienda van al carrito de Shopify y abren el checkout
  en el navegador; los externos entran al `SupplyOrder` como partidas a recibir,
  sin pasar por el carrito.
- **Se elimina** la acción "Confirmar recepción" por artículo. La recepción se
  hace siempre contra un pedido.
