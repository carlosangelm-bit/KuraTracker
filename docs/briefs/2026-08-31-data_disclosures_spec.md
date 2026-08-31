# KuraTracker — Fase 1: registro de divulgación (`data_disclosures`). Spec autocontenida.

**Fecha:** 31-ago-2026 · **Base:** `main` en `e1a3543`
**Para:** agente de desarrollo. Este documento es autosuficiente — no necesitas los briefs
anteriores para implementarlo.

---

## 0. Por qué esta fase va ANTES de la Fase 3

Hoy quedaron desplegadas **tres** vías por las que datos clínicos salen de la plataforma:

1. `mediciones.csv` — todas las mediciones del centro.
2. `consultas.csv` — todas las consultas del centro, con el contenido de las notas.
3. **Expediente completo de un paciente en ZIP** — demográficos, diagnósticos, consultas y
   **todas las fotos originales**.

**Ninguna de las tres deja constancia de que ocurrió.** La Fase 3 agrega una cuarta, que es
la divulgación más grande que el sistema puede producir: el centro entero de una sola vez.

Construir la cuarta antes del registro significa que la mayor salida de datos posible se
despliega sin rastro. La razón de existir de un registro de divulgación es el día en que
alguien pregunta "qué salió, cuándo y quién se lo llevó" — y esa pregunta llega **después**,
cuando el registro existe o no existe.

---

## 1. Por qué tabla propia y no `audit_log`

`audit_log` (`0001:375-385`) es bitácora de **cambios**:

```sql
action text not null,      -- 'insert' | 'update' | 'delete'
table_name text not null,
record_id uuid,
old_data jsonb, new_data jsonb
```

Una exportación no es un cambio: no tiene `record_id`, no tiene old/new, su acción no es
ninguna de las tres, y no hay dónde poner lo que importa (cuántos registros, de qué
pacientes, en qué archivo). Meterla ahí obliga a abusar de `action` y dejar media tabla nula.

Una exportación es una **divulgación** — categoría que el esquema no tiene. En expediente
clínico son cosas distintas y la distinción es normativa: NOM-024 se ocupa de acceso y
divulgación, no solo de modificación.

**No construyas el lector del `audit_log`.** Sigue siendo otro proyecto.

---

## 2. Migración

```sql
-- =============================================================================
-- NNNN_data_disclosures.sql — Registro de divulgaciones de datos clínicos.
-- =============================================================================
-- Toda salida de datos del centro (CSV de mediciones, CSV de consultas,
-- expediente de un paciente, entrega completa del centro) deja una fila aquí.
-- NO es la bitácora de cambios (audit_log): esa registra modificaciones; esta
-- registra qué SALIÓ de la plataforma, cuándo y por mano de quién.
-- =============================================================================

create table if not exists public.data_disclosures (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id),
  actor_id uuid references auth.users(id),
  actor_email text,                 -- desnormalizado a propósito: el registro debe
                                    -- seguir siendo legible si el perfil se borra
  kind text not null,               -- 'csv_mediciones' | 'csv_consultas'
                                    -- | 'expediente_paciente' | 'entrega_centro'
  scope jsonb,                      -- filtros aplicados: patient_id, rango de fechas, etc.
  record_count integer,             -- filas (CSV) o archivos (ZIP)
  patient_count integer,
  photo_count integer,
  missing_count integer,            -- fotos/registros que no se pudieron incluir
  file_name text,
  occurred_at timestamptz not null default now()
);

create index if not exists idx_data_disclosures_org
  on public.data_disclosures(organization_id, occurred_at desc);

comment on table public.data_disclosures is
  'Registro de divulgaciones: qué datos clínicos SALIERON de la plataforma, cuándo '
  'y por mano de quién. Distinto de audit_log (que registra cambios). Inmutable: '
  'un registro de divulgación que se puede editar no sirve de nada.';

-- RLS
alter table public.data_disclosures enable row level security;

-- Insert: cualquier miembro autenticado, para SU organización activa.
create policy data_disclosures_insert on public.data_disclosures
  for insert with check (organization_id = public.current_organization_id());

-- Select: admin de esa organización, y master.
create policy data_disclosures_select on public.data_disclosures
  for select using (
    (public.is_admin() and organization_id = public.current_organization_id())
    or public.is_master()
  );

-- Inmutabilidad: ni UPDATE ni DELETE, para nadie. Mismo patrón que el 0097.
create or replace function public.prevent_disclosure_change()
returns trigger language plpgsql set search_path = public, pg_temp as $$
begin
  raise exception 'Registro de divulgación: es inmutable.';
end; $$;

create trigger trg_prevent_disclosure_change
  before update or delete on public.data_disclosures
  for each row execute function public.prevent_disclosure_change();
```

