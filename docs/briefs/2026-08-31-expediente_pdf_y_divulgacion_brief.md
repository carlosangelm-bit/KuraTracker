# KuraTracker — Expediente en PDF + registro de divulgación

**Fecha:** 31-ago-2026 · **Base:** `main` en `952640c` (§2.4 y §3.2 en prod)
**Para:** agente de desarrollo

## Decisiones tomadas por Carlos

1. **El expediente PDF incluye la serie fotográfica completa**, reescalada a resolución
   clínica (no los originales). Un PDF por paciente.
2. **La entrega la genera siempre el admin del centro cliente.** *No* se construye vía para
   el master — se respeta la regla de oro del `0012` (el master no toca datos clínicos) y no
   se abre excepción que haya que auditar.
3. **El manifiesto NO va en `audit_log`.** Va en tabla propia. Razón en §3.

---

## 1. Lo que ya existe y hay que reusar

| pieza | dónde |
|---|---|
| `pdf: ^3.11.1` + `printing: ^5.13.4` | ya en `pubspec.yaml` |
| Dos generadores de PDF como patrón a seguir | `lib/services/referral_pdf.dart`, `lib/services/prevention_report_pdf.dart` |
| Reescalado de imágenes | `image: ^4.3.0` y `lib/services/image_transcode.dart` |
| Acceso a fotos | `lib/services/photo_upload_service.dart` — bucket **privado**, se accede con `createSignedUrl(path, 3600)`; nunca URL pública |

**No** está `archive` en `pubspec.yaml`. Hace falta para empaquetar (ver §2).

## 2. El problema de escala, que hay que resolver antes de escribir el generador

Kura+ tiene **300+ pacientes**. Un PDF por paciente significa 300 archivos, y cada uno
requiere descargar sus fotos por signed URL (una petición por imagen).

Consecuencias que hay que decidir **antes** de codificar:

- **Empaquetado.** Sin ZIP son 300 descargas separadas: inutilizable. Hay que agregar
  `archive` y entregar un solo `.zip`.
- **Generación por lotes.** Generar 300 PDFs con fotos en una pestaña del navegador es
  frágil: memoria, tiempo, y la pestaña tiene que quedarse abierta. Hay que procesar por
  bloques, con progreso visible y capacidad de reanudar, no en un solo `await`.
- **Honestidad sobre el límite:** si un centro grande hace que esto no sea viable en el
  navegador, la alternativa es generación en servidor (Edge Function), que es **otro
  proyecto** — Deno + PDF + imágenes, con límite de tiempo de ejecución. **No lo empieces
  sin decirlo.** Si al probar con los 300+ de Kura+ el navegador no aguanta, para y repórtalo
  en vez de forzarlo.

**Sugerencia de alcance:** dos modos, mismo generador.
- **Un paciente** (uso clínico normal: imprimir el expediente de alguien). Sin ZIP, inmediato.
- **Entrega completa** (offboarding): por lotes, con progreso, resultado en un ZIP.

El primero es útil desde el día uno y sirve para validar el generador con un caso real antes
de enfrentarlo a 300.

## 3. Registro de divulgación — tabla propia, no `audit_log`

`audit_log` (`0001:375-385`) es una bitácora de **cambios**:

```sql
action text not null,      -- 'insert' | 'update' | 'delete'
table_name text not null,
record_id uuid,
old_data jsonb, new_data jsonb
```

Una exportación no es un cambio: no tiene `record_id`, no tiene old/new, su acción no es
ninguna de las tres, y no hay dónde poner lo que importa (cuántos registros, de qué
pacientes, en qué archivo). Meterla ahí obliga a abusar de `action` y dejar media tabla en
null.

Una exportación es una **divulgación**, categoría que el esquema no tiene hoy. En expediente
clínico son cosas distintas, y la distinción es normativa (NOM-024 se ocupa de acceso y
divulgación, no solo de modificación). **KuraTracker tiene rastro de cambios y ninguno de
divulgación** — incluidas las dos exportaciones CSV que acaban de salir a producción.

```sql
-- Migración: registro de divulgaciones de datos.
create table if not exists public.data_disclosures (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id),
  actor_id uuid references auth.users(id),
  kind text not null,               -- 'csv_mediciones' | 'csv_consultas' | 'expedientes_pdf'
  scope jsonb,                      -- filtros aplicados (rango de fechas, pacientes, etc.)
  record_count integer,             -- filas o pacientes incluidos
  patient_count integer,
  file_name text,
  occurred_at timestamptz not null default now()
);

create index if not exists idx_data_disclosures_org
  on public.data_disclosures(organization_id, occurred_at desc);
```

RLS: **insert** para quien pertenece a la organización; **select** para admin de esa
organización y para master. Nadie puede borrar ni actualizar — un registro de divulgación que
se puede editar no sirve de nada. (Trigger que rechace UPDATE y DELETE, igual que el patrón
del `0097`.)

**Alcance de este paso:** escribir el registro desde las **tres** exportaciones —las dos CSV
que ya están en producción y el PDF cuando exista. El manifiesto que va dentro del ZIP se
genera del mismo dato.

**No** construyas el lector del `audit_log`: eso sigue siendo otro proyecto. Una pantalla
simple que liste `data_disclosures` del centro sí vale, y es media hora.

## 4. Contenido del PDF por paciente

Mínimo para que un clínico receptor pueda continuar el tratamiento:

- Identificación del paciente (folio, datos demográficos) y del centro emisor.
- Diagnósticos y comorbilidades.
- Por cada herida: etiología, ubicación, y la **serie cronológica** de valoraciones con
  medidas (largo, ancho, área, profundidad), composición de tejido, tunelización y
  socavamiento, más la **foto de esa fecha** junto a sus medidas.
- Consultas: fecha, autor con cédula, nota (cuidado, procedimiento, materiales, evolución).
- Plan de tratamiento vigente al cierre.
- Pie de página con fecha de generación y quién lo generó.

La clave de la utilidad clínica es que **la foto vaya junto a las medidas de su misma fecha**,
no en un anexo al final: así se lee la evolución.

## 5. Orden

1. **`data_disclosures`** (§3) + escritura desde las dos CSV ya desplegadas. Cierra el hueco
   que el último deploy abrió.
2. **PDF de un paciente** (§4) reusando el patrón de `referral_pdf.dart`. Validar con un
   paciente real de Kura+ que tenga varias consultas y fotos.
3. **Entrega completa por lotes + ZIP** (§2), agregando `archive`. Probar con los 300+ de
   Kura+ y **reportar si no es viable en navegador** en vez de forzarlo.
4. Pantalla que liste las divulgaciones del centro.
