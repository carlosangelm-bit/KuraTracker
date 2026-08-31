# KuraTracker — Modelo de licencias por centro: especificación

**Fecha:** 31-ago-2026 · **Base:** `main` en `22b74c1`
**Para:** agente de desarrollo
**Decisiones de Carlos, ya tomadas:**
- El contrato es con el **centro**; el centro tiene licencias para su personal.
- **La licencia es por PERSONA.** Una licencia admite múltiples roles al mismo costo.
- **Los cuidadores NO consumen licencia.**
- Las funcionalidades premium se compran a nivel centro y el centro decide a quién dárselas.

---

## 1. La regla de consumo, implementable

Una licencia se consume por **persona, por centro** — no por persona globalmente. El
contrato es del centro, así que cada centro cuenta su propia gente.

| conjunto de roles en ese centro | consume |
|---|---|
| `{admin}` | 1 |
| `{clinico}` | 1 |
| `{admin, clinico}` | **1** (multirol al mismo costo) |
| `{enfermeria}` | 1 |
| `{cuidador}` | **0** |

Sobre `enfermeria`: Carlos habló de "clínicos y más admins" en el contexto de clínicas.
`enfermeria` solo aparece en centros tipo `hospital`, que son contratos a la medida donde el
conteo se negocia. Se cuenta como 1 por defecto —es personal del centro, no familiar del
paciente— y en un contrato hospitalario se ajusta ahí.

## 2. Los asientos se cuentan desde la MEMBRESÍA, no desde el perfil

Esto importa: `profiles` tiene **una** fila por persona y **un** centro activo. Una persona
con membresía en tres centros aparece una sola vez en `profiles`. Contar asientos desde ahí
daría 1 en lugar de 3.

**La fuente correcta es `user_center_memberships`.** Y eso significa que **este trabajo y el
de roles-por-centro son la misma migración**: la tabla necesita `roles` (para saber qué es la
persona en ese centro) y el conteo lo consulta. Ver
`KuraTracker_roles_por_centro_brief.md` §3 — hacerlos juntos, no en dos rondas.

```sql
-- Depende de user_center_memberships.roles (migración de roles-por-centro).
-- Mientras esa columna no exista, usar m.role <> 'cuidador'.
create or replace function public.consumed_seats(p_org uuid)
returns integer language sql stable security definer
set search_path = public, pg_temp
as $$
  select count(*)::int
  from public.user_center_memberships m
  join public.profiles p on p.id = m.profile_id
  where m.organization_id = p_org
    and m.is_active
    and p.is_active
    and not coalesce(m.seat_exempt, false)
    and exists (select 1 from unnest(m.roles) r
                where r <> 'cuidador'::public.user_role);
$$;
```

## 3. El caso que ya existe en los datos: membresías que NO deben consumir

Hoy, en producción:

```
maria.amaya@kuramas.com   Centro hospitalario de prueba   admin
maria.amaya@kuramas.com   Cuidador de prueba              admin
carlosangelm@procomsa...  Kura+                           master
```

Dos situaciones que **no** deben consumir licencia del centro:

1. **`master`.** Es personal de plataforma de Kura+, no del centro. Nunca consume.
2. **Personal de Kura+ operando dentro de un centro cliente.** María con membresía
   administrativa en un centro cliente está **prestando servicio**, no ocupando un asiento
   que el cliente pagó. Cobrarle al cliente por la supervisión de Kura+ sería incorrecto.

De ahí el `seat_exempt boolean not null default false` en la membresía del §2. Se marca al
crear la membresía, desde la consola del master. **Decisión de diseño:** que sea explícito y
no inferido del rol — inferirlo del `master` cubre el caso 1 pero no el 2, y el 2 es el que
va a ocurrir en cada centro cliente.

## 4. El arreglo del premium (OR → AND)

Detalle completo en `KuraTracker_licencias_y_premium_centro.md`. Resumen ejecutable:

1. `session_provider.dart:256` — `kuraProtocolEnabledProvider` pasa de OR a AND:
   `organizations.premium_protocolo_kura` **AND** `profiles.premium_enabled`.
2. Migración de backfill (obligatoria, evita apagar el premium a quien ya lo tiene):
   ```sql
   update public.profiles p set premium_enabled = true
   where exists (select 1 from public.organizations o
                 where o.id = p.organization_id and o.premium_protocolo_kura = true);
   ```
3. `setUserPremium` rechaza el otorgamiento si el centro no tiene el add-on, con mensaje
   claro. Idealmente también un trigger en la base, para no depender del cliente.

Nota: `premium_insumos` (`0047`) ya es solo de centro y está correcto. No lo toques.

## 5. Capacidad y estado de contrato

`organizations` tiene 13 columnas de configuración y ninguna de contrato. Falta:

- `seats_contracted integer` — licencias contratadas (o un plan que lo implique).
- Estado del contrato: **vigente / vencido / suspendido**, con fecha. Hoy los add-ons
  premium son booleanos sin fecha: una vez prendidos, quedan prendidos para siempre.
- **Qué pasa al vencer.** Decisión de producto que hay que fijar antes de codificar:
  ¿se bloquea el acceso, se pasa a solo-lectura, o se conserva el acceso y solo se impide
  dar de alta gente nueva? Para un expediente clínico, **bloquear el acceso a datos de
  pacientes por un tema de cobranza es delicado** — mi recomendación es solo-lectura más
  bloqueo de altas, nunca cierre total.

## 6. Puntos de verificación (dónde se aplica el límite)

- `admin-create-user` (Edge Function): rechaza si `consumed_seats(org) >= seats_contracted`.
  Es el único lugar que corre con service role, así que es el candado real.
- `createUserWithLogin` (`data_repository.dart:415`): valida antes de llamar, para dar un
  mensaje decente en vez de un error de la función.
- Alta de membresía en un centro (cuando exista esa pantalla): mismo chequeo.
- **No** aplicar el límite a cuidadores ni a membresías `seat_exempt`.

## 7. Orden

1. **Premium OR → AND** (§4). Es el hueco de ingresos, y es independiente de todo lo demás.
2. **Roles-por-centro + `seat_exempt` + `consumed_seats`** (§2, §3). Una migración.
3. **`seats_contracted` + estado de contrato** (§5), con la decisión de qué pasa al vencer.
4. **Verificaciones** (§6).
