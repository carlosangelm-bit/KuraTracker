# Navegación de KuraTracker — especificación

**Canvas aprobado:** "Navegación KuraTracker", página *Propuesta*, 14-sep-2026.
**Decisión:** dirección B (riel único que se anida) con el buscador de C encima.
En pantallas angostas el riel **colapsa a iconos**. El buscador llega a **pantallas,
centros y pacientes**.

---

## 1. El problema que resuelve

Hoy conviven tres niveles de navegación en la misma pantalla: el riel de la app
(8 destinos), un segundo riel de sección (6 en Administración, **9** en Plataforma) y
subsecciones dentro del contenido. Se van 216 px de ancho antes de que empiece el
contenido y la sección activa se dice en dos lugares a la vez.

Además, la navegación de `/platform` se indexa por número (`_tab`), con un `switch`
cuyos casos y las entradas del riel se mantienen sincronizados **a mano**. Ya produjo
una falla: el panel de Licencia se escribió en el caso `8` y la entrada del riel se
agregó por separado; si una de las dos se hubiera olvidado, la pantalla quedaba
inalcanzable sin que ninguna prueba se quejara.

## 2. Qué se construye

Un solo componente de navegación, `KuraNavRail`, con **dos estados** y **un nivel** de
anidación. Nada más. Se eliminan: el segundo riel, el `TabBar` de `/platform`, y el
`switch` por índice.

### 2.1 Estado abierto (ancho ≥ 1200 px)

- Riel de **240 px**, fondo `surface`, borde derecho 1 px `border`.
- Encabezado: marca 30×30 radio 9, nombre 15/w800, botón de colapsar a la derecha.
- Buscador: fondo `background`, borde 1 px `border`, radio 10, `padding 8px 11px`,
  texto 12 `textDisabled` "Buscar o ir a…", y la tecla `⌘K` en `chipBg` radio 5.
- Destinos: `padding 9px 11px`, radio 10, icono 18 px trazo 2, etiqueta 13.
  Activo: fondo `chipBg`, etiqueta w800 en `brandPrimary`.
- Un destino **con hijos** muestra un chevron y, al estar activo, expande sus hijos
  **en el lugar**: lista con `padding-left 18px`, `margin-left 20px` y un borde
  izquierdo de 2 px `chipBg`; cada hijo `padding 7px 12px`, radio 8, texto 13.
  El hijo activo: fondo `background`, w800, `textPrimary`.
- Pie: separador 1 px, avatar 28 radio pill, nombre 12/w700, centro 11 `textSecondary`.

**Un solo nivel.** Si alguna sección llegara a necesitar nietos, se resuelve en el
contenido, no en el riel.

### 2.2 Estado colapsado (ancho < 1200 px)

- Riel de **72 px**, solo iconos de 19 px en cajas de 38×38 radio 11.
- El destino activo lleva fondo `chipBg` y una barra de 3×20 px radio 3 en
  `brandPrimary` pegada al borde izquierdo.
- Los hijos NO se muestran en el riel. La sección activa se dice en el **encabezado**
  del contenido, como menú: `Administración › Configuración ▾`, fondo `background`,
  borde 1 px `border`, radio 10, `padding 7px 13px`, que despliega la lista de hermanas.
- El buscador se reduce a su icono en una caja de 34×34.

**Teléfono (< 600 px): fuera de alcance a propósito.** Un riel de 72 px se come el 18 %
de una pantalla de 390. Se decide aparte, con pantallas propias. No inventar aquí.

### 2.3 Buscador (⌘K)

- Modal de 660 px, radio 20, sombra `0 24px 64px rgba(32,26,46,0.38)`, sobre velo.
- Resultados agrupados: **Ir a** (pantallas y centros) y **Pacientes** (nombre o folio).
- Cada resultado: icono o avatar, título 14/w700, contexto 11 `textSecondary`.
  El seleccionado lleva fondo `chipBg`. Teclado: ↑↓ mueve, ↵ abre, `esc` cierra.