**Nota sobre `is_master()` en el select:** un master no puede leer pacientes (regla de oro del
`0012`), pero **sí** debe poder ver el registro de divulgaciones — son metadatos de operación,
no datos clínicos. Es exactamente la información que necesita para supervisar la plataforma
sin acceder a expedientes.

---

## 3. Los tres puntos de escritura (ya desplegados, hay que instrumentarlos)

| vía | archivo | `kind` |
|---|---|---|
| CSV de mediciones | `lib/features/import_export/import_export_screen.dart:21` | `csv_mediciones` |
| CSV de consultas | `lib/features/import_export/import_export_screen.dart:54` | `csv_consultas` |
| Expediente de un paciente | `lib/features/patients/patient_detail_screen.dart` (`_exportPatientRecord`) | `expediente_paciente` |

Y la Fase 3 agregará `entrega_centro`.

**Cuándo escribir:** *después* de que la descarga se haya entregado, no antes. Si la
generación falla a la mitad, no hubo divulgación y no debe haber registro. Si la generación
tuvo faltantes parciales pero se entregó, sí hay registro, con `missing_count`.

**El manifiesto que ya va dentro del ZIP se genera del mismo dato.** No dupliques la lógica:
construye el resumen una vez, escríbelo al manifiesto y a la tabla.

---

## 4. Honestidad sobre el alcance de este registro

La escritura la hace el cliente. Eso significa que **es un registro de uso legítimo, no un
control de seguridad**: un admin decidido a no dejar rastro puede llamar a PostgREST
directamente y omitir el insert.

Hacerlo inevitable requeriría mediar las exportaciones en el servidor —una Edge Function que
genere y entregue— y eso es otro proyecto, con sus propios límites de tiempo de ejecución.

**No presentes esta tabla como algo que impide una fuga.** Lo que hace, y es valioso, es dejar
constancia verificable de las entregas normales — que es exactamente lo que hoy no existe
cuando Carlos entrega expedientes a mano.

---

## 5. Pantalla (después de la tabla, media hora)

Lista simple de `data_disclosures` del centro activo: fecha, quién, qué tipo, conteos, archivo.
Ordenada por fecha descendente. Visible para admin del centro y para master.

Sin filtros elaborados en la primera versión — que exista y se pueda leer es el 90% del valor.

---

## 6. Detalle aparte, de una línea

`patient_detail_screen.dart:149`:

```dart
final canExportRecord =
    exportUser?.role == AppRole.admin || (exportUser?.isMaster ?? false);
```

Debería ser `exportUser?.isAdmin`. Funciona hoy (por precedencia, cualquier conjunto con
`admin` y sin `master` espeja a `admin`), así que **no es un bug** — pero es una comparación
nueva contra el espejo escalar, introducida después del barrido del punto 6.

**Lo relevante no es la línea, es que la convención no se sostiene sola.** Vale anotarla en
`CLAUDE.md` —"para decidir permisos usa los getters del conjunto (`isAdmin`, `canDiagnose`,
`isNurse`), nunca `user.role == AppRole.x`"— o cada función nueva la va a reintroducir.
