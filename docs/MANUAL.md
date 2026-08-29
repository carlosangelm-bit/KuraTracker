# Manual de usuario — KuraTracker

> **Qué es KuraTracker.** Expediente clínico electrónico (EHR) para el cuidado de
> heridas crónicas y la prevención de lesiones por presión (LPP). Cubre el flujo
> completo del profesional: alta de pacientes, agenda, consulta (valoración y
> seguimiento), motor de apoyo a la decisión **Kura+**, reportes, cobros, y los
> módulos de prevención (hospital) y de cuidadores a domicilio.
>
> **Aviso clínico.** El motor Kura+ y sus pronósticos/checkpoints son **apoyo a la
> decisión clínica: no sustituyen el juicio del profesional de salud.**
>
> **Cómo usar este manual.** Está organizado por conceptos base, luego por flujo y
> por módulo, y termina con un glosario y una matriz de permisos por rol. Los
> nombres entre comillas ("Nuevo paciente") son botones/etiquetas tal como
> aparecen en la aplicación. Un asterisco (\*) marca campos obligatorios.

---

## Índice

1. Conceptos base (roles, tipos de centro, navegación, módulos)
2. Acceso a la plataforma (login y demo)
3. Pacientes (lista, filtros, alta/edición, comorbilidades, diagnósticos, detalle)
4. Agenda de citas
5. Consulta (nueva consulta, detalle, cobro)
6. Valoración: captura de herida (pronóstico Kura+ en vivo) y **Plan del mes**
7. Seguimiento en 5 fases
8. Reportes
9. Prevención y riesgo (Braden, tablero, perfil, rondas, dashboard hospital)
10. Cuidadores (app del cuidador)
11. Eventos adversos
12. Consentimientos
13. Referencias / interconsultas
14. Insumos e inventario
15. Comercial (servicios, cobros, Stripe, terminal Point)
16. Terapia VAC y Laboratorios
17. Importar / exportar (eKare)
18. Administración (admin de centro) — incl. Protocolo Kura+ y Productos del protocolo
19. Plataforma (master)
20. Dashboard principal (Inicio)
21. Glosario clínico
22. Matriz de permisos por rol

---

## 1. Conceptos base

### 1.1 Roles

| Rol | Etiqueta en la app | A dónde entra | Qué puede hacer |
|---|---|---|---|
| **clinico** | Personal sanitario | Inicio (`/`) | Operación clínica completa: pacientes, consultas, valoración, seguimiento, diagnósticos, reportes. Sí puede diagnosticar. |
| **admin** | Administrador | Inicio (`/`) | Todo lo clínico **+** la pestaña **Administración** de su centro (usuarios, personal, sitios, catálogo de notas, marca). Sí puede diagnosticar. |
| **enfermeria** | Enfermería | Inicio (`/`) | Observa, reporta y **ejecuta** cuidados. **No diagnostica ni cambia el protocolo.** Puede leer el expediente, valorar Braden, reportar eventos adversos y ejecutar la agenda de prevención. |
| **cuidador** | Cuidador | Monitoreo (`/caregiver`) | Acceso restringido: solo sus pacientes asignados (lectura clínica) y sus propias tareas de cuidado. |
| **master** | Administrador de plataforma | Plataforma (`/platform`) | Administra la **estructura** de todos los centros (organizaciones, usuarios, sitios, catálogos, módulos). **No accede a datos clínicos de pacientes.** Acceso interno. |

Solo **clínico** y **admin** pueden diagnosticar y capturar clínicamente. **Enfermería**
tiene bloqueadas las pantallas de escritura clínica (crear/editar paciente, nueva
consulta, captura de herida, nuevo/borrador de seguimiento, comorbilidades,
diagnósticos, nueva referencia); si intenta abrirlas, la app la regresa al expediente.

### 1.2 Tipos de centro

Cada centro (organización) es de un tipo, que cambia el color de marca y los módulos
por defecto:

| Tipo | Color | Enfoque |
|---|---|---|
| **Clínica de heridas** | Morado | Tratamiento de heridas. Módulos de insumos y comercial activos por defecto; prevención apagada. |
| **Hospital** | Azul | Prevención de LPP centrada en el paciente (Braden, rondas, dashboard). Todos los módulos activos salvo eKare. |
| **Cuidadores** | Rosa | Cuidado a domicilio. Solo pacientes, agenda y prevención por defecto. |

### 1.3 Multi-centro (cambiar de centro)

Un usuario puede pertenecer a varios centros. Si tiene **2 o más membresías**, aparece
un **selector de centro**:
- Toca el **ícono/título de marca** (muestra una flecha ⌄ cuando es cambiable) o el
  **menú del avatar** → **"Cambiar de centro"**.
- Se abre una lista con cada centro (nombre, chip del tipo con su color, y
  `tipo · rol`); el activo lleva palomita. Al elegir otro, la app **repinta toda la
  paleta** (morado/azul/rosa) y muestra los datos de ese centro.

### 1.4 Navegación

- **Escritorio (ancho ≥ 900 px):** barra lateral (rail) con todos los destinos.
- **Móvil:** barra flotante inferior con los destinos principales; el resto se agrupa
  en un menú **"Más"**. Los destinos principales fijos son **Inicio, Pacientes,
  Agenda/Rondas**. La barra inferior se oculta en pantallas de detalle/formulario/
  captura para no tapar sus botones.
- **La pestaña de agenda depende del tipo de centro:** hospital muestra **"Rondas"**
  (agenda de prevención); clínica y cuidadores muestran **"Agenda"** (citas).

### 1.5 Módulos configurables

Los destinos visibles dependen de qué **módulos** estén encendidos para el centro/
sitio/usuario (lo configura el admin/master): Pacientes, Agenda, Prevención, VAC,
Reportes, Insumos, Comercial, eKare. **Inicio** siempre está; **Administración**
depende del rol admin; **Plataforma** del rol master.

---

## 2. Acceso a la plataforma

### 2.1 Login (producción)

Pantalla de inicio de sesión con dos modos:
- **Personal (correo):** correo + contraseña.
- **Cuidador (teléfono):** teléfono + clave (el correo es sintético, derivado del
  teléfono).

