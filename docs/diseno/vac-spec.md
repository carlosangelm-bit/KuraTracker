# Terapia VAC — lista y detalle

Guardar como `docs/diseno/vac-spec.md`.
Da por leído `sistema-componentes-spec.md`.

**Pantallas:** `lib/features/vac/vac_therapies_screen.dart` y
`vac_therapy_detail_screen.dart`.

## El problema que resuelve

No es que se vean pobres: **no comunican lo urgente.** Hoy una terapia sana y una
con el apósito vencido hace nueve horas se ven exactamente igual. No hay
antigüedad, ni alarmas recientes, ni el cruce que importa.

**El dato para hacerlo ya existe y ninguna pantalla lo cruza:** el intervalo de
cambio de apósito (`changeIntervalHours`, que sí se captura en el formulario) y
la fecha del último evento de cambio en la bitácora. Cruzarlos convierte una
lista plana en un tablero de guardia. Ese cruce es el corazón de este rediseño.

Segundo problema: en el detalle hay **seis `OutlinedButton` idénticos en un
`Wrap`**, donde "Agregar nota" pesa visualmente lo mismo que "Finalizar";
"Suspender" no pide confirmación y "Finalizar" sí.

---

# A · Lista (`/vac`)

`padding 30px 40px 44px`, `gap 20`.

## Encabezado

Izquierda (`gap 5`): **28px w800** → `Terapia VAC`; **14px `textSecondary`** →
`Presión negativa: qué equipo trae cada paciente, con qué parámetros y qué necesita atención hoy.`
Derecha: botón primario **14px w700**, `padding 13px 22px` → `Nueva terapia`.

## Fila de cifras — cuatro `KuraStat`

| Etiqueta | Cifra | Qué significa | Variante |
|---|---|---|---|
| `Terapias activas` | conteo | `en N ubicaciones` | normal |
| `Cambio de apósito vencido` | conteo | `pasaron sus horas programadas` | **peligro** |
| `Alarmas en 7 días` | conteo | `N escalada a guardia` | **aviso** |
| `Suspendidas` | conteo | `esperan decisión` | normal |

`Suspendidas` se separa de `Finalizadas`: hoy están en la misma bolsa
("Finalizadas / suspendidas"), y una suspendida **requiere acción** mientras una
finalizada es archivo.

## Barra de acciones

Buscador `Buscar por paciente, piso, área o cama` (con plegado de acentos, como
ya hace el selector de paciente). Filtros con conteo: `Activas · 9`,
`Requieren atención · 3`, `Suspendidas · 1`, `Finalizadas · 14`.

## Tabla (`KuraDataTable`)

| Columna | Ancho | Alineación | Contenido |
|---|---|---|---|
| Paciente | 22% | izq | avatar **30×30** `radius 30` + nombre **13px w600** |
| Equipo | 16% | izq | **13px `textSecondary`** → `V.A.C. Ulta`, `ActiV.A.C.` |
| Parámetros | 20% | izq | **13px `textSecondary`** → `−125 mmHg · Continua` |
| Ubicación | 15% | izq | pastilla `chipBg` |
| Día | 9% | der | **13px w700** — días desde `startedAt` |
| Próximo cambio | 18% | izq | pastilla de estado (abajo) |

**Pastilla de "Próximo cambio"** — el cruce:

| Situación | Fondo | Texto | Copy |
|---|---|---|---|
| ya pasó | `#FBEDEB` | `#C0392B` | `Vencido hace 9 h` |
| dentro de 6 h | `#FFF6E6` | `#8A5A0B` | `En 4 h` |
| más lejos | `#E8F4EE` | `#1B8A5A` | `En 38 h` o `Mañana 08:00` |

El **avatar toma el mismo tono** que su pastilla (fondo `#FBEDEB` con iniciales
`#C0392B`, etc.), para que la urgencia se lea de un vistazo recorriendo la
primera columna.

Orden por defecto: **lo vencido primero**, luego por proximidad del cambio.
No por `startedAt` descendente, que es lo que hace hoy.

Nota al pie, tarjeta `radius 12`, `padding 15px 18px`, ícono 18px
`textSecondary`, texto **12px `textSecondary`** `line-height 1.5`:
`"Próximo cambio" sale de dos datos que ya capturas: el intervalo de cambio de apósito de la terapia y la fecha del último cambio en su bitácora.`

## Estados

- **Vacío** (`KuraEmptyState`): `Sin terapias VAC registradas`, texto
  `Al registrar una terapia vas a ver aquí sus parámetros, sus alarmas y cuándo toca el próximo cambio de apósito.`, botón `Nueva terapia`.
- **Sin pacientes al crear**: diálogo, no snackbar.
- **Modo lectura**: la lista lo detecta y **oculta el botón `Nueva terapia`**.
  Hoy no lo detecta: el botón sigue visible y el fallo sale al guardar.

---

# B · Detalle (`/vac/:id`)

`padding 30px 40px 44px`, `gap 20`. Migaja arriba: flecha + **13px w600
`textSecondary`** → `Terapia VAC`.

## Encabezado

Tarjeta `radius 24`, `padding 26px 30px`, en fila, `justify: space-between`,
`gap 32`:

- Izquierda (`gap 8`): fila con nombre del paciente **24px w800**
  `letter-spacing -.02em`, pastilla de estado (`Activa` verde / `Suspendida`
  roja / `Finalizada` neutra) y **13px `textSecondary`** → `Día 6 de terapia`.
  Debajo, **13px `textSecondary`** con la línea completa del equipo →
  `V.A.C. Ulta · −125 mmHg · Continua · GranuFoam (negra) · Hospitalización`.
