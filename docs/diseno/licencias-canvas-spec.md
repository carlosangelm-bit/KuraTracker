# Licencias — especificación exacta del canvas

Guarda este archivo en el repo como `docs/diseno/licencias-canvas-spec.md`.

Cada valor de aquí sale del canvas aprobado. **No son sugerencias: son los valores.**
Donde dice un hex, un tamaño o un peso, se usa ese. Todos existen ya en
`lib/core/design/tokens.dart` (`BrandTokens`, `AppSpacing`, `AppRadii`, `AppType`),
así que se toman de ahí — nunca `KuraColors`, nunca literales sueltos.

Marca clínica como referencia; en hospital y cuidadores cambian solo los tokens de
marca (`brandPrimary`, `heroTop`, `heroBottom`, `background`, `textPrimary`,
`textSecondary`, `textDisabled`, `border`). Los de estado (#1B8A5A, #E8A93A, #C0392B)
son iguales en las tres.

Nota de alcance: entre HTML y Flutter hay diferencias de render tipográfico que no se
pueden eliminar. "Idéntico" aquí significa: misma estructura, mismos tokens, mismos
tamaños, pesos, espaciados, radios y jerarquía. Un `hover` del canvas no aplica en móvil.

---

## 1. HERO

Contenedor: `borderRadius 24` · gradiente **150°** de `#241B4E` a `#5B3AC7` ·
`padding 32` · fila con `alignment: flex-start`, `justify: space-between`, `gap 40`.

### Columna izquierda (`gap 18`)

**a) Fila de estado** (`gap 10`) — hoy no existe:

- Pastilla: `padding 4/12`, `radius 30`, fondo `rgba(255,255,255,.16)`,
  borde `1px rgba(255,255,255,.22)`. Dentro: palomita 13px blanca
  (`stroke-width 2.4`) + texto **12px w700 blanco**, `letter-spacing .02em`.
  Texto: `Suscripción activa` · en prueba: `Prueba · quedan N días` ·
  vencida: `Prueba terminada` · impago: `Pago vencido`.
- A su derecha, texto **12px w500 `rgba(255,255,255,.7)`**:
  `Plan mensual · renueva el 12 de octubre` (fecha real de `current_period_end`).

**b) Importe** — fila con `alignment: baseline`, `gap 12`:

- Cifra: **44px w800 blanco**, `letter-spacing -.02em`.
- A su derecha: **15px w600 `rgba(255,255,255,.78)`** → `al mes · IVA incluido`
  (o `al año · IVA incluido`).

**c) Pastillas de conceptos** — `flex-wrap`, `gap 10`. Cada una:
`padding 5/12`, `radius 30`, fondo `rgba(255,255,255,.12)`, texto **12px w600 blanco**.
Una por concepto contratado: `5 asientos clínicos`, `3 Protocolo Kura+`,
`Administración avanzada`, `Insumos`, `Comercial`.

> Hoy los conceptos van como texto plano separado por `·`. Deben ser pastillas.

### Columna derecha (`min-width 220`, `gap 10`, estirada)

1. Botón primario: fondo `#FFFFFF`, texto `#241B4E` **14px w700**, `radius 30`,
   `padding 13/22`. Etiqueta `Cambiar mi plan`.
2. Botón secundario — hoy no existe: fondo transparente, borde
   `1px rgba(255,255,255,.32)`, texto blanco **13px w600**, `radius 30`,
   `padding 11/22`. Etiqueta `Facturas y recibos`.
3. Pie: **11px `rgba(255,255,255,.62)`**, centrado, `padding-top 2` →
   `Pago seguro con Stripe`.

En techo del autoservicio el botón 1 pasa a `Solicitar cotización asistida` y
**el importe se sustituye por `Cotización a la medida`** (arriba de 5 asientos el
precio es por volumen: no se muestra precio de lista).

---

## 2. TARJETA "Lo que tienes contratado"

Tarjeta: fondo `#FFFFFF`, borde `1px #E7E4F0`, **`radius 24`**, `padding 28/32`.

### Encabezado (hoy no existe) — `padding-bottom 20`, `justify: space-between`, base inferior