Tras entrar, cada rol ateramiza a su área: master → Plataforma, cuidador → Monitoreo,
el resto → Inicio.

### 2.2 Demo

En el sitio de demostración (sin credenciales reales) aparece primero una **capa de
selección de perfil**: el visitante elige un perfil (Kuradora/Médico, Administrador de
centro, Enfermería, Cuidador) a partir de una descripción y entra con un usuario de
ejemplo con datos sembrados. El perfil **Master no se expone en la demo** (es de acceso
interno).

---

## 3. Pacientes

### 3.1 Lista de pacientes ("Pacientes")

- Alterna entre **vista Lista** y **vista Tarjeta** (la elección se recuerda).
- Botón flotante **"Nuevo paciente"** (abajo a la derecha) para dar de alta.
- Cada paciente muestra nombre, **folio** (EXP2026-…), chips de etiología de sus
  heridas activas y un **semáforo de avance** (trayectoria de Sheehan). Acciones
  rápidas: tocar abre el expediente; **"Valoración"** inicia una nueva consulta de
  valoración; **"Seguimiento"** va al seguimiento de la herida activa (si hay varias,
  pide elegir).
- **Qué ve cada rol:** el clínico ve sus pacientes asignados; en **hospital**, cualquier
  personal del centro ve a **todos** los pacientes del centro; admin ve todos. En
  hospital, si el paciente no tiene heridas activas, la fila muestra señales de
  prevención (Braden, internamiento, comorbilidades, diagnóstico principal).

### 3.2 Filtros

Debajo del título:
- Búsqueda **"Buscar por nombre o folio"**.
- Chip **"Estado"**: Todos / Con heridas activas / Sin heridas activas.
- Chip **"Sitio"** (si hay sitios).
- Chips por **etiología** (multi-selección): Pie diabético, Vascular, LPP, Quirúrgica,
  Traumática, Otra.
- Chips por **estatus de avance** (semáforo).
- **"Limpiar filtros"** cuando hay filtros activos.

### 3.3 Alta / edición de paciente

Título **"Nuevo paciente"** (alta) o **"Completar / editar expediente"** (edición;
típico para pacientes creados desde Acuity que solo traen el nombre). Secciones:

- **Datos generales:** Nombre completo \*, Fecha de nacimiento, Sexo (Femenino /
  Masculino / Otro), CURP (recomendada, 18 caracteres), Domicilio, Ocupación, Peso
  (kg), Talla (cm), Sitio principal, Movilidad (Ambulatorio / Silla de ruedas /
  Encamado / Otro).
- **Cuidador y fragilidad:** interruptor **"Cuidador identificado"** (revela nombre y
  teléfono del cuidador); interruptor **"Paciente frágil"** (activa interconsulta a
  geriatría en el motor Kura+).
- **Responsable / tutor:** nombre, parentesco, teléfono (para menores o urgencias).
- **Antecedentes**, **Medicamentos activos**, **Alergias**.
- **Comorbilidades (APP):** selector con tres estados por comorbilidad — **Presente**,
  **Negado**, **No evaluado**. Solo "Presente" influye en el motor Kura+.
- **Antecedentes heredo-familiares:** chips + detalle.
- **Antecedentes personales no patológicos (APNP):** Tabaquismo, Alcohol, Actividad
  física, y un campo "Otros".

Botón final **"Crear expediente"** / **"Guardar cambios"** (requiere el nombre).

### 3.4 Diagnósticos CIE-10

En **"Diagnósticos (CIE-10)"** del expediente. Es registro **documental** que no
modifica el motor. Botón **"Agregar diagnóstico"**:
1. **Buscador CIE-10:** busca por código o nombre (ej. "E11, úlcera") con filtros por
   relación (Causa / Comorbilidad / Consecuencia / Herida).
2. **Confirmación:** Relación con la herida, interruptor **"Diagnóstico principal"**
   (reemplaza al anterior), Notas.

Cada diagnóstico se lista con código, nombre, relación, notas y chips
**Principal / estado** (Activo / Resuelto / Descartado). Un diagnóstico que deja de
aplicar se **marca resuelto/descartado, no se borra**.

### 3.5 Detalle del paciente

Encabezado con nombre; si el rol puede diagnosticar, botones **"Editar / completar
expediente"** y **"Nueva consulta"** (enfermería ve todo en solo lectura).

Tarjeta de datos (folio, chip "Frágil", edad, sexo, movilidad, cuidador, CURP, peso/
talla con IMC, responsable, antecedentes, alergias en rojo, medicamentos, APNP) y
tarjetas de sección:
- **Comorbilidades (APP)**, **Diagnósticos (CIE-10)**, **Laboratorios**, **Prevención y
  riesgo**, **Terapia VAC** (si el módulo está activo), **Cuidadores que monitorean**
  (solo admin), **Consentimientos** (chips verde/rojo por tipo), **Cobros** (centros
  premium).
- **Heridas:** botón **"Registrar herida"**; cada herida con etiología, subtipo, badge
  de escenario, mini-estadísticas (Área, Profundidad, Necrosis+Esfacelo) y acciones
  **"Seguimiento"**, **"Nueva valoración"**, **"Plan de alta"** (egresa la herida con
  motivo de egreso). Si hay una sola herida activa, el seguimiento se muestra embebido
  aquí.
- **Historial de consultas** (con chip "Borrador" si aplica), **Eventos adversos**,
  **Referencias / interconsultas**.

En **hospital**, la tarjeta de Prevención/Riesgo va primero y el resto se agrupa bajo
**"Avanzado"**.

---

## 4. Agenda de citas

Título **"Mi agenda"** (clínico) o **"Agenda del centro"** (admin). Modos según el
centro: **Acuity** (integrada), **Manual** (local) o **Sin configurar**.

- **Encabezado:** "Hoy · fecha" con conteo del día, la **Próxima** cita y "Esta semana:
  N".
- **Controles:** chips **Día / Semana**; en Día, chip **"Historial"** para incluir
  citas pasadas; menú **"Kurador"** para filtrar (admin, si hay varios).