- Derecha, **solo si el cambio está vencido o próximo**: caja `radius 12`,
  `padding 14px 18px`, `gap 14`, fondo y borde del tono del estado
  (vencido: `#FBEDEB` / `#EBC4BF`); reloj 20px del color; título **13px w700**
  → `Cambio de apósito vencido hace 9 h`; **11px** → `Programado cada 48 h · último el 10/09 a las 07:30`;
  y botón del color del estado **12px w700** → `Registrar cambio`.

El nombre del paciente es un enlace a su expediente (hoy va subrayado con un
ícono de "abrir en otra"; basta el color de marca y el cursor).

## Cuerpo — dos columnas, `gap 20`, izquierda flexible, derecha **400px**

### Izquierda

**Dos accesos grandes** (reja de 2, `gap 16`) — no seis botones iguales:

| Tarjeta | Cuadro 42×42 `radius 10` | Título 15px w700 | Subtítulo 12px `textSecondary` |
|---|---|---|---|
| Alarma | fondo `#FFF6E6`, ícono 21px `statusWarning` | `Atender una alarma` | `7 alarmas del equipo, con sus pasos.` |
| Asistente | fondo `chipBg`, ícono 21px `brandPrimary` | `Asesoría del equipo` | `Pregunta y, si hace falta, sales a guardia.` |

**Bitácora** — tarjeta `padding 26px 28px`, `gap 20`.
Encabezado: **19px w700** → `Bitácora`; **12px `textSecondary`** →
`El registro del episodio: quién hizo qué, cuándo y dónde.`;
a la derecha botón `Agregar nota` (fondo `chipBg`, `brandPrimary`, **12px w700**).

Es una **línea de tiempo agrupada por día**, no una lista de tarjetas:

- Encabezado de día: **11px w700**, `letter-spacing .04em`, MAYÚSCULAS,
  `textDisabled` → `HOY · 12 DE SEPTIEMBRE`, `10 DE SEPTIEMBRE`.
- Cada evento, en fila `gap 14`: columna izquierda con punto **10×10**
  `radius 30` y una línea vertical **2px `border`** que baja al siguiente;
  a la derecha (`gap 3`): tipo del evento **14px w700**; **12px
  `textSecondary`** con hora · ubicación · nota; y **11px `textDisabled`**
  con **el autor**, que hoy se guarda en `byProfile` y **nunca se muestra**.
- Color del punto: `statusWarning` alarma, `statusDanger` suspensión,
  `statusSuccess` colocación y reinicio, `brandPrimary` el resto.

### Derecha

**Parámetros** — tarjeta `radius 24`, `padding 26`, `gap 18`.
Encabezado con `Parámetros` **17px w700** y `Editar` **12px w700 `brandPrimary`**.
**Reja de 2 columnas**, `gap 16px 20px` — no filas clave/valor con `SizedBox(130)`,
que se rompen en móvil. Cada par: etiqueta **11px w700**, `letter-spacing .04em`,
MAYÚSCULAS, `textDisabled`; valor **14px w600**. Seis pares: `Presión`, `Modo`,
`Apósito`, `Cambio cada`, `N° de serie`, `Instilación`. Un valor ausente se pinta
`textDisabled` con su texto propio (`Sin instilación`), nunca `—` a secas.

**Indicaciones para el cuidador** — tarjeta `padding 22px 24px`, `gap 12`:
título **15px w700**; cuerpo **13px `textSecondary`** `line-height 1.55`;
`Editar` **12px w700 `brandPrimary`**. Vacío: el placeholder actual.

**Acciones** — tarjeta `padding 22px 24px`, `gap 12`. Título `Acciones`
**15px w700**. Cada acción es una fila: `padding 12px 14px`, borde `1px border`,
`radius 10`, fondo `surface`, ícono 17px, texto **13px w600**, `gap 10`.

Orden y jerarquía:

1. `Cambiar equipo` — ícono `brandPrimary`
2. `Egreso a domicilio` — ícono `brandPrimary`
3. separador `1px border`
4. `Suspender` — borde `#EBC4BF`, texto e ícono `statusDanger`
5. `Finalizar terapia` — borde `#EBC4BF`, texto e ícono `statusDanger`

Nota al pie **11px `textDisabled`** `line-height 1.5` →
`Suspender y finalizar piden confirmación. Las dos quedan en la bitácora con tu nombre.`
**Suspender hoy no confirma: ahora sí.**

`Cambio de apósito` deja de ser un botón suelto: vive en la caja del encabezado
cuando toca, y en el menú de la bitácora el resto del tiempo.

---

## Arreglos de comportamiento, no de pixeles

Estos importan más que el layout:

1. **`createVacTherapy`, `updateVacTherapy` y `addVacEvent` no llaman a
   `_assertCanWriteClinical`**, a diferencia de heridas y riesgo. El candado de
   escritura clínica **no cubre VAC**. Ponlo.
2. **Ninguna acción del detalle tiene `try/catch`**: en modo lectura o con RLS
   negando, el fallo es silencioso. Cada una debe mostrar el error.
3. **El formulario no valida nada**: presión y horas son `int.tryParse` y si
   fallan quedan nulas en silencio. Pásalo a `Form` + `TextFormField` con rangos.
4. **El verde de WhatsApp `#25D366` está escrito a mano en tres lugares y en tres
   tipos de botón distintos.** La acción más crítica del módulo necesita una sola
   identidad: un componente `KuraGuardiaButton`, un solo color, en un token.
5. El interruptor "Con instilación" duplica el valor `Con instilación (Veraflo)`
   que ya está en el dropdown de Modo. Deja uno.