- Izquierda (`gap 4`): título **22px w700**, `letter-spacing -.01em` →
  `Lo que tienes contratado`; subtítulo **13px `#6B6577`** →
  `La licencia es por persona, no por rol: quien es clínico y administrador a la vez paga una sola vez.`
- Derecha: enlace **13px w700 `#7C3AED`** `Ver comparativa de planes` + flecha
  diagonal 14px (`stroke-width 2.2`).

### Tabla

Encabezados: **11px w700**, `letter-spacing .06em`, MAYÚSCULAS, `#6B6577`,
`padding 0 0 10px 0`, alineados a la izquierda salvo los dos últimos.

Celdas: `padding 14px 0`, **`border-top: 1px #E7E4F0`** (línea arriba de cada fila,
no debajo), `vertical-align: middle`.

Anchos: `Concepto 30%` · `Uso 26%` · `Contratado 16%` ·
`Precio unitario 14%` (derecha) · `Subtotal 14%` (derecha).

**Celda Concepto** — `gap 12`:
cuadro de ícono **34×34**, `radius 8`, fondo `#EFEDF7`, SVG 18px `#7C3AED`;
al lado (`gap 2`) nombre **14px w700** y descripción **11px `#6B6577`**.

| Fila | Descripción |
|---|---|
| Asiento clínico | `Expediente, agenda, reportes, prevención, VAC` |
| Protocolo Kura+ | `Pronóstico A/B/C, Sheehan, medición por foto` |
| Cupo administrativo | `Sin rol clínico · 3 incluidos en Administración avanzada` |
| Cuidadores | `Acceso del cuidador en casa` |

**Celda Uso** — `padding-right 28`, `gap 7`. Esta es la diferencia visual más grande
contra lo que está hoy:

- Fila base: número **15px w700** + texto **12px `#6B6577`**
  (`de 5 en uso`, `de 3 asignadas`, `activos`).
- Debajo, **barra de progreso**: alto **6px**, `radius 30`, riel `#EFEDF7`,
  relleno `#7C3AED` al porcentaje usado/contratado. En `Cuidadores` no hay barra
  (no tiene tope).

**Celda Contratado**: número **15px w700**; cuando no aplica, texto **13px `#6B6577`**
(`sin límite`).

**Precio unitario** (derecha): **14px `#6B6577`** → `$400`, `$300`, `$0`.
En `Cupo administrativo` dice literalmente **`incluidos`**, 13px `#6B6577`.

**Subtotal** (derecha): **15px w700** → `$2,000`, `$900`.
En `Cupo administrativo` y `Cuidadores` es **`—`**, 14px `#6B6577`.

> Regla dura: el cargo del módulo Administración avanzada aparece **una sola vez**,
> en su tarjeta de módulo. La fila `Cupo administrativo` no lleva subtotal.
> La suma de los subtotales de la tabla **más** los precios de las tarjetas de módulo
> debe dar exactamente el importe del hero. Hoy da $5,900 contra $4,700.

---

## 3. MÓDULOS DEL CENTRO

Encabezado fuera de tarjeta, `justify: space-between`, base inferior, `gap 14` con
la reja: título **22px w700** `letter-spacing -.01em` → `Módulos del centro`;
a la derecha **13px `#6B6577`** → `Se cobran por centro, no por persona`.

**Reja de 3 columnas, `gap 16`.** Hoy es una lista vertical de ancho completo: cambia.

### Tarjeta de módulo contratado

Fondo `#FFFFFF`, borde `1px #E7E4F0`, `radius 16`, `padding 22`, `gap 14`.

- Fila superior (`justify: space-between`, `gap 12`, arriba):
  - Izquierda (`gap 12`): cuadro **38×38**, `radius 8`, fondo `#EFEDF7`, SVG 20px
    `#7C3AED`; al lado (`gap 1`) nombre **15px w700** y precio **12px `#6B6577`**
    → `$1,200 / mes · 3 usuarios incluidos`, `$1,400 / mes`, `$900 / mes`.
  - Derecha: pastilla de estado — `padding 4/10`, `radius 30`, fondo `#EFEDF7`,
    punto **6×6** `radius 30` color `#1B8A5A`, texto **11px w700 `#201A2E`** `Activo`.
