# Reportes

Guardar como `docs/diseno/reportes-spec.md`.
Da por leído `sistema-componentes-spec.md`.

**Pantalla:** `lib/features/reports/reports_screen.dart`.

## El problema que resuelve

Hoy no es un módulo, es un formulario: sin rango de fechas (siempre mete **todo**
el histórico — en un paciente con 30 consultas, un ladrillo), sin
previsualización, sin historial. La lista de pacientes es una caja de checkboxes
con la altura calculada a mano. Y la variante hospitalaria pierde todos los
controles y los sustituye por un párrafo de texto plano.

**El hallazgo que cambia el alcance:** el historial **ya existe**. Cada PDF llama
a `recordDataDisclosure` y queda registrado con fecha, tipo, autor y pacientes,
en la misma tabla del Registro de divulgaciones. Nadie lo muestra. No hay que
construirlo: hay que sacarlo a la pantalla.

---

## Layout

`padding 30px 40px 44px`, `gap 20`. Dos columnas, `gap 20`, alineadas arriba:
izquierda flexible, derecha **fija 400px**.

Encabezado: **28px w800** → `Reportes`; **14px `textSecondary`** →
`El documento que le entregas al paciente, a su médico tratante o a la aseguradora.`

---

## Izquierda · selección de pacientes

Tarjeta `padding 22px 24px 8px 24px`, `gap 16`.

Barra: buscador `Buscar por nombre o folio` **con plegado de acentos** (hoy no lo
tiene, así que "Ramirez" no encuentra a "Ramírez"; el selector de VAC sí lo hace).
Filtros con conteo: `Todos · 24`, `Míos · 9`, `Con herida activa · 17`.
En centro hospital: `Internados · N` en vez de los dos últimos.

Tabla (`KuraDataTable`) con selección múltiple:

| Columna | Ancho | Alineación | Contenido |
|---|---|---|---|
| casilla | 34px | — | selección; el encabezado selecciona todo |
| Paciente | 34% | izq | avatar **30×30** `radius 30` con iniciales **11px w700** + nombre **13px w600** |
| Folio | 16% | izq | **13px `textSecondary`** |
| Heridas activas | 20% | izq | pastilla `2 activas`; sin heridas → `cerrada` en **12px `textDisabled`** |
| Última consulta | 18% | izq | **13px `textSecondary`** en lenguaje relativo (`ayer`, `hace 3 días`, `hace 2 meses`) |
| Evidencias | 12% | der | **13px `textSecondary`** → `14 fotos` |

Avatar de un paciente no seleccionado: fondo `background`, iniciales
`textDisabled`.

## Izquierda · Reportes emitidos

Tarjeta `padding 22px 24px 8px 24px`, `gap 14`. **Se llena de
`data_disclosures`, que ya existe.**

Encabezado: **17px w700** → `Reportes emitidos`; **12px `textSecondary`** →
`Cada descarga queda registrada. Es la misma constancia del Registro de divulgaciones.`
A la derecha, **12px w700 `brandPrimary`** → `Ver el registro completo`
(navega al Registro de divulgaciones).

Tabla: `Fecha` 26% · `Tipo` 26% · `Quién lo generó` 26% · `Pacientes` 22% derecha.
Fecha en `dd/MM/yyyy HH:mm`; tipo con su etiqueta legible
(`Reporte clínico de herida`, `Reporte de prevención (LPP)`) — **nunca el `kind`
crudo de la base**, que es lo que hace hoy cuando no lo reconoce.

---

## Derecha · Qué va a incluir

Tarjeta `radius 24`, `padding 26`, `gap 20`.

Encabezado (`gap 3`): **17px w700** → `Qué va a incluir`; **12px
`textSecondary`** → `N pacientes seleccionados.`

**Periodo** — hoy no existe y es el arreglo de mayor efecto:
etiqueta **11px w700 `textSecondary`** → `Periodo`; tres pastillas de igual ancho
(`flex: 1`, centradas): `3 meses`, `6 meses`, `Todo`; debajo **11px
`textDisabled`** con el rango resuelto →
`Del 12 de marzo al 12 de septiembre de 2026.`

Separador `1px border`.

**Secciones** — etiqueta `Secciones`; una fila por sección (`gap 11`), con la
casilla de 17px y, al lado (`gap 1`), el nombre **13px w600** y **11px
`textDisabled`** con **cuántas hay en el periodo elegido**:

- `Consultas` → `8 en el periodo`
- `Notas de seguimiento` → `23 en el periodo`
- `Antecedentes` → sin subtexto
- `Evolución del área (gráfica)` → `Necesita al menos 2 mediciones`;
  deshabilitada y en `textSecondary` cuando no se cumple.

Separador.

**Fotografías** — etiqueta; dos pastillas de igual ancho: `Basal y última` /
`Todas · 20`. La etiqueta actual dice "Primera y última" pero el código toma
basal + más reciente: **el copy correcto es `Basal y última`.**

**Indicaciones para el paciente** — etiqueta; caja borde `1px border`,
`radius 8`, `padding 12px 13px`, `min-height 58`, placeholder **12px
`textDisabled`** → `Cuidados en casa, señales de alarma, cuándo volver…`

**Aviso de cuántos documentos salen** — caja `radius 8`, fondo `background`,
`padding 13px 14px`, `gap 11`, ícono 17px `textSecondary`, texto **12px** →
`Van a salir 2 documentos, uno por paciente.` con la cifra en **w700**.

Botón primario ancho completo **15px w700**, `padding 15px 24px` →
`Generar PDF`. Mientras corre: `Generando…` con spinner, deshabilitado.

Pie centrado **11px `textDisabled`** `line-height 1.5` →
`Se registra en el Registro de divulgaciones: qué salió, cuándo y quién lo descargó.`

---

## Centro hospital

**Mismo layout, misma paridad de controles.** Cambian los datos, no la
estructura: la tabla lista pacientes con internamiento activo y suma columna
`Braden`; las secciones son `Internamiento`, `Riesgo (Braden)`,
`Comorbilidades y diagnósticos`, `Cumplimiento de prevención`,
`Bitácora de prevención`; las indicaciones se titulan
`Indicaciones para el cuidador`. **No se sustituyen los controles por un
párrafo**, que es lo que hace hoy.

## Estados

- **Vacío**: `KuraEmptyState`. Clínica: `Todavía no hay pacientes en el centro`.
  Hospital: `No hay pacientes internados en el centro`.
- **Sin coincidencias**: `Ningún paciente coincide con "<texto>"`, con botón
  `Limpiar búsqueda`.
- **Error al generar**: `KuraErrorState` → `No pudimos generar el PDF`.
  **El camino hospitalario hoy no tiene `try/catch`**: un fallo ahí no muestra
  nada. Ponle el mismo manejo que el clínico.

## Además

- La pantalla usa `KuraColors` y `withOpacity`: **no cambia de color con el tipo
  de centro**. Migrar a `BrandTokens` — un hospital debe verla azul.