- Pie con las ayudas de teclado y la línea **"Solo ve lo que su cuenta puede ver."**

**Regla de seguridad, no de producto:** el buscador NO es un atajo a la autorización.
Los resultados se filtran por lo que la sesión ya puede leer — mismas reglas que las
pantallas, mismo `canReadModule` y misma pertenencia de centro. Un paciente de otro
centro no aparece, ni siquiera como nombre. Esto se prueba, no se confía (§4).

## 3. Rutas, no índices

Cada destino y cada hijo tiene **su ruta**. El riel se pinta desde una sola declaración
(destino, etiqueta, icono, ruta, hijos, condición de visibilidad) y navega con
`context.go`. Se elimina `_tab` y su `switch`. La pantalla activa se deriva de la URL,
nunca de un entero.

Esto cierra por construcción el hueco de §1: no se puede agregar una pantalla al
`switch` y olvidar el riel, porque no hay dos listas.

## 4. Pruebas — de invocación, como siempre

1. **Cobertura de rutas:** para cada entrada de la declaración del riel, navegar a su
   ruta monta su pantalla y la entrada queda marcada como activa. Agregar una entrada
   sin ruta válida rompe la prueba.
2. **Nada se pierde al colapsar:** en el estado colapsado, todo destino de la
   declaración sigue siendo alcanzable (icono + menú del encabezado). Quitar el menú
   del encabezado pone la prueba en rojo.
3. **El buscador no filtra de más ni de menos:** con una sesión que NO pertenece a un
   centro, buscar el nombre exacto de un paciente de ese centro devuelve **cero**
   resultados; con la sesión que sí pertenece, lo devuelve. Es la prueba que más
   importa de todo el spec.
4. **Un solo nivel:** una declaración con nietos falla en tiempo de prueba, con mensaje.

Cada una con el criterio de siempre: romper la regla tiene que poner la prueba en rojo,
verificado a mano antes de darla por verde.

## 5. Etapas

1. **`KuraNavRail` + declaración de rutas + los dos estados.** Sin cambiar ninguna
   pantalla. Pruebas 1, 2 y 4.
2. **`/platform`**: se sustituye el riel doble y el `switch` por índice. Es donde más
   duele (9 secciones) y donde los usuarios son tres. **Va antes de la etapa 4 de la
   consola de derechos** — si no, esa pantalla se construye sobre el chrome que vamos
   a tirar y hay que rehacerla.
3. **`/admin`**: mismo cambio, 6 secciones.
4. **Buscador ⌘K**, primero solo navegación y centros; pacientes al final, con la
   prueba 3 verde antes de exponerlos.
5. **La app clínica**, solo con lo anterior rodado. Enfermería ya aprendió dónde está
   todo: el cambio se anuncia, no se suelta.

   **Condición de salida de esta etapa** (no un pendiente suelto): mientras AppShell
   siga pintando su riel en las rutas clínicas, la declaración DUPLICA su lógica
   condicional (tipo de centro, gateo por módulo, roles). Esa duplicación se prueba con
   `admin_nav_test` → "cierre de la clase", que hoy compara a mano cada destino
   condicional contra `app_shell.dart` (por eso la lista `moduleGated` está escrita a
   mano, con la línea de origen al lado: un noveno destino con condición propia NO la
   hace crecer sola — misma limitación que `_gatedScreens`). Forzar hoy un escaneo de
   fuente sería construir algo para tirarlo. Al cerrar esta etapa —cuando AppShell deje
   de pintar riel en las rutas clínicas— la duplicación desaparece: `_itemsFor` de
   AppShell se retira, la declaración pasa a ser la ÚNICA fuente, y ese test o muere (ya
   no hay contra qué comparar) o se convierte en la fuente autoritativa. Revisar los dos
   al retirar `_itemsFor`.

