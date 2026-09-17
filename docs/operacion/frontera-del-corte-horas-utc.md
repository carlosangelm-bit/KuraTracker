# La frontera del corte — sellos en hora local (UTC−6) → UTC

**Estado: DOCUMENTADO, NO CONSTRUIR.** Decisión de Carlos (17-sep-2026): los datos ya
registrados en producción son **desechables**; no se corrige historia. La corrección
histórica sale del camino crítico. **No se escribe el script.** Este documento conserva la
arquitectura del corte por si algún día se decide, y para dejar constancia de por qué la
frontera es donde es.

## El defecto (por qué había que pensar en un corte)

El cliente sellaba `timestamptz` con `DateTime.now().toIso8601String()` — hora del
DISPOSITIVO **sin zona**. Postgres interpreta esa cadena naive como UTC, así que un centro
en UTC−6 (México, sin horario de verano desde octubre 2022) guardaba el instante **+6 h
adelantado**. El desfase es **constante +6 h** para todo el dato posterior a 2022-11-01
(Carlos lo confirmó).

## La frontera: el disparador que le devuelve `created_at` a la base

El arreglo hacia adelante (que SÍ se hace, tabla por tabla) es que **la base** ponga los
sellos de sistema: `default now()` en INSERT + trigger `set_updated_at()` (0002) en UPDATE;
y que los campos de EVENTO que captura el cliente vayan en **UTC explícito** (`.toUtc()`).

Eso crea una **frontera limpia y auto-marcada** en el dato, sin columna de bandera:

- **Antes de la frontera** (cliente sellaba local): `created_at` viene de `DateTime.now()`
  naive → guardado +6 h. Estas filas están desfasadas de forma constante.
- **Después de la frontera** (la base sella): `created_at = now()` del servidor → UTC real,
  con **precisión de microsegundo** de Postgres (no de milisegundo del cliente).

La **precisión** es la firma que separa las dos épocas sin necesidad de fechas de corte:
un `created_at` con microsegundos distintos de `000` y sin el patrón de +6 h nació del
servidor; uno con desfase de +6 h respecto de su hermano de auditoría nació del cliente
viejo. **La huella dice quién escribió, no si escribió bien.**

## Si algún día se decidiera corregir (guion, NO construido)

Requisitos que Carlos fijó y que este documento preserva:

1. **Guarda de fecha explícita `>= 2022-11-01`** — México dejó el horario de verano en
   octubre 2022; TODO el dato es posterior, así que el offset es constante +6 h. La guarda
   impide que alguien reúse el script sobre dato anterior (donde el offset NO sería
   constante).
2. **Excluir los sitios ya correctos** (`.toUtc()` de siempre): `data_repository` createdAt
   de modelo, `p_until` (grant), `uploaded_at` (clinical_params), `archived_at`,
   `occurred_at`/createdAt (adverse_events). Esas filas tienen precisión de milisegundo y
   están BIEN: si entran en la corrección, se rompen.
3. **Ensayo en sandbox** primero, **script reversible**, **respaldo de producción
   confirmado** y **aprobación explícita de Carlos** antes de tocar prod.
4. Producción **sigue sin PITR** — eso no cambió aunque los datos sean desechables.

## Por qué NO se construye hoy

Los datos históricos son desechables (Carlos presenta sobre producción con dato que puede
regenerar). El valor está en que **lo nuevo nazca bien**, no en reparar lo viejo. La
arquitectura del corte queda aquí escrita; el trinquete `no_local_timestamp_writes_test`
lleva la deuda del cliente hacia 0 tabla por tabla.
