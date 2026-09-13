# Ensayo del backfill de licencias (0114) contra una copia de producción

**Estado:** procedimiento, no ejecutado.
**Fecha:** 2026-09-13.
**Quién lo corre:** Carlos. Nadie más toca las bases.

---

## 1. Qué se está probando y por qué

Producción está en la migración **0107**. Fase 2 trae **24 migraciones pendientes (0108 → 0131)**.
Entre ellas, `0114_license_backfill.sql` es la única que **congela un estado**: escribe, centro
por centro, los derechos (módulos y asientos) que ese centro tendrá a partir de ese momento,
deduciéndolos del estado de hoy.

Todo lo demás es reversible o inerte. El backfill no: si escribe mal el tope de asientos o
deja fuera un módulo, el cliente real se entera al día siguiente, intentando dar de alta a
alguien o abriendo una pantalla que ayer veía.

**0114 nunca se ha ejecutado contra datos reales.** Solo contra sandbox y staging, que se
sembraron para que funcione.

El ensayo consiste en: restaurar un respaldo de producción en un proyecto desechable, correr
las 24 migraciones en orden, y comparar lo que quedó contra lo que ese cliente tiene
contratado hoy. Si no coinciden, el problema se encuentra aquí y no en producción.

---

## 2. Los cuatro riesgos concretos que el ensayo debe descartar

### Riesgo 1 — El tope de asientos se congela con una definición y se cobra con otra

`0114` fija `seat:clinico.quantity = consumed_seats(org)`, la función de **0106**:

```sql
-- 0106: cuenta a TODOS los que no son cuidador, mirando m.roles (la MEMBRESÍA)
where m.is_active and p.is_active and not m.seat_exempt
  and exists (select 1 from unnest(m.roles) r where r <> 'cuidador')
```

Pero quien después **exige** ese tope es `consumed_seat_demand` (0128), construida sobre los
contadores de **0116**, que miden por `p.roles` (el **PERFIL**):

```
demanda = consumed_clinical_seats            -- p.roles tiene clinico o enfermeria
        + max(0, consumed_admin_slots − cupos_admin_incluidos)
cupos_admin_incluidos = 3 si module:admin está activo, 0 si no
```

Dos definiciones distintas para el mismo número: una mira la membresía, la otra el perfil.
Mientras `m.roles` y `p.roles` coincidan, `consumed_seats ≥ demanda` siempre y el tope queda
holgado o justo — nunca corto. **Si divergen en producción** (un perfil con rol clínico cuya
membresía dice solo `cuidador`), la demanda puede salir **mayor** que el tope congelado: el
centro nace por encima de su propio límite y **toda alta falla** con `SEAT_NO_CLINICAL`.

Esto es lo primero que hay que medir, y se puede medir **en producción, sin tocar nada**
(consulta P3, sección 4).

### Riesgo 2 — `module:admin` se regala

`0114` otorga `module:admin` a **todo centro con más de un miembro activo**, gratis
(`source='master'`, sin periodo). Bajo el empaquetado nuevo, Administración avanzada son
**$1,200/centro/mes**. Es decir: el cliente existente se queda con el módulo de pago sin
pagarlo, para siempre, hasta que alguien lo quite a mano.

Probablemente eso es lo correcto (no se le puede quitar a un cliente algo que ya usa), pero
tiene que ser **una decisión tomada, no un efecto secundario**. El ensayo dice exactamente a
cuántos centros y a cuáles.

### Riesgo 3 — `seat:protocolo` sale en cero

Los asientos de Protocolo Kura+ se deducen de dos banderas legadas:
`organizations.premium_protocolo_kura` y `profiles.premium_enabled`. Si producción nunca las
escribió (o las escribió en otra tabla), el centro real termina con **cero asientos Kura+**
aunque lo esté usando. La pantalla se le apaga.

### Riesgo 4 — El bloque de aborto de 0114

`0114` termina abortando la migración si algún centro activo perdería `clinico`, `insumos` o
`comercial`. La condición del `insert` y la del `check` son **la misma expresión**, así que en
una copia virgen de producción **no puede dispararse**: la tabla `org_entitlements` nace en
0113, vacía.

Por lo tanto: **si el aborto se dispara, la copia no era virgen** — algo ya había escrito
derechos, y el `on conflict do nothing` se los saltó. En ese caso no se debilita el bloque: se
averigua quién escribió esas filas.

Nota: el bloque **no cubre `module:admin`**. Un centro que hoy llega a Administración pero se
queda sin el derecho no dispara nada. Bajo el diseño nuevo eso no es pérdida (la gestión
básica viaja con la licencia clínica), pero conviene confirmarlo con la app ya desplegada.

---

## 3. Antes de empezar: lo que hay que tener a mano

- [ ] El **contrato o la última factura** del centro real. El veredicto del ensayo no se
      compara contra la base, se compara contra lo que ese cliente está pagando.
- [ ] Un **respaldo reciente de producción** (Supabase → Database → Backups).
- [ ] Un **proyecto desechable** de Supabase, misma región, creado para esto y borrado después.
      Nombre sugerido: `kt-ensayo-0114`.