- Descripción: **12px `#6B6577`**, `line-height 1.5`:
  - Administración avanzada → `Tus propios protocolos y catálogos, varias sedes, marca propia y Acuity. Incluye 3 personas administrativas sin pagar asiento clínico.`
  - Insumos → `Tienda, inventario, mapeo insumo↔producto, consumo por paciente y reabasto.`
  - Comercial → `Cobros, métodos de pago, ingresos del centro y facturación.`

### Tarjeta de módulo NO contratado

Igual, pero: **borde `1px dashed #E7E4F0`**; cuadro de ícono con fondo `#F6F5FB` y
SVG `#AEA9BC`; nombre **15px w700 `#6B6577`**; precio **12px `#AEA9BC`**;
descripción **12px `#AEA9BC`**; y en lugar de la pastilla, botón
`Agregar` — fondo `#7C3AED`, texto blanco **12px w700**, `radius 30`, `padding 7/16`.

---

## 4. TARJETA "Ya viene incluido con tus asientos clínicos"

Va **arriba de la reja de módulos**. Hoy es un panel verde de ancho completo en una
sola columna: cambia a tarjeta blanca en dos columnas.

Fondo `#FFFFFF`, borde `1px #E7E4F0`, `radius 16`, `padding 24`, `gap 16`.

- Encabezado, `justify: space-between`, base: título **15px w700** →
  `Ya viene incluido con tus asientos clínicos`; derecha **12px w700 `#1B8A5A`** →
  `Sin costo`.
- **Reja de 2 columnas**, `gap 12px 24px`. Cada ítem: palomita SVG **17px `#1B8A5A`**
  (`stroke-width 2.6`, `margin-top 2`, no se encoge) + texto **12px**, `line-height 1.5`:
  1. `Dar de alta a tu equipo clínico, con sus roles y su cédula.`
  2. `Datos fiscales, método de pago, facturas y esta misma pantalla.`
  3. `Encender el Protocolo Kura+ y las escalas curadas, y cargar el catálogo base.`
  4. `Exportar el expediente y el registro de divulgaciones. Tu sede.`
- Nota final (hoy no existe): **11px `#AEA9BC`**, `line-height 1.5` →
  `Un centro puede operar solo con licencias clínicas. Lo que la ley te exige poder hacer con tu expediente nunca depende de un módulo.`

---

## 5. TARJETA "Quién usa el Protocolo Kura+"

Hoy no existe. Debe salir **siempre** que haya asientos clínicos, aunque haya
0 licencias Kura+ contratadas (todos los interruptores apagados).

Tarjeta: `#FFFFFF`, borde `1px #E7E4F0`, `radius 24`, `padding 28/32`.

- Encabezado `padding-bottom 18`, `justify: space-between`, base:
  izquierda (`gap 4`) título **22px w700** `letter-spacing -.01em` →
  `Quién usa el Protocolo Kura+`, subtítulo **13px `#6B6577`** →
  `Se compran por centro y se asignan por persona. Tienes N asignadas de M.`;
  derecha botón — fondo `#EFEDF7`, texto `#7C3AED` **13px w700**, `radius 30`,
  `padding 10/18` → `Comprar otra licencia`.
- Tabla, mismos estilos de `th`/`td` que la sección 2.
  Anchos: `Persona 38%` · `Rol 24%` · `Asiento 22%` · `Kura+ 16%` (derecha).
  - **Persona** (`gap 12`): avatar circular **32×32**, `radius 30`, fondo `#EFEDF7`,
    iniciales **12px w700 `#7C3AED`**; al lado (`gap 1`) nombre **14px w600** y
    correo **11px `#6B6577`**. Si la persona no tiene Kura+, el avatar va con fondo
    `#F6F5FB` e iniciales `#AEA9BC`.
  - **Rol**: pastilla `padding 4/10`, `radius 30`, fondo `#EFEDF7`,
    texto **12px w600 `#201A2E`** (`Clínico · Admin`, `Clínico`, `Enfermería`).
    Para administrativo puro: fondo `#F6F5FB`, texto `#6B6577`, etiqueta `Administrativo`.
  - **Asiento**: **13px `#6B6577`** → `Clínico` o `Cupo admin`.
  - **Kura+** (derecha): interruptor **40×23**, `radius 30`, `padding 2`,
    knob **19×19** blanco `radius 30`. Encendido: track `#7C3AED`, knob a la derecha.
    Apagado: track `#EFEDF7`, knob a la izquierda, y a su izquierda (`gap 10`)
    texto **11px `#AEA9BC`** `sin licencia`. Para administrativo puro no hay
    interruptor: solo **11px `#AEA9BC`** `no aplica`.

