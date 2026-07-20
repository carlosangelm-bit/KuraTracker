# Integración Acuity Scheduling — despliegue

Andamiaje para que el profesional (y el admin) vean/gestionen su agenda de
Acuity desde KuraTracker. **El código está listo; estos pasos los hace quien
tenga acceso a Supabase + la cuenta de Acuity** (no se puede desplegar ni
probar sin credenciales reales).

## Arquitectura

```
Flutter ──► Edge Function acuity-proxy ──► Acuity API        (leer/crear/editar)
Acuity  ──► Edge Function acuity-webhook ─► tabla appointments (sincroniza)
Flutter ◄── Supabase Realtime (tabla appointments)           (tiempo real)
```

La app NUNCA habla con Acuity directo ni guarda credenciales: todo pasa por las
Edge Functions. La app solo LEE `appointments` (RLS) y crea/edita vía el proxy.

## 1. Migración

Aplica `supabase/migrations/0016_acuity_agenda.sql` (tabla `appointments` + RLS
+ columna `staff.acuity_calendar_id`):

```
supabase db push        # o supabase migration up
```

## 2. Credenciales de Acuity (Basic Auth para empezar)

En Acuity → Integrations copia **User ID** y **API Key** (requiere plan con
acceso a API). Guárdalas como secrets de Supabase:

```
supabase secrets set ACUITY_USER_ID=xxxxx ACUITY_API_KEY=xxxxxxxx
```

> Multi-cuenta a futuro: si cada clínica conecta su propia cuenta, se migra a
> OAuth2 (registro en el Developer Hub de Acuity). Por ahora, una cuenta.

## 3. Desplegar las Edge Functions

```
supabase functions deploy acuity-proxy
supabase functions deploy acuity-webhook --no-verify-jwt   # Acuity no manda JWT
```

`SUPABASE_URL` y `SUPABASE_SERVICE_ROLE_KEY` los inyecta Supabase solo.

## 4. Registrar los webhooks en Acuity

Una vez por evento, apuntando al webhook desplegado
(`https://<PROYECTO>.supabase.co/functions/v1/acuity-webhook`):

```
POST /webhooks {"event":"appointment.scheduled",   "target":"<URL>"}
POST /webhooks {"event":"appointment.rescheduled", "target":"<URL>"}
POST /webhooks {"event":"appointment.canceled",    "target":"<URL>"}
POST /webhooks {"event":"appointment.changed",     "target":"<URL>"}
```

(Se pueden crear vía el mismo proxy, o en Acuity → Integrations.)

## 5. Mapear cada Kurador a su calendario de Acuity

Para que "cada profesional vea SU agenda", cada `staff` debe tener su
`acuity_calendar_id`. Dos opciones:

### 5a. Automático por EMAIL (recomendado — no necesitas los IDs)

`acuity-sync-calendars` lee `GET /calendars` (cada calendario trae su email) y
setea `acuity_calendar_id` casando el email del calendario con el email del
perfil del Kurador en KuraTracker:

```
supabase functions deploy acuity-sync-calendars
curl -X POST 'https://<PROJECT_REF>.supabase.co/functions/v1/acuity-sync-calendars' \
     -H "Authorization: Bearer <SERVICE_ROLE_KEY>"
# -> {"matched":[...], "unmatched":[...]}
```

Requisito: el email del calendario en Acuity debe coincidir con el email del
perfil del Kurador (profiles.email). Reejecuta esta función cada que agregues
calendarios o personal.

### 5a-bis. Crear los usuarios faltantes (con cuenta de acceso)

Para los proveedores de Acuity que aún NO existan en KuraTracker, la misma
función puede crearlos: invita por email (Supabase Auth), crea el perfil (rol
`clinico`) y el registro de personal, con su `acuity_calendar_id`, en el centro
indicado. Necesitas el `organizationId` del centro (`select id,name from
organizations;`):

```
curl -X POST 'https://<PROJECT_REF>.supabase.co/functions/v1/acuity-sync-calendars' \
     -H "Authorization: Bearer <SERVICE_ROLE_KEY>" \
     -H "Content-Type: application/json" \
     -d '{"createMissing": true, "organizationId": "<UUID_DE_KURA+>"}'
# -> {"matched":[...], "created":[...], "skipped":[...]}
```

Los creados reciben un correo de invitación para fijar su contraseña y así
poder entrar a ver SU agenda. Es idempotente: quien ya exista se mapea, no se
duplica.

### Multi-organización (estructura a futuro)