- [ ] La rama de Fase 2 con las 24 migraciones.

**Nunca** se apunta el ensayo al proyecto de producción. Las únicas consultas que se corren en
producción son las de la sección 4, y son todas `SELECT`.

---

## 4. Paso 1 — Fotografía de producción (solo lectura)

Correr en el SQL Editor de **producción**. Guardar los tres resultados; son la referencia
contra la que se compara todo después.

**P1 — Censo de centros**

```sql
select o.id, o.name, o.center_type, o.is_active, o.is_test,
       o.premium_protocolo_kura,
       (select count(*) from public.user_center_memberships m
          join public.profiles p on p.id = m.profile_id
         where m.organization_id = o.id and m.is_active and p.is_active) as miembros_activos,
       (select count(*) from public.profiles p
         where p.organization_id = o.id and p.premium_enabled) as perfiles_premium
from public.organizations o
order by o.is_active desc, o.name;
```

Esto responde de entrada el **Riesgo 2** (`miembros_activos > 1` → se regala `module:admin`) y
el **Riesgo 3** (`premium_protocolo_kura` y `perfiles_premium`).

**P2 — Módulos encendidos hoy, a nivel centro**

```sql
select ms.organization_id, ms.module_key, ms.enabled
from public.module_settings ms
where ms.site_id is null and ms.profile_id is null
order by 1, 2;
```

Un centro sin fila aquí hereda el default: `insumos` y `comercial` encendidos **solo si**
`center_type = 'clinica_heridas'`.

**P3 — La divergencia que causa el Riesgo 1**

```sql
select m.organization_id, p.id as profile_id, p.full_name,
       m.roles  as roles_membresia,
       p.roles  as roles_perfil,
       p.role   as rol_legado,
       m.seat_exempt
from public.user_center_memberships m
join public.profiles p on p.id = m.profile_id
where m.is_active and p.is_active
  and m.roles is distinct from p.roles
order by 1, 3;
```

**Cero filas = el Riesgo 1 no existe en producción** y el ensayo se vuelve una confirmación
rutinaria. Cualquier fila hay que mirarla una por una antes de seguir.

---

## 5. Paso 2 — La copia desechable

Dos caminos; elegir uno según el plan de Supabase.

**Opción A — Branching de Supabase** (si el plan lo incluye). Crear una rama a partir de
producción. Es el camino corto y no requiere manejar el respaldo a mano.

**Opción B — Restaurar el respaldo en un proyecto nuevo.**

1. Descargar el respaldo desde el dashboard de producción.
2. Crear el proyecto `kt-ensayo-0114`.
3. Restaurar con `psql` / `pg_restore` contra la cadena de conexión del proyecto nuevo.

En cualquiera de los dos casos, antes de seguir, **confirmar que la copia es realmente virgen**:

```sql
select count(*) as filas_de_derechos
from information_schema.tables
where table_schema = 'public' and table_name = 'org_entitlements';
-- Esperado: 0 (la tabla NO debe existir todavía; nace en 0113).
```

Si la tabla ya existe, la copia no salió de 0107 y el ensayo no es válido.

---

## 6. Paso 3 — Correr las 24 migraciones

En orden, **0108 → 0131**, una por una, cada una en su propia transacción, capturando la
salida. No en bloque: si algo falla, importa saber exactamente en cuál.

```bash
for f in supabase/migrations/01{08,09}*.sql supabase/migrations/01[1-3]*.sql; do
  echo "=== $f ==="
  psql "$ENSAYO_DB_URL" --single-transaction -v ON_ERROR_STOP=1 -f "$f" || break
done
```

Las migraciones emiten `NOTICE`. El de 0114 es el que importa:

```
NOTICE: Backfill de licencia verificado: ningún centro activo pierde un módulo.
```

Si en lugar de eso aparece `Backfill incompleto: algún centro perdería un módulo bajo el AND
→ ...`, **parar**. Ver Riesgo 4: no se debilita el bloque, se averigua por qué la copia tenía
derechos previos.

---

## 7. Paso 4 — Las afirmaciones

Todo esto se corre **en la copia**, ya con las 24 migraciones aplicadas.

### A. Tope congelado vs demanda futura — la afirmación principal

```sql
select o.name,
       (select e.quantity from public.org_entitlements e
         where e.organization_id = o.id and e.kind = 'seat'
           and e.key = 'clinico' and e.status = 'active')      as tope_clinico,
       public.consumed_seat_demand(o.id)                        as demanda,
       public.consumed_clinical_seats(o.id)                     as clinicos,
       public.consumed_admin_slots(o.id)                        as administrativos,
       exists (select 1 from public.org_entitlements e
                where e.organization_id = o.id and e.kind = 'module'
                  and e.key = 'admin' and e.status = 'active')  as tiene_modulo_admin
from public.organizations o
where o.is_active
order by o.name;
```

**Verde:** `demanda <= tope_clinico` en todas las filas.
**Rojo:** cualquier fila con `demanda > tope_clinico` — ese centro nace por encima de su tope
y no podrá dar de alta a nadie. Es el Riesgo 1 materializado; la corrección es en `0114`
(congelar con la misma definición que después se exige), no en el cliente.