---

## 6. "ARMA TU PLAN" — configurador

Página: `padding 32/40`. **Dos columnas**, `gap 24`, alineadas arriba:
izquierda flexible, derecha **fija 400px**.

Migaja arriba, `padding-bottom 22`, `gap 12`: flecha 18px `#6B6577`
(`stroke-width 2.2`) + texto **14px w600 `#6B6577`** `Licencias`.

### Izquierda (`gap 20`)

**Encabezado** (`gap 6`): `Arma tu plan` **28px w800** `letter-spacing -.02em`;
debajo **14px `#6B6577`** →
`Los cambios se aplican al confirmar el pago. Si ya tienes suscripción, se ajusta y el prorrateo aparece en tu próxima factura.`

**Tarjeta Periodicidad** — hoy es una barra segmentada suelta arriba; debe ser tarjeta.
`#FFFFFF`, borde `1px #E7E4F0`, `radius 16`, `padding 20/24`,
`justify: space-between`, `gap 24`:

- Izquierda (`gap 2`): `Periodicidad` **15px w700**; debajo **12px `#6B6577`** →
  `El plan anual se cobra como 10 meses: dos meses sin costo.`
- Derecha: cápsula contenedora — fondo `#F6F5FB`, `radius 30`, `padding 4`, `gap 4`.
  Botón activo: fondo `#FFFFFF`, texto `#201A2E` **13px w700**, `radius 30`,
  `padding 9/18`. Inactivo: fondo transparente, texto `#6B6577` **13px w600**.
  Etiquetas: `Mensual` y `Anual · 2 meses gratis`.

**Tarjeta Personas** — `radius 16`, `padding 24`, `gap 20`.
Título `Personas` **15px w700**.

Cada fila (`justify: space-between`, `gap 24`):

- Izquierda (`gap 14`): cuadro **40×40**, `radius 8`, fondo `#EFEDF7`, SVG 20px
  `#7C3AED`; al lado (`gap 2`) nombre **14px w700** y descripción **12px `#6B6577`**:
  - `Asientos clínicos` → `$400 por persona al mes · expediente, agenda, reportes, prevención, VAC`
  - `Protocolo Kura+` → `$300 por persona al mes · pronóstico A/B/C, Sheehan, medición por foto`
- Derecha (`gap 14`): **subtotal de la línea** — **14px w700 `#6B6577`**,
  `min-width 72`, alineado a la derecha (hoy no existe) — y luego el stepper
  (`gap 10`): botón `−`, contador, botón `+`.
  - Botón del stepper: **34×34**, `radius 8`, borde `1px #E7E4F0`, fondo `#FFFFFF`,
    texto `#201A2E` **18px w700**; al pasar el cursor, fondo `#EFEDF7`.
  - Contador: **20px w800**, `min-width 28`, centrado.

Separador entre las dos filas: **1px `#E7E4F0`**.

Bajo la fila de Kura+, nota **11px `#AEA9BC`** →
`Nunca más que asientos clínicos: Kura+ se asigna a una persona que atiende.`

**Aviso de tope** — dentro de esta tarjeta, **al llegar a 5 asientos** (hoy solo
aparece a 6 y en el panel derecho): caja `radius 8`, fondo `#F6F5FB`,
`padding 14/16`, `gap 10`; ícono 18px `#7C3AED`; texto **12px**, `line-height 1.5`:
`**Cinco es el máximo que puedes contratar tú mismo.** A partir del sexto lo armamos contigo: hay precio por volumen y acompañamiento en la migración de expedientes.` +
enlace **w700** `Pedir cotización`. La primera oración va en **w700**.