- **Acciones desde una cita:** **"Paciente"** (va al expediente) e **"Iniciar
  consulta"** / **"Ver consulta"** (botón inteligente: abre la consulta ligada si
  existe, o crea una nueva pre-ligada a la cita). El menú (⋮) ofrece **"Ver detalle"**,
  **"Reagendar"**, **"Cancelar cita"**.
- **Detalle de la cita:** todos los campos de Acuity (paciente, teléfono, email, fecha/
  hora, duración, tipo, calendario/Kurador, ubicación, estado, precio, pagado, notas),
  la foto de la herida del formulario de admisión si viene, y un bloque **"Todos los
  campos (crudo)"** con **"Copiar"**.
- **Nueva cita / Reagendar:** hoja con Servicio → fecha → hora (y, para altas, nombre/
  apellido/email).

---

## 5. Consulta

### 5.1 Nueva consulta (hub)

Título **"Nueva consulta"**. Muestra el paciente y **"Datos de la consulta"**: fecha
(hoy por defecto), **Sitio \***, **Tipo de visita \*** (**Valoración** o
**Seguimiento**). Botón inferior:
- **Valoración** → **"Continuar: capturar herida"** (crea la consulta como borrador y
  entra a la captura).
- **Seguimiento** → **"Continuar: registrar seguimiento"**. Exige una herida activa: si
  no hay, avisa ("registra una valoración primero"); si hay varias, pide elegir.

Se puede **guardar como borrador** en cualquier momento.

### 5.2 Detalle de consulta

Título **"Detalle de consulta"** (referencia histórica). Chip del tipo de visita, chip
"Borrador" si aplica, fecha, paciente, sitio, personal.

- **Si es borrador:** **"Continuar consulta (borrador)"** y **"Eliminar borrador"** (con
  confirmación; borra también la captura asociada).
- Por cada herida evaluada: **Mediciones**, **Composición del lecho**, **Evaluación
  clínica** (exudado, olor, borde, dolor EVA, adherencia, criterios de infección IWII,
  piel perilesional), **Recomendación Kura+** (escenario, fenotipo, régimen,
  interconsultas), **Tratamiento aplicado** y **Fotos**.
- **Insumos utilizados** (centros premium): **"Sugerir del plan"** resuelve los productos
  del Protocolo Kura+ según la **medida de la herida**, el exudado, la zona y la infección,
  y los agrega como insumos (si un genérico tiene varias presentaciones, te deja elegir);
  si no hay reglas, usa el mapeo antiguo. **"Agregar insumo"** agrega uno manual. Por
  insumo: cantidad ± y chips **"Cobrar"** / **"Descontar"** (independientes).
- **Cobro / pago:** **"Cobrar consulta"** (funciona en borrador) → elige el
  **Servicio (honorario)** o captura "Otro"; suma honorario + insumos a cobrar y
  muestra el **Total** → **"Registrar cobro"**. Después, **"Registrar pago"** con
  **Efectivo / Transferencia / Tarjeta (manual)**; al pagar, descuenta el inventario
  marcado.
  > Los pagos con **terminal Point (Mercado Pago)** y los **links de pago Stripe** se
  > gestionan en el módulo **Comercial** / la tarjeta **"Cobros"** del expediente, no
  > aquí.
- **Notas y resumen:** notas del especialista, resumen de la consulta y (admin/master)
  la transcripción completa.
- **Enmiendas / aclaraciones (NOM-004):** **"Agregar aclaración"** → texto de
  corrección + motivo + **"Firmar y agregar"**. Las notas firmadas no se editan ni se
  borran; las correcciones quedan como aclaraciones fechadas y firmadas.

---

## 6. Valoración: captura de herida

Título **"Registrar herida"**. Arriba, **"Guardar borrador"**. El **Pronóstico en
vivo** está siempre visible (a un lado en pantallas anchas, arriba en móvil). Abajo,
**"Continuar a tratamiento"**. **Los campos cambian según la etiología.**

- **Evidencia fotográfica:** agregar fotos (la primera es la basal). Requiere
  consentimiento de **privacidad + fotografía**; si falta, avisa con acción
  **"Registrar"**.
- **Etiología y localización:** **Tipo de herida \*** (Pie diabético / Vascular / LPP /
  Quirúrgica / Traumática / Otra), Subtipo, **Ubicación corporal \***, **Fecha de
  inicio \***.
- **Sección específica por etiología:**
  - *Pie diabético:* **Wagner \***, **WIfI \*** (W/I/fI 0-3), Universidad de Texas,
    IDSA/IWGDF, monofilamento 10 g.
  - *Vascular:* subtipo (venosa/arterial/mixta), interruptor "No revascularizable",
    Rutherford, CEAP.
  - *Quirúrgica:* WUWHS, clase de contaminación (CDC), tipo de cierre, drenaje, sutura.
  - *Traumática:* agente causal.
  - *LPP:* estadio NPUAP/EPUAP y **Escala de Braden \*** ("Valorar Braden (escala
    completa)" o slider 6-23).
- **Evaluación clínica:** **Glucosa (mg/dL) \*** (y **HbA1c \*** si es diabético),
  **Edema \***, interruptor **Dolor \*** (tipo, duración, EVA 0-10), Exudado (tipo y
  cantidad), **Infección — criterios IWII \***, **Olor \***, **Borde \***, **Piel
  perilesional \***, Notas.
- **Zona de la herida (dimensiones):** **Longitud \***, **Anchura \***, Profundidad; el
  **Área se autocalcula**. En heridas profundas aparece el **Volumen (cm³)**
  autocalculado por la fórmula de **Kundin** (editable a mano). Casillas
  **Tunelización** y **Socavamiento \***.
- **Composición del lecho \*:** cuatro sliders 0-100% — **Granulación, Esfacelo,
  Necrosis, Epitelización** — con colores realistas del tejido. Casilla **"Confirmo que
  esta composición se capturó antes de curar/desbridar"**. Una barra de total avisa si
  la suma pasa de 100%.