**Ámbar:** `demanda = tope_clinico`. Es lo esperado por diseño ("tope = uso actual"), pero
significa cero holgura: el cliente no puede agregar a nadie sin comprar un asiento. Decidir si
se le regala holgura (+1 o +2) en el momento del corte.

### B. ¿Puede el centro dar de alta a alguien más?

La pregunta anterior, hecha al guard mismo en lugar de a la aritmética:

```sql
do $$
declare r record;
begin
  for r in select id, name from public.organizations where is_active loop
    begin
      perform public.assert_seat_available(r.id, array['clinico']::public.user_role[]);
      raise notice '% → SÍ cabe un clínico más', r.name;
    exception when others then
      raise notice '% → NO cabe un clínico más (%)', r.name, sqlerrm;
    end;
    begin
      perform public.assert_seat_available(r.id, array['admin']::public.user_role[]);
      raise notice '% → SÍ cabe un administrativo más', r.name;
    exception when others then
      raise notice '% → NO cabe un administrativo más (%)', r.name, sqlerrm;
    end;
  end loop;
end $$;
```

### C. Qué derechos quedaron, centro por centro

```sql
select o.name, e.kind, e.key, e.status, e.quantity, e.source, e.current_period_end
from public.organizations o
join public.org_entitlements e on e.organization_id = o.id
where o.is_active
order by o.name, e.kind, e.key;
```

Comparar contra **P1/P2** (la fotografía de producción):

- `module:clinico` — en todos.
- `module:insumos` / `module:comercial` — exactamente en los que P2 (o el default por
  `center_type`) decía que estaban encendidos.
- `module:admin` — exactamente en los que P1 decía `miembros_activos > 1`. **Riesgo 2:** cada
  uno de estos es un módulo de $1,200/mes regalado. Decisión consciente, escrita abajo.
- `seat:protocolo` — solo donde `premium_protocolo_kura` era verdadero, con cantidad igual a
  `perfiles_premium` de P1. **Riesgo 3:** si sale cero o no aparece, Kura+ se apaga.

### D. Coherencia entre lo encendido y lo contratado

Desde 0115, encender un módulo sin derecho lanza excepción. Verificar que no quedó ninguna fila
encendida sin respaldo:

```sql
select ms.organization_id, ms.module_key, ms.enabled
from public.module_settings ms
where ms.site_id is null and ms.profile_id is null and ms.enabled
  and not exists (
    select 1 from public.org_entitlements e
    where e.organization_id = ms.organization_id
      and e.kind = 'module' and e.key = ms.module_key and e.status = 'active');
-- Esperado: cero filas.
```

### E. Plan gratuito retirado (0126)

`0126` revoca `create_organization_with_admin` y elimina el trigger del tope de 5 pacientes.
Ya está verificado en el código: la app solo llama a `create_trial_organization`
(`lib/services/data_repository.dart:1331`), y `admin-create-user` no invoca la función
retirada. Confirmarlo en la copia:

```sql
select tgname from pg_trigger where tgname = 'trg_zz_free_plan_patient_cap';
-- Esperado: cero filas.
```

---

## 8. El veredicto

El ensayo no termina con las consultas en verde. Termina con esta tabla llena, una fila por
centro activo, comparando **la copia** contra **el contrato**:

| Centro | Módulos hoy (contrato) | Módulos en la copia | Asientos clínicos contratados | Tope en la copia | Demanda en la copia | Kura+ contratado | Kura+ en la copia | ¿Coincide? |
|---|---|---|---|---|---|---|---|---|
| | | | | | | | | |

Y con tres decisiones escritas:

1. **`module:admin` regalado** — ¿a cuántos centros, y se queda así? (Sí / se quita / se
   convierte en cortesía con fecha.)
2. **Holgura de asientos** — ¿el tope queda pegado al uso actual, o se le suma margen?
3. **Kura+** — si salió en cero, ¿de dónde se toma la cantidad real?

---

## 9. Después del ensayo

- Si todo queda verde y las tres decisiones están tomadas → fusionar Fase 2 a `main` con plan
  de reversa.
- Si algo salió rojo → se corrige `0114` (o se agrega una migración correctiva **después** de
  0131; no se reescribe una migración ya aplicada en staging) y se repite el ensayo desde una
  copia limpia.
- **Borrar el proyecto desechable.** Tiene datos reales de pacientes.

### Plan de reversa para el corte real

Las 24 migraciones son casi todas aditivas. Lo que no se deshace solo:

- `0126` elimina el trigger del tope de pacientes y revoca una función. Reversible, pero hay
  que tener el SQL escrito **antes** del corte, no improvisado.
- `0114` escribe derechos. Su reversa es
  `delete from public.org_entitlements where source = 'master' and created_at >= '<hora del corte>'`,
  que solo es segura si nadie compró nada en el intervalo.
- El respaldo previo al corte es la reversa real. Tomarlo inmediatamente antes y anotar la hora.