**Tarjeta Módulos** — `radius 16`, `padding 24`, `gap 18`.
Encabezado con base alineada: `Módulos del centro` **15px w700** y a la derecha
**12px `#6B6577`** → `Precio por centro, sin importar cuántas personas sean`.

Cada módulo (`justify: space-between`, `gap 24`):

- Izquierda (`gap 3`): nombre **14px w700** con el precio en la misma línea como
  **11px w600 `#6B6577`** → `Administración avanzada · $1,200 · incluye 3 usuarios administrativos`;
  debajo descripción **12px `#6B6577`**.
- Derecha: interruptor **46×27**, `radius 30`, `padding 3`, knob **21×21** blanco.
  Encendido `#7C3AED` con knob a la derecha; apagado `#EFEDF7` con knob a la izquierda.
  **Ningún módulo se bloquea.**

### Derecha (`width 400`, `gap 16`)

**Tarjeta resumen**: `#FFFFFF`, borde `1px #E7E4F0`, **`radius 24`**, `padding 28`, `gap 20`.

- `Tu plan` **17px w700**.
- Líneas (`gap 12`), cada una `justify: space-between`, base, `gap 16`:
  etiqueta **13px `#6B6577`** (`3 × asiento clínico`, `2 × Protocolo Kura+`,
  `Administración avanzada`, `Insumos`, `Comercial`) y valor **13px w600**.
- **Solo en anual**, fila destacada: `padding 10/12`, `radius 8`, fondo `#EFEDF7`,
  ambos textos **12px w700 `#201A2E`** → izquierda
  `Plan anual · se cobra como 10 meses`, derecha `{mensual} × 10`.
  Las líneas de arriba **siguen siendo mensuales** en ese modo.
- Separador **1px `#E7E4F0`**.
- Bloque total (`justify: space-between`, base inferior, `gap 16`):
  - Izquierda (`gap 2`): `TOTAL` **12px w700**, MAYÚSCULAS, `letter-spacing .06em`,
    `#6B6577`; debajo **11px `#AEA9BC`** → `al mes` o `al año · equivale a 10 meses`.
  - Derecha, alineada a la derecha: cifra **34px w800** `letter-spacing -.02em`;
    debajo **11px `#6B6577`** → `IVA incluido`.
- Caja de cambio: `padding 12/14`, `radius 8`, fondo `#F6F5FB`, `gap 8`;
  ícono 16px `#6B6577`; texto **12px `#201A2E`**:
  `Subes $X al mes. El prorrateo aparece en tu próxima factura.` /
  `Bajas $X al mes. El ajuste se refleja en tu próxima factura.` /
  `Es exactamente tu plan actual. Mueve algo para ver el cambio.`
- Botón ancho completo: fondo `#7C3AED`, texto blanco **15px w700**, `radius 30`,
  `padding 15/24` → `Continuar al pago`.
- Pie centrado (`gap 7`): candado 13px `#AEA9BC` + texto **11px `#AEA9BC`** →
  `Pago seguro con Stripe · cancela cuando quieras`.

**Tarjeta bajo el resumen** — hoy no existe: borde `1px #E7E4F0`, `radius 16`,
`padding 18/20`, `gap 6`; título **13px w700** → `Si cancelas, tu expediente no se va`;
texto **12px `#6B6577`**, `line-height 1.5` →
`Todo queda consultable y exportable. Lo que se cierra es dar de alta pacientes y editar; nada se borra.`

---

## 7. Verificación

Antes de reportar, comprobar en el sandbox:

1. La suma de los subtotales de la tabla **más** los precios de las tarjetas de
   módulo es **exactamente** el importe del hero. Test que lo fije.
2. 5 asientos + 5 Kura+ + los tres módulos = **$7,000/mes** y **$70,000/año**.
3. A **5** asientos aparece el aviso de tope dentro de la tarjeta Personas.
   A **6**, el hero deja de mostrar precio y dice `Cotización a la medida`.
4. Apagar Administración avanzada baja el total exactamente $1,200.
5. Cero usos de `KuraColors` en los archivos tocados.