- **Perfusión y nutrición:** interruptor "Herida de extremidad inferior" (se autodetecta
  por la ubicación) con **ABI/ITB** derecho/izquierdo y **Albúmina sérica**.

**Al continuar:** exige al menos largo y ancho y los consentimientos requeridos
(privacidad, fotografía y, si la captura fue posterior al desbridamiento,
desbridamiento). Al guardar, la consulta deja de ser borrador y pasa a tratamiento.

### 6.1 Pronóstico en vivo (Kura+)

Panel **"Pronóstico en vivo — Protocolo Kura+"** ("Apoyo a la decisión clínica — no
sustituye el juicio clínico"). En tiempo real muestra las tres probabilidades
(**Escenarios A/B/C**) como barras, resalta el **escenario dominante** con su
significado y **fenotipo**, y lista **alertas** de seguridad e **interconsultas**
sugeridas (con marca de urgente). Antes de tener largo y ancho, indica que faltan datos.

### 6.2 Plan del mes (tras la valoración)

Título **"Plan de tratamiento del mes"**. Se abre **automáticamente al guardar la
valoración** (se puede **"Omitir"**). Arma el plan del mes: qué insumos, en qué cantidad
y con qué cadencia. Enfermería no puede acceder (rol restringido).

- **Insumos por procedimiento** (agrupados por procedimiento): se **autosugieren** desde
  las reglas de producto del Protocolo Kura+ (resueltas por la medida de la herida,
  exudado, zona e infección; ver §18) o, si no hay regla, desde el mapeo antiguo. Cada
  insumo tiene: nombre, precio unitario, un **± de cantidad** y un **toggle de modo**:
  - **"por sesión"**: la cantidad se multiplica por el nº de sesiones (consumibles de cada
    cura).
  - **"mensual (multidosis)"**: la cantidad **ya es la del mes** (productos que se compran
    1–2 veces al mes según el uso); **no** se multiplica por sesiones.
  Toca el chip para alternar. **"Agregar producto"** abre un buscador del inventario del
  sitio.
- **Cadencia de sesiones:** **Días de la semana** (chips L–D; por defecto Lun/Mié/Vie),
  **Hora**, **Inicio** (fecha) y **Semanas** (1–8, duración del plan).
- **Sesiones del mes:** lista autogenerada (una por día elegido × semanas). En centros con
  **Acuity**, las sesiones que se **empalman** con el calendario del especialista (±60 min)
  se marcan en rojo con un aviso (Acuity se usa solo para detectar conflictos; el plan **no**
  crea citas en Acuity).
- **Explosión de materiales del mes** ("para reservar stock"): total por insumo — los "por
  sesión" = cantidad × sesiones; los "mensual" = su cantidad tal cual (con etiqueta
  "mensual"). Sirve para reservar/pedir stock.
- Botones: **"Guardar borrador"** (guarda el plan como borrador) y **"Aceptar e iniciar"**
  (guarda los insumos con su modo y **registra todas las sesiones** del mes; el plan queda
  aceptado).

**Cómo se conecta con los seguimientos:** al aceptar, cada seguimiento **no** se rellena
solo; en la consulta se usa **"Sugerir del plan"** (ver §5.2 y §14) para volver a resolver
los mismos insumos. La explosión del mes alimenta el reabasto/stock.

---

## 7. Seguimiento en 5 fases

Título **"Registrar seguimiento"**. Arriba, la **Fecha de la visita**. Organizado por
fases:

- **Fase 0 · Perfil heredado:** tarjeta de solo lectura con lo premarcado desde la
  valoración (semana de tratamiento y meta del hito, etiología, ABI/ITB mínimo,
  comorbilidades presentes, clasificaciones). En heridas vasculares permite ajustar
  subtipo vascular y "No revascularizable" para esta visita.
- **Fase 1 · Procedimiento físico:** **Foto después de limpiar (sin medición) \***;
  **Medición** (Largo \*, Ancho \*, Profundidad; Área 2D automática; Volumen Kundin si
  es profunda); casillas Tunelización/Socavamiento (y medición manual si aplica);
  **Foto con medición**.
- **Fase 2 · Estado actual:** Composición del lecho (sliders), Estado clínico (Edema;
  Dolor tipo/duración/EVA; Exudado; **Criterios IWII**; Olor; Borde; Piel
  perilesional), casilla **"Baja adherencia al tratamiento"**, Notas.
- **Fase 3 · Régimen sugerido por Kura+** (premium): **"Calcular régimen"** corre el
  motor con Fase 0 + Fase 2 → alertas, componentes (método — producto + justificación),
  interconsultas. **"Aceptar y aplicar a la nota"** preselecciona (editable) los
  conceptos de la Fase 5.
- **Fase 4 · Trayectoria / checkpoint de Sheehan:** compara el área actual contra la
  basal; muestra **% de reducción** (ajustada y bruta) contra las metas de cierre/
  alerta, una barra coloreada, la **decisión** (En trayectoria de cierre / Extender
  observación / Reclasificar) y las penalizaciones aplicadas (−5 pp por infección
  activa, baja adherencia, deterioro del lecho o aumento de exudado).
- **Fase 5 · Nota + firma (obligatoria):** chips de catálogo del centro (más "Otro"):
  **Tipo de atención \*** (única), **Descripción del procedimiento \*** (múltiple),
  **Material utilizado \*** (múltiple), **Evolución \*** (única). Luego **Notas del
  especialista** y **Resumen** (autollenado editable). Tarjeta de firma (nombre + cédula
  del profesional en sesión) y recuadro para **trazar la firma digital**.

**Guardar:** **"Guardar como borrador"** (solo requiere largo/ancho, no cobra) y
**"Guardar seguimiento"** (se habilita con largo/ancho, la foto después de limpiar, la
nota completa, nombre y cédula, la firma trazada y el consentimiento de fotografía; si
falta algo, un texto en rojo dice exactamente qué).

### 7.1 Vista de seguimiento

