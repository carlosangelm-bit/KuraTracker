# KuraTracker — El paquete de salida: la práctica existe, el producto no la sostiene

**Fecha:** 31-ago-2026 · **Base:** `main` en `a5f3b16`
**Origen:** práctica descrita por Carlos — al terminar contrato, a los clientes se les
comparten **todos sus expedientes** y **CSV con mediciones y consultas**.

---

## 0. Esto reencuadra la decisión de vencimiento

Si la salida estándar es una **entrega de datos**, entonces la política de vencimiento no es
principalmente sobre qué se restringe: es sobre **producir esa entrega de forma confiable**.
La palanca comercial sigue siendo "no puedes crecer" (sin altas, sin premium, sin pacientes
nuevos); la salida es "aquí están tus datos".

Retiro el énfasis que puse en el escalonamiento de restricciones. Sigue siendo la forma
correcta de restringir, pero es lo secundario. Lo que hay que construir es el paquete.

---

## 1. Qué existe hoy

**Una sola exportación**, en `lib/features/import_export/import_export_screen.dart:19`
(`_exportMeasurementsCsv`): mediciones, 8 columnas —
`folio_paciente, herida_id, etiologia, fecha, largo_cm, ancho_cm, area_cm2, profundidad_cm`.

### Verifiqué el alcance, porque el código Dart se ve sin filtro

`listAllPatients()` (`data_repository.dart:3091`) **no** filtra por organización. Fui a ver la
policy antes de dar la alarma, y **está bien**:

```sql
-- 0011_organizations.sql:333
create policy patients_select on public.patients for select using (
  (public.is_admin() and organization_id = public.current_organization_id())
  or exists (select 1 from public.staff_patient_assignments spa ...)
);
```

La RLS acota al **centro activo del llamador**. Un admin de centro exporta lo suyo y nada
más. **No hay fuga entre centros.** Lo dejo escrito porque la asimetría (Dart sin filtro,
RLS con filtro) invita a concluir lo contrario, y la conclusión sería falsa.

---

## 2. Los cuatro huecos entre la práctica y el producto

### 2.1 El master NO puede generar la exportación del cliente

`is_admin()` lee el conjunto de roles. Un master tiene `roles = {master}`, así que
`is_admin()` es **false** y no pasa `patients_select` — coherente con la "regla de oro" del
`0012` (el master no tiene datos clínicos propios).

Consecuencia: la entrega la hace, o **el propio admin del cliente**, o alguien con **acceso
privilegiado a la base** (service role / SQL Editor) por fuera de la app. Si hoy es lo
segundo, es una operación manual, privilegiada y **sin rastro** — justo en el momento en que
salen datos clínicos de la plataforma.

### 2.2 Las consultas no se exportan

Carlos dice "mediciones **y consultas**". Solo existen las mediciones. La parte de consultas
se está armando a mano hoy.

### 2.3 Los expedientes no tienen exportación

No hay ninguna generación de expediente (PDF o documento) en el producto. "Todos sus
expedientes" es trabajo manual completo.

### 2.4 La única exportación que existe no se puede descargar

```dart
showDialog(... content: SingleChildScrollView(child: Text(csv)),
           actions: [TextButton(... child: const Text('Cerrar'))]);
```

Muestra el CSV en un modal, con un solo botón: "Cerrar". **No descarga** — y el proyecto ya
tiene `downloadCsv()` (`lib/services/csv_download.dart`, con implementaciones web e io).
Para una entrega real de miles de filas, seleccionar y copiar desde un diálogo no es viable.

**Arreglo de 10 minutos:** agregar la acción de descarga al diálogo usando el
`downloadCsv()` que ya existe. Es el cambio con mejor relación esfuerzo/valor de toda esta
lista.

---

## 3. Lo que hay que construir: el paquete de salida

Un solo comando, ejecutable **por el admin del centro** (que es quien tiene el alcance de RLS
correcto), que produzca:

1. **Mediciones** — CSV. Ya existe; falta descarga y, si se quiere, más columnas
   (composición de tejido R/Y/B, tunelización, socavamiento).
2. **Consultas** — CSV. No existe. Una fila por consulta con paciente, fecha, autor,
   diagnóstico, plan.
3. **Expedientes** — un documento por paciente. No existe.
4. **Fotografías** — están en Storage; hay que decidir si van en el paquete. Para un
   expediente de heridas, la serie fotográfica *es* evidencia clínica; omitirla hace la
   entrega incompleta.
5. **Manifiesto** — qué se exportó, cuántos registros de cada cosa, fecha, y quién lo
   generó.

El punto 5 es el que convierte la entrega en algo defendible: hoy no queda registro de qué
se entregó. Y conecta con un pendiente ya identificado — **existe un `audit_log` en Postgres
que ninguna pantalla lee.** El paquete de salida es un buen primer consumidor de ese rastro.

---

## 4. Por qué esto ayuda a vender, no solo a salir bien

La portabilidad no es solo un deber: en venta de EHR, el miedo al secuestro de datos es una
objeción real. Un cliente que sabe que puede irse con todo su expediente en un clic entra
con menos fricción. Convertir la salida en función de producto —y poder decirlo en la
conversación comercial— vale más que la retención que se consigue haciéndola difícil.

Y al revés: **la exportación no debe bloquearse nunca**, ni al vencer ni al cancelar ni por
adeudo. El expediente clínico no es de Kura+; es del paciente y de su médico tratante. Vale
que el contrato lo diga y que la plataforma lo cumpla por diseño.

---

## 5. Orden sugerido

1. **Descarga en el diálogo de exportación** (§2.4). Diez minutos, desbloquea la práctica
   actual.
2. **CSV de consultas** (§3.2). Completa lo que Carlos ya entrega a mano.
3. **Manifiesto + registro de la entrega** (§3.5). Convierte la operación manual en un hecho
   auditable.
4. **Expedientes** (§3.3) — es el más grande; requiere decidir formato y si incluye fotos.
5. **Escalonamiento de restricciones al vencer** — después de lo anterior. Restringir antes
   de poder entregar bien es el orden equivocado.