Hoy hay UNA cuenta de Acuity (secrets globales) y todo se crea en el centro que
pases en `organizationId`. Para que OTRAS organizaciones conecten SU propia
cuenta de Acuity:
1. Tabla `organization_acuity_credentials` (organization_id → user_id/api_key
   o token OAuth2).
2. Que `acuity-proxy` / `acuity-webhook` / esta sync elijan las credenciales
   según la organización (en vez de los secrets globales).
3. Migrar de Basic Auth a **OAuth2** (registro en el Developer Hub de Acuity)
   para conectar cuentas de terceros sin compartir API keys.
La función ya recibe `organizationId` como parámetro para no reescribirla
cuando se agregue esto.

### 5b. Manual (si algún email no coincide)

```sql
update public.staff set acuity_calendar_id = <ID_ACUITY>
where id = '<staff_uuid>';
```

El webhook usa ese mapeo para resolver `staff_id`/`organization_id` de cada
cita. Citas de calendarios no mapeados quedan con `staff_id = null`.

## 6. Backfill inicial (citas ya existentes)

El webhook solo refleja cambios NUEVOS. Para traer las citas que ya existían en
Acuity, usa la función `acuity-backfill` (escribe en PRODUCCIÓN vía service role;
no toca el modo demo):

```
supabase functions deploy acuity-backfill
# ejecutar UNA vez (autenticado con la service role key):
curl -X POST 'https://<PROJECT_REF>.supabase.co/functions/v1/acuity-backfill' \
     -H "Authorization: Bearer <SERVICE_ROLE_KEY>"
# -> {"imported": N}
```

Hazlo DESPUÉS de mapear los `acuity_calendar_id` (paso 5) para que las citas
queden con su `staff_id`/`organization_id`. Si tienes >1000 citas habría que
paginar por rango de fechas (ver comentario en la función).

## Verificación

- `supabase functions logs acuity-webhook` al crear una cita de prueba en Acuity.
- La fila debe aparecer en `appointments`; la app la ve por Realtime.
- En KuraTracker: pestaña **Agenda** (clínico ve sus citas; admin las del centro).

## Notas

- Rate limit Acuity: 10 req/s. El proxy reintenta ante 429 (backoff simple).
- Zona horaria: Acuity usa la del calendario/negocio; `datetime` se guarda como
  `timestamptz`. La app formatea en local.
- En **modo demo local** (sin Supabase) la Agenda muestra un estado
  "no disponible en demo" (no hay Edge Functions).

---

# Gestión de usuarios y roles (admin-create-user)

Permite que el **admin de un centro** y el **master** creen usuarios CON login
y cambien roles desde la app (pestaña "Usuarios" en Administración / Plataforma),
sin tocar SQL a mano.

## Qué se puede hacer sin backend nuevo
Cambiar rol (admin ↔ personal sanitario) y activar/desactivar usuarios YA
funciona solo con RLS: se hace desde el cliente vía `profiles`. Requisito para
el **master**: aplicar la migración `0017_master_manage_profiles.sql`, que
agrega `or is_master()` a las policies de `profiles` (el admin de centro ya
podía; ver el hallazgo documentado en esa migración).

```
supabase db push        # aplica 0017 (además de 0016 si faltara)
```

## Qué necesita la Edge Function
**Crear** una cuenta de acceso nueva requiere service role (Auth
`admin.createUser`), que no puede vivir en el cliente. La función
`admin-create-user`:
- Verifica (por el JWT) que el llamador sea **admin** o **master**.
- **admin**: crea SOLO en su propio centro. **master**: en el centro que indique
  (`organizationId`). Rol permitido: `admin` | `clinico` (nunca `master`).
- Crea la cuenta Auth (el trigger `handle_new_auth_user` crea el `profile` desde
  `user_metadata`), refuerza el perfil y —para clínicos— crea el `staff`.
- Como el **SMTP puede no estar configurado**, crea con `email_confirm=true` y
  **devuelve una contraseña temporal** para que el admin la comparta; la app la
  muestra en un diálogo. Con SMTP, el usuario puede usar "olvidé mi contraseña".

```
supabase functions deploy admin-create-user     # con verify_jwt (default)
```

No requiere secrets propios (usa `SUPABASE_URL` / `SUPABASE_SERVICE_ROLE_KEY`,
inyectados por Supabase). Reutiliza el mismo patrón JWT que `acuity-proxy`.

## Verificación
- Entra como admin/master → pestaña **Usuarios** → "Nuevo usuario".
- Debe aparecer en la lista y (sin SMTP) mostrarse una contraseña temporal.
- Cambiar rol y activar/desactivar deben reflejarse de inmediato.