Título **"Seguimiento de herida"** con **"Registrar seguimiento"**. Vista comparativa:
- **Tendencia de área (cm²)** — gráfica de línea, un punto por visita.
- **Gráfica de volumen** (heridas profundas medidas en 3D).
- **Composición de tejido en el tiempo** (colores realistas del tejido).
- **Checkpoint de Sheehan · Semana N** — medidor con % de reducción bruta/ajustada,
  umbrales, penalizaciones y decisión coloreada.
- Aviso **"Sin avance en 2–4 semanas: considerar referir a especialista"** cuando el
  área no se redujo.
- Comparación de fotos **Basal** vs **Actual** con sus fechas.

---

## 8. Reportes

Título **"Reportes"**.

- **Selecciona pacientes:** búsqueda **"Buscar por nombre o folio"** (con limpiar).
  Lista de casillas; contador **"N seleccionado(s)"** y **"Quitar selección"**. La
  búsqueda oculta filas pero **no desmarca** lo ya seleccionado. La población depende
  del contexto: el clínico ve sus pacientes, admin todos, y en **hospital** solo los
  internados.
- **Reporte clínico (no hospital):** casillas **Consultas / Seguimientos /
  Antecedentes**; **Evidencias** (Todas / Primera y última); **"Recomendaciones para el
  paciente"**; botón **"Generar reporte (PDF)"**.
  - **Encabezado repetido en todas las hojas** (trazabilidad): nombre, folio y fecha de
    descarga; **pie con paginación** (Página X de Y). Datos del paciente en la portada
    incluyen **fecha de nacimiento**, edad y sexo; antecedentes.
  - Por cada herida: diagnóstico/localización, **clasificaciones** (WUWHS, Wagner, CEAP),
    **fecha de valoración y especialista**; condición actual (tamaño, dimensiones,
    composición, **socavamiento/tunelización**); **valoración clínica** de la última
    evaluación (**signos de infección IWII, dolor, exudado, piel perilesional, nota
    clínica**); **avance** (% de reducción), **gráfico de evolución del área**,
    **checkpoint de Sheehan** (semana, % vs. objetivo, estado, factores que penalizan),
    **tratamiento establecido**, y **evidencia fotográfica** con pie por foto (**fecha,
    hora, área**; basal / más reciente). Al final: lista de consultas, **notas de
    seguimiento** (tipo, procedimiento, material, evolución, firma con cédula), las
    recomendaciones y la leyenda de apoyo a la decisión clínica.
- **Reporte de prevención (hospital):** botón **"Generar reporte de prevención (PDF)"**;
  incluye internamiento, riesgo (Braden), comorbilidades, diagnósticos, cumplimiento de
  rondas, bitácora de prevención e indicaciones al cuidador.

El PDF se abre en el diálogo estándar de impresión/compartir.

---

## 9. Prevención y riesgo

Capa de prevención de LPP (apoyo documental; no modifica el plan de tratamiento). Es el
foco de los centros **hospital** y también aplica en cuidadores.

### 9.1 Escala de Braden

Se abre desde el perfil de riesgo con **"Valorar"** (o desde la captura de herida en
LPP). Hoja **"Valoración de Braden"**: seis subescalas, cada una con opciones
"puntaje · descripción"; se elige una por ítem y el **total se calcula solo** (muestra
"Total: N · banda de riesgo" o "Faltan N ítem(s)"). Campo **Notas** opcional.
**"Guardar"** se habilita al responder las seis subescalas.

**Bandas de riesgo:** ≤12 **Alto** (rojo), 13–17 **Medio** (ámbar), 18–23 **Bajo**
(verde), sin valoración = gris.

### 9.2 Perfil de riesgo del paciente ("Prevención y riesgo")

- Banner de nivel (rojo/ámbar/verde).
- Acción principal: **clínico/admin** → **"Definir plan de cuidados"**; **enfermería/
  cuidador** → **"Ver plan de cuidados (rondas)"**.
- Tarjetas: **Internamiento** (Ingresar/Egresar, con piso/área/cama), **Valoración de
  Braden** (último puntaje + banda + **"Valorar"**; en hospital, guardar Braden
  **autogenera el plan** esperado para ese nivel), **Indicaciones para el cuidador**
  (oculta en hospital), **Cumplimiento preventivo** (global + por tipo de actividad,
  con barras rojo/ámbar/verde: <60 / 60–84 / ≥85), **Bitácora del paciente**
  (cronología de valoraciones, tareas hechas/saltadas, eventos, internamientos), y
  **Signos a vigilar**.

### 9.3 Tablero de riesgo ("Prevención")

Lista del centro. Encabezado con chips **Alto / Medio / Bajo / Sin valoración** (tocar
filtra). Chips adicionales por **Piso** y **Área**. Pacientes ordenados por prioridad
(mayor riesgo arriba). Cada tarjeta: nombre, nivel, chip **"Vencidas"** si hay tareas
atrasadas, **% de cumplimiento**, ubicación, la preocupación principal y su acción
sugerida. En hospital, la barra superior tiene accesos al **Dashboard del centro** y a
la **agenda de prevención**.

### 9.4 Agenda de prevención / rondas

Actividades preventivas como tareas programadas. Toggle **Día / Semana**, navegador de
fecha, filtros **Paciente / Piso / Área / Riesgo**, y una barra **"Adherencia: N%"**.
Cada tarea muestra hora, título, ícono/color por tipo, estado (pendiente/vencida/hecha/
saltada), paciente (enlace a su perfil) y ubicación de la ronda; las pendientes tienen
**✓ (Marcar hecha)** y **✕ (Saltar)**, y un botón **(i) "Cómo se realiza"**. Las
completadas/saltadas se colapsan en **"Completadas · N"**.

**Cómo se generan las tareas:** en hospital, guardar Braden autocrea el plan de la banda
(tareas **sin dueño**, las marca quien está de turno). El clínico/admin también puede
definirlas con **"Definir plan de cuidados"** (lista de indicaciones con su cadencia
"cada N h" e interruptor **"Omitir cuidados nocturnos"**). Fuera de hospital, las tareas
se asignan al cuidador del paciente.

### 9.5 Dashboard del centro (hospital, `/hospital`)