## 6. Lo que NO cambia

Los componentes de contenido (`KuraDataTable`, `KuraStat`, `KuraActionBar`,
`KuraModuleLock`, estados vacíos y de error) no se tocan. Esto es chrome, no contenido.

---

# Etapa 5 — la app clínica (decidida 14-sep-2026)

Decisión de Carlos: **el riel nuevo va a todas las rutas clínicas, para todos, en un
solo despliegue. Sin bandera de encendido.** El único centro productivo es Kura+, así
que un despliegue por etapas no reduce riesgo y sí obliga a mantener dos navegaciones
en paralelo durante meses.

## 7. Tres bandas de ancho, no dos

Es lo que más fácil se hace mal, porque hoy hay dos puntos de corte distintos en el
código: el riel usa 1200 y AppShell usa 900.

| Ancho | Qué se ve |
|---|---|
| ≥ 1200 | `KuraNavRail` abierto (240 px), hijos anidados |
| 900 – 1199 | `KuraNavRail` colapsado (72 px) + menú `Sección › Subsección ▾` en el encabezado |
| < 900 | **La barra inferior flotante de hoy, sin cambios.** Ningún riel. |

La barra inferior **no se rediseña en esta etapa**. Funciona, enfermería la conoce, y
es el flujo del teléfono junto a la cama. Se toca solo lo indispensable para que coma
de la misma declaración (§8).

## 8. Una sola declaración para las dos formas

Hoy `app_shell.dart:60-104` construye **su propia lista** de destinos, con su propio
gateo por módulo y su propia rama por tipo de centro — duplicada de
`kuraNavDestinations`. Esa duplicación ya nos costó una regresión (el hospital viendo
`/agenda`, que sale "no configurada").

En esta etapa la lista de AppShell **desaparece**: la barra inferior se construye desde
`kuraNavDestinations`, igual que el riel. Para eso la declaración gana un campo por
destino que diga si es **primario** — los que hoy viven en `primaryPaths`
(`/`, `/patients`, `/agenda`, `/prevention-agenda`); el resto va al desbordamiento de
la barra, como hoy.

**Condición de salida que quedó escrita en §5 y ahora se cumple:** al desaparecer la
lista de AppShell, la prueba de "cierre de la clase" con su lista `moduleGated` escrita
a mano deja de tener sentido. Se elimina y se sustituye por la prueba de §9.1, que
compara las dos formas contra la misma fuente en vez de contra un inventario manual.

## 9. Pruebas

1. **Las dos formas dicen lo mismo.** Para las mismas banderas (rol, módulos, tipo de
   centro), el conjunto de destinos del riel y el de la barra inferior —primarios más
   desbordamiento— es **idéntico**. Esta es la prueba que reemplaza al inventario
   manual: agregar un destino a la declaración lo pone en las dos, o cae.
2. **La rama por tipo de centro sobrevive en la barra:** hospital → `Rondas`
   (`/prevention-agenda`); clínica de heridas → `Agenda` (`/agenda`). Es la regresión
   que ya tuvimos; ahora hay que probarla también del lado del teléfono.
3. **Las tres bandas:** a 1400 el riel está abierto; a 1000, colapsado con su menú; a
   800, no hay riel y sí barra inferior. Sobre el router real.
4. AppShell ya no pinta riel de escritorio en **ninguna** ruta.

Cada una con el criterio de siempre: romperla tiene que ponerla en rojo, verificado a
mano antes de darla por verde.

## 10. El despliegue (hecho)

Se desplegó sin bandera, en un solo corte, con el plan de reversión previsto:

- Respaldo antes del corte, con la hora anotada.
- El build anterior quedó identificado para poder redesplegarlo — minutos, no un
  revert de commits bajo presión.
- **Fuera de horario de atención**, no a media mañana.
- Se avisó al equipo clínico antes, no después: el cambio es visible el primer segundo.
