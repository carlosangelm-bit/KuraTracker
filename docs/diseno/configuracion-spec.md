# Administración › Configuración

Guardar como `docs/diseno/configuracion-spec.md`.
Da por leído `sistema-componentes-spec.md`.

**Pantalla:** pestaña "Configuración" (índice 3) de `admin_home_screen.dart`
(`NoteCatalogTab`). El rail de secciones no cambia.

## El problema que resuelve

Un solo `Wrap` plano con **once botones** mezcla acciones sobre esta pantalla
(catálogo base, CSV) con navegación a ocho pantallas distintas, en dos estilos de
botón cuya diferencia no significa nada. En móvil son cinco o seis filas de
botones antes de que aparezca el contenido. Y el reparto gateado/libre se ve
arbitrario: "Descargar plantilla CSV" es libre pero "Cargar CSV" no.

Se reemplaza por **tres grupos que responden a tres preguntas distintas.**

---

## Encabezado

`padding 32px 40px 48px`, `gap 26` entre bloques.
Título **28px w800** `letter-spacing -.02em` → `Configuración del centro`.
Debajo **14px `textSecondary`** →
`Lo que tu equipo ve al capturar, los protocolos que sigue y la constancia de lo que sale del expediente.`

---

## Grupo 1 — Catálogo de la nota de seguimiento

Tarjeta `radius 16`, `padding 26px 28px`, `gap 20`.

**Encabezado** (`justify: space-between`, base inferior, `gap 24`):

- Izquierda (`gap 4`): **19px w700** `letter-spacing -.01em` →
  `Catálogo de la nota de seguimiento`; **13px `textSecondary`** →
  `Los conceptos que tu personal clínico ve como opciones al registrar una nota. Se configura una vez para todo el centro.`
- Derecha (`gap 10`): botón primario `Nuevo concepto`; botón `Herramientas`
  (fondo `chipBg`, texto `brandPrimary`, chevron) que abre el menú con
  `Cargar catálogo base`, `Descargar plantilla CSV` y `Cargar CSV`
  (este último con el candado de la densidad (b) si no hay módulo).

**Selector de sección** — fila `gap 10`, `flex-wrap`: cuatro pastillas de filtro
del `KuraActionBar`, **cada una con su conteo**:
`Tipo de atención · 12`, `Descripción del procedimiento · 24`,
`Material utilizado · 31`, `Evolución · 9`.
A la derecha, empujado, el buscador (`min-width 230`, `padding 8px 15px`,
placeholder `Buscar concepto`).

**Tabla** (`KuraDataTable`) — hoy es una fila con texto + dropdown + basura + switch
amontonados sin alineación:

| Columna | Ancho | Contenido |
|---|---|---|
| Concepto | 44% | texto **13px w600**; si está inactivo, `textDisabled` con tachado |
| Paso del Protocolo Kura+ | 27% | pastilla `chipBg` **12px w600** con la etiqueta Kura, o `Sin asignar` en **12px `textDisabled`** |
| Estado | 15% | `Activo` **12px w700 `statusSuccess`** / `Inactivo` **12px w700 `textDisabled`** |
| Acciones | 14%, derecha | `Editar · Desactivar` **12px `textDisabled`**, cada palabra clicable |

Nota al pie, **11px `textDisabled`** `line-height 1.5`:
`Desactivar oculta el concepto de las notas nuevas y no toca las notas ya guardadas. El paso del protocolo es lo que conecta cada concepto con las sugerencias de Kura+.`
La palabra **no toca** en `textSecondary` w700.

La columna de etiqueta solo aparece en los campos que tienen `availableTags`;
en los otros la columna se omite entera, no se deja vacía.

---

## Grupo 2 — Tu propio protocolo (el módulo pagado)

Tarjeta `radius 16`, `padding 26px 28px`, `gap 20`.

Encabezado (`gap 4`): **19px w700** → `Tu propio protocolo`; **13px
`textSecondary`** →
`Escribe los pasos que sigue tu centro y qué producto usa en cada uno, en vez de usar el protocolo curado por Kura+.`