Solo hospital; métricas de solo lectura (lo único editable son los turnos). Etiqueta
**"Ventana de cumplimiento"** (turno actual o últimas 24 h). KPIs: **Encamados, Alto
riesgo, Sin valoración, Vencidas, Cumplimiento %**. Tarjetas: **Distribución de
riesgo**, **Cumplimiento por tipo / por piso / por área / por turno**, **Alto riesgo sin
revisión**, **Tendencia (7 días)**, **Actividad de enfermería (7 días)**, **Incidencia/
prevalencia de LPP** (pendiente de definición), y (admin/master) el **editor de turnos**
("Configurar turnos": nombre + inicio/fin por turno, "Añadir turno", "Guardar", "Usar
24 h").

---

## 10. Cuidadores (app del cuidador)

Vista restringida del cuidador: solo sus pacientes asignados (lectura clínica) y sus
tareas.

- **Inicio ("Monitoreo"):** con **un** paciente, pestañas **Tareas** (su agenda) y
  **Paciente** (el monitor); con **varios**, pestañas **Mis tareas** y **Pacientes**
  (lista → abre el monitor). Estado vacío: "El centro aún no te ha asignado pacientes".
- **Monitor del paciente** (solo lectura): botón que se adapta —
  **"Reportar signos / recomendaciones"** (paciente con herida activa: contesta el
  cuestionario en modo reporte, ve recomendaciones y signos a vigilar, **sin agendar**)
  o **"Evaluación preventiva"** (paciente sin heridas: al terminar puede agendar el plan
  a sí mismo). Secciones: **Indicaciones del profesional**, **Recomendaciones del
  centro**, **Evolución de la herida** (última medición, cm²/cm³) y **Cita y contacto**.
- **Cuestionario preventivo:** flujo de una pregunta por paso (movilidad, humedad,
  nutrición, enrojecimiento que no cede, ¿herida?, y signos de infección si aplica),
  termina en una vista previa del plan ("Actividades a agendar" y "Signos a vigilar").

---

## 11. Eventos adversos

Bitácora por paciente con la regla centinela COFEPRIS.

- **Lista ("Eventos adversos"):** **"Registrar evento"**. Si hay centinelas pendientes,
  un **banner rojo** avisa "Hay N evento(s) centinela PENDIENTE(S) de reporte (≤24 h)".
  Cada tarjeta: gravedad (Leve/Moderado/Grave/Centinela), fecha, señales de alarma,
  descripción/acciones/evolución. Los **centinela** muestran "Reportado el [fecha]" o
  un aviso rojo con la fecha límite y **"Marcar reportado"**.
- **Captura ("Registrar evento adverso"):** Fecha y hora, **Tipo** (Infección,
  Dehiscencia, Reacción a material, Sangrado, Caída, Dolor no controlado, Deterioro de
  la herida, Otro), **Gravedad** (Centinela muestra el aviso ≤24 h), **Señales de
  alarma** (multi), **Herida relacionada** (opcional), y Descripción/Acciones/Evolución.
  **"Guardar evento"** (requiere gravedad + tipo).

Rol: personal sanitario (enfermería también puede reportar).

---

## 12. Consentimientos

Gestión de consentimiento informado por paciente. La valoración y la fotografía
requieren consentimiento de **privacidad + fotografía**; el **desbridamiento** requiere
el suyo, firmado antes del primer desbridamiento.

- Una tarjeta por tipo con su estado (fecha, **Firma** = quién otorgó, **Documento** =
  referencia). **"Registrar"** (otorgar): nombre de quien otorga + referencia de
  documento opcional → **"Otorgar consentimiento"**. **"Revocar"** pide confirmación.
- En otras pantallas, un banner rojo aparece cuando falta un consentimiento requerido,
  con acceso directo a **"Registrar consentimientos"**.

> En esta pantalla la "firma" se registra como el **nombre de quien otorga + una
> referencia de documento** (no hay trazo de firma en pantalla; el trazo digital sí
> existe en la **Fase 5 del seguimiento**).

---

## 13. Referencias / interconsultas

- **Nueva referencia:** **Especialidad** (chips rápidos + campo editable), **Motivo**,
  **Herida relacionada** (opcional), **Checklist de adjuntos** (multi). Botones
  **"Guardar y generar PDF"** (crea la referencia y abre el PDF, con paciente, personal
  que refiere y su cédula, y el centro) o **"Guardar sin generar"**.
- **Lista ("Referencias / interconsultas"):** cada tarjeta con especialidad, estado
  (Pendiente/Respondida), fecha, motivo, adjuntos y, si respondida, la respuesta.
  Acciones **PDF** y, si no respondida, **"Registrar respuesta"** (referencia de
  documento de retorno + resumen).

---

## 14. Insumos e inventario

Suite de insumos para clínicas de heridas (respaldada por Shopify). **Inicio
("Insumos"):** banner de licencia (premium o no) y tarjetas de sección con badges
(Disponible / Premium):
- **Tienda** (sin premium), **Mapeo insumo ↔ producto**, **Inventario**, **Consumo y
  costeo por paciente**, **Reabasto sugerido** (estas cuatro, premium).

- **Inventario:** existencias por sitio. Acciones (premium): **Sincronizar con
  Shopify** (centro espejo Kura+), **Descargar CSV**, **Cargar CSV**. KPIs
  **Artículos / Reordenar / Valor**; alcance **Por sitio / Por centro** (admin). Lista
  de artículos (imagen, nombre, "Externo" o "Tienda Kura+", proveedor, costo/precio,
  stock coloreado verde/ámbar/rojo). **"Agregar"**: producto de la tienda Kura+ o
  externo (nombre, proveedor, costo, precio [auto costo +30%], umbral de reorden). El
  detalle permite movimientos **Entrada / Salida / Ajuste** y ver el log.
- **Consumo:** elige un paciente, ve "Costo de insumos consumidos", chips de sugerencia
  del plan y **"Registrar consumo"** (descuenta stock).
- **Mapeo:** por cada método del protocolo, liga el insumo genérico a productos/
  variantes concretos de Shopify (tamaños/marcas/SKUs). Se usa para costeo y reabasto.
- **Reabasto sugerido:** artículos bajo umbral; **"De tu tienda Kura+"** con ± y recibir,
  **"Externos"** con proveedor y cantidad sugerida. **"Reabastecer N en la tienda"**
  arma un carrito Shopify y abre el checkout. **"Confirmar recepción"** registra la
  entrada.
- **CSV:** descarga el catálogo global (sku, nombre, proveedor, costo, precio, moneda,
  cantidad, ids de Shopify), edítalo y cárgalo para crear/reabastecer.

---

## 15. Comercial

Servicios, cobros, links Stripe y conciliación de terminal (Point). Premium. Pestañas:
**Resumen · Cobros · Conciliación · Servicios · Facturación**.

- **Resumen:** KPIs Cobrado / Pendiente, "Ingresos por mes", "Cobrado por método de
  pago" (dona), accesos a las demás secciones.
- **Cobros:** KPIs + filtros de estado (Todos/Pendiente/Pagado/Cancelado). Cada cobro
  con paciente, fecha, estado, método, total (se actualiza en tiempo real cuando Stripe
  confirma). Detalle de un cobro pendiente:
  - **"Generar link de pago (Stripe)"** → **Copiar** / **WhatsApp** para enviar al
    paciente (se concilia solo al pagar).
  - **"Verificar pago (Point)"** (si está ligado a Mercado Pago) — jala el estado.
  - **"Cancelar cobro"** y **"Registrar pago"** (efectivo/transferencia/tarjeta).
- **Conciliación:** bandeja de pagos de terminal (Mercado Pago Point) **Sin ligar /
  Ligados**. **Ligar** empata un pago con un cobro pendiente (sugerido por folio/monto);
  **Desligar** lo revierte; **"Registrar pago"** agrega un pago de terminal manual.
- **Servicios:** catálogo de honorarios. Con Acuity es de solo lectura (sincronizado);
  si no, es CRUD local (lista con precio, **"Servicio"** para crear, Editar/Activar-
  Desactivar por fila).
- **Facturación:** pendiente (CFDI, integración de PAC).

---

## 16. Terapia VAC y Laboratorios

- **Terapia VAC** (módulo `vac`, si está activo): lista y detalle de terapias de presión
  negativa, con **alarma** y un **asistente (bot)** de guardia. Accesible desde el
  detalle del paciente y la ruta **VAC**.
- **Laboratorios:** tarjeta **Laboratorios** en el expediente; registra/consulta
  resultados de laboratorio del paciente.

---

## 17. Importar / exportar (eKare)

Interoperabilidad por CSV (**"Interoperabilidad eKare"**):
- **Importar CSV desde eKare:** **"Seleccionar archivo CSV"** (muestra vista previa) +
  **mapeo de campos** (full_name, folio, birth_date, sex → columnas) → **"Importar con
  este mapeo"**.
- **Exportar mediciones a CSV:** **"Exportar CSV"** genera un CSV de todas las
  mediciones seriadas (folio, herida, etiología, fecha, largo/ancho/área/profundidad).

---

## 18. Administración (admin de centro)

**"Administración"** (rol admin, acotado a su propio centro). Pestañas: **Usuarios ·
Personal sanitario · Sitios · Configuración · Marca**.
- **Usuarios:** lista con rol, correo. Por usuario: interruptores **Activo** y
  **Premium** y un menú de rol (no puedes cambiar tu propio rol ni desactivarte).
  **"Nuevo usuario"**: nombre, rol, correo (o, para **Cuidador**, teléfono + clave),
  teléfono/cédula opcionales y sitio principal (clínicos). Al crear muestra la
  **contraseña temporal** para copiar y compartir.
- **Personal sanitario:** registro con folio/cargo/sitio. **Nuevo/Editar**: nombre,
  cargo, **cédula profesional**, especialidad (aparece en las firmas de notas), sitio
  principal y un enlace opcional a una cuenta de usuario.
- **Sitios:** lista (Clínica/Domicilio/Hospital/Otro). **Nuevo/Editar**: nombre, tipo,
  dirección.
- **Configuración (catálogo de notas):** administra los chips que el clínico elige al
  escribir la nota de seguimiento (por campo). Activar/desactivar, borrar, etiqueta
  Kura+. Herramientas: **Cargar catálogo base**, **Descargar plantilla CSV**, **Cargar
  CSV**, **"Nuevo concepto"**, y dos accesos de protocolo:
  - **"Protocolo Kura+"**: mapeo por categoría de los pasos del protocolo a conceptos del
    catálogo.
  - **"Productos del protocolo"** ("Productos del protocolo"): por cada **categoría** del
    protocolo (Limpieza, Desbridamiento, Relleno de cavidad, Apósito, Protección de piel,
    Antimicrobiano, Compresión, Descarga) defines **reglas de producto**: qué producto del
    inventario usar y en qué cantidad, opcionalmente condicionado a la **medida de la
    herida** (Área/Volumen con rango Mín/Máx), al **exudado**, la **zona anatómica** y la
    **infección/riesgo**. Cada regla: **"Buscar producto…"**, condiciones (chips), modo de
    cantidad (**Cantidad fija** / **Por área (× cm²)** / **Por volumen (× cm³)**) + **Valor**,
    y **"Guardar regla"**. Estas reglas son las que alimentan **"Sugerir del plan"** y el
    autollenado del **Plan del mes** (§6.2, §5.2).
- **Marca:** logo y color del centro.

---

## 19. Plataforma (master)

**"Plataforma"** (rol master). Primero elige un centro en el selector; las pestañas se
acotan a ese centro. Solo estructura, **sin datos clínicos**. Pestañas: **Organizaciones
· Usuarios · Personal sanitario · Sitios · Catálogo · Marca · Módulos**.
- **Acciones globales:** **Descargar parámetros clínicos (CSV)** (umbrales, bandas de
  compresión, mapeos de grados, con procedencia) y **Cargar parámetros clínicos (CSV)**
  (valida, muestra un diff antes→después y, al confirmar, aplica a **todos** los
  centros).
- **Organizaciones:** lista de centros; tarjeta de **sincronización del catálogo
  Shopify**; por centro: seleccionarlo, **Activo**, **Tipo** (tipo de centro) y
  **Miembros** (dar/quitar membresías y rol por centro). **"Nuevo centro"**.
- **Usuarios / Personal / Sitios / Catálogo / Marca:** iguales al panel de admin, para
  el centro seleccionado.
- **Módulos:** enciende/apaga módulos por **Centro / Sitio / Usuario** (heredado/
  encendido/apagado). Add-ons premium arriba: **Protocolo Kura+**, **Insumos**, **Espejo
  de inventario con Shopify**, y el número de **Guardia VAC**.

---

## 20. Dashboard principal (Inicio)

Tablero de triage; cambia según tipo de centro y rol.
- **Clínico (sus pacientes):** saludo, **Hero "Hoy"** (activos / heridas en tratamiento
  / requieren atención) con CTA **"Requieren atención"**, buscador y acceso a
  **Reportes**, dona **Estado de mis pacientes** (Avanza / Con reservas / No avanza /
  Sin datos), **Tipos de lesión**, lista **Requieren atención** (peor primero, con
  Valoración/Seguimiento) y **Continuar donde te quedaste** (con mini-gráfica de área).
- **Admin (supervisión):** KPIs (Pacientes activos, Heridas activas, **En avance %** =
  tasa de cierre, Requieren atención), dona de estado, Tipos de lesión, **Pacientes y
  sesiones por sitio** y **Carga por Kurador** (con chips de periodo).
- **Hospital:** home de prevención — KPIs (Encamados, Alto riesgo, Rondas vencidas,
  Cumplimiento %), accesos a **Rondas / Tablero de riesgo / Dashboard**, **Distribución
  de riesgo (Braden)** y lista **Requieren atención**.

---

## 21. Glosario clínico

- **Kura+ (Protocolo):** motor de apoyo a la decisión que estima el pronóstico (tres
  **Escenarios A/B/C**), el **fenotipo** de tratamiento y comercial, alertas de
  seguridad, interconsultas y el régimen sugerido. No sustituye el juicio clínico.
- **Escenarios A / B / C:** trayectorias pronósticas (A = favorable … C = contención).
- **Checkpoint de Sheehan:** regla de seguimiento que compara el área actual contra la
  basal a una semana dada y decide si la herida está **en trayectoria de cierre**,
  requiere **extender observación** o **reclasificar**. Aplica penalizaciones (−5 pp) por
  infección activa, baja adherencia, deterioro del lecho o aumento de exudado.
- **Escala de Braden:** valoración del riesgo de LPP en 6 subescalas (6–23 puntos).
  Bandas: ≤12 Alto, 13–17 Medio, 18–23 Bajo.
- **IWII:** criterios de infección de la herida (International Wound Infection
  Institute).
- **Wagner / WIfI / Universidad de Texas / IDSA-IWGDF:** clasificaciones del pie
  diabético (severidad, isquemia/infección, estadio, infección).
- **CEAP / Rutherford:** clasificaciones de enfermedad venosa (CEAP) y arterial
  (Rutherford).
- **NPUAP/EPUAP:** estadificación de la lesión por presión.
- **WUWHS:** graduación de severidad de la herida (World Union of Wound Healing
  Societies).
- **ABI / ITB:** índice tobillo-brazo (perfusión de la extremidad).
- **Fórmula de Kundin:** cálculo del volumen de la herida a partir de sus dimensiones.
- **LPP:** lesión por presión.
- **APP / APNP:** antecedentes personales patológicos / no patológicos.
- **Plan del mes (programa de tratamiento):** plan mensual que se arma tras la valoración
  (insumos por procedimiento + cadencia de sesiones); genera las sesiones del mes y la
  explosión de materiales.
- **Regla de producto (Protocolo Kura+):** regla que, por categoría del protocolo, asigna
  un producto del inventario y una cantidad, condicionada opcionalmente a la medida de la
  herida, el exudado, la zona y la infección. Alimenta "Sugerir del plan" y el Plan del mes.
- **Insumo por sesión vs. mensual (multidosis):** un insumo "por sesión" se consume en cada
  cura (mensual = cantidad × sesiones); uno "mensual/multidosis" se compra 1–2 veces al mes
  y su cantidad ya es la del mes.
- **Folio:** identificador del expediente (EXP2026-…, HOSP-…, CUI-…).

---

## 22. Matriz de permisos por rol

| Acción | clinico | admin | enfermeria | cuidador | master |
|---|:---:|:---:|:---:|:---:|:---:|
| Ver expediente clínico | ✅ | ✅ | ✅ (lectura) | ✅ (solo asignados) | ❌ |
| Crear/editar paciente | ✅ | ✅ | ❌ | ❌ | ❌ |
| Nueva consulta / valoración | ✅ | ✅ | ❌ | ❌ | ❌ |
| Seguimiento (5 fases) | ✅ | ✅ | ❌ | ❌ | ❌ |
| Diagnósticos CIE-10 | ✅ | ✅ | ❌ | ❌ | ❌ |
| Cobros / pagos | ✅ | ✅ | ❌ | ❌ | ❌ |
| Reportes | ✅ | ✅ | ✅ | ❌ | ❌ |
| Valorar Braden | ✅ | ✅ | ✅ | ❌ | ❌ |
| Ejecutar rondas de prevención | ✅ | ✅ | ✅ | ✅ (propias) | ❌ |
| Reportar evento adverso | ✅ | ✅ | ✅ | ❌ | ❌ |
| Administración del centro | ❌ | ✅ | ❌ | ❌ | ❌ |
| Plataforma (centros/módulos/usuarios) | ❌ | ❌ | ❌ | ❌ | ✅ |
| Parámetros clínicos del motor (CSV) | ❌ | ❌ | ❌ | ❌ | ✅ |

---

*Documento de referencia de uso. La lógica clínica del motor (umbrales, cadencias,
paleta hospitalaria) puede seguir en validación; este manual describe la operación de la
plataforma, no constituye una guía de práctica clínica.*