**Banda de bloqueo** — densidad (a) del `KuraModuleLock`, con este copy:
título `Estas seis funciones son del módulo Administración avanzada · $1,200 al mes`
(precio de `billing_catalog`), subtítulo
`Incluye además 3 usuarios administrativos, varias sedes y tu marca en los reportes. IVA incluido.`
Botón `Ver Licencias`. **Solo se pinta si el módulo no está contratado.**

**Reja de 3 columnas**, `gap 12`. Cada tarjeta: `padding 15px 16px`, `radius 12`,
`gap 13`; cuadro de ícono **34×34** `radius 9`; nombre **13px w700** y
descripción **11px `textSecondary`** `line-height 1.45`.

Contratado: borde `1px border`, fondo `surface`, cuadro `chipBg` con SVG
`brandPrimary`, nombre `textPrimary`, cursor de mano; al pasar el cursor el borde
va a `#C9BEF0`.
No contratado: borde `1px dashed border`, fondo `#FAF9FD`, cuadro `#F1EFF7` con
SVG `textDisabled`, nombre `textSecondary`. No navega: abre la densidad (c).

Las seis, en este orden y con este copy:

| Función | Descripción |
|---|---|
| Protocolo Kura+ | `Qué conceptos van en cada paso` |
| Productos del protocolo | `Qué insumo y cuánto, por paso` |
| Cargar catálogo por CSV | `Sube tus conceptos en bloque` |
| Tipo de cita para sesiones | `Integración con Acuity` |
| Tipos de consulta | `Valoración o seguimiento, en Acuity` |
| Depurar expedientes | `Archivar en bloque contra tu padrón` |

---

## Grupo 3 — Expediente y cumplimiento (nunca se gatea)

Tarjeta `radius 16`, `padding 26px 28px`, `gap 20`.

Encabezado (`justify: space-between`, base inferior): izquierda **19px w700** →
`Expediente y cumplimiento`, y **13px `textSecondary`** →
`Lo que la ley te exige poder hacer con tu expediente. Nunca depende de un módulo ni de que el pago esté al día.`
Derecha: pastilla **12px w700 `statusSuccess`**, fondo `#E8F4EE`, `radius 30`,
`padding 6px 14px` → `Siempre incluido`.

Reja de 3 columnas, mismas tarjetas del grupo 2, **todas en estado contratado**:

| Función | Descripción |
|---|---|
| Registro de divulgaciones | `Constancia de cada salida de datos` |
| Escalas del protocolo | `Cuáles participan en tu centro` |
| Fuente de recomendaciones | `De dónde sale cada sugerencia` |
| Descargar plantilla CSV | `Tu catálogo actual, en hoja` |
| Cargar catálogo base | `Los conceptos curados por Kura+` |
| Exportar el expediente | `Completo, cuando lo necesites` |

**Requisito, no preferencia:** ninguna de estas seis lleva candado nunca.
La custodia del expediente es del establecimiento (NOM-004) y el acceso es
derecho del paciente (LFPDPPP): no pueden depender de un módulo ni de que el
pago esté al día.

---

## Otros arreglos de esta pantalla

- Las ocho pantallas hijas se abren hoy con `Navigator.push` + `MaterialPageRoute`,
  fuera de go_router: quedan fuera de la URL, del shell y del historial del
  navegador. **Pásalas a rutas hijas de `/admin`** para que el botón "atrás" y
  los enlaces compartibles funcionen.
- `ScaleTogglesScreen` es la única con botón `Guardar` explícito y **pierde los
  cambios si sales sin avisar**. O guarda al instante como sus hermanas, o avisa
  al salir.
- Errores: `KuraErrorState`, no `'Error: $e'` ni `'No se pudo … : $e'`.
- El `hintText` del padrón en `PatientCleanupScreen` trae tres nombres completos
  de personas con aspecto de datos reales. Cámbialos por texto genérico.
