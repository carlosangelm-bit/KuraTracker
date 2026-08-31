# KuraTracker — Licencias y premium a nivel centro: un hueco de ingresos abierto

**Fecha:** 31-ago-2026 · **Base:** `main` en `22b74c1`
**Origen:** el modelo comercial descrito por Carlos — el contrato es con el CENTRO; el
centro tiene licencias para sus clínicos y admins; las funcionalidades premium del centro
son accesibles a quienes el centro decida, y **no se compran por usuario**.

---

## 0. Corrección a lo que dije antes

Afirmé que "no existe modelo de licencia". **Inexacto.** El nivel de centro sí existe y
está en el grano correcto:

- `organizations.premium_insumos` (`0047`)
- `organizations.premium_protocolo_kura` (`0049`)

Lo que no existe es el **conteo de licencias** y el **estado de la suscripción**. Y hay un
defecto en cómo se resuelve el premium, que es el tema de §1.

---

## 1. El hueco: el premium se resuelve con OR, no con AND

`lib/core/providers/session_provider.dart:256-262`

```dart
final kuraProtocolEnabledProvider = Provider<bool>((ref) {
  final user = ref.watch(sessionProvider).user;
  if (user == null) return false;
  if (user.premiumEnabled) return true;          // ← basta la bandera del USUARIO
  final repo = ref.watch(dataRepositoryProvider).valueOrNull;
  return repo?.premiumProtocoloKuraFor(user.organizationId) ?? false;
});
```

Es decir: `premium_efectivo = profiles.premium_enabled **OR** organizations.premium_protocolo_kura`.

Y quién puede prender la bandera del usuario:

- **App:** `setUserPremium` (`data_repository.dart:390`) desde el panel de Administración
  del centro (`admin_home_screen.dart:516`).
- **Base:** el trigger `prevent_profile_privilege_escalation` (`0006`, extendido en `0096`)
  bloquea `premium_enabled` **solo para no-admins**:
  ```sql
  if auth.uid() is not null and not public.is_admin() then
    if ... or new.premium_enabled is distinct from old.premium_enabled then
      raise exception 'No autorizado: solo un administrador puede modificar ...';
  ```
  Un **admin sí puede**. Y la policy `profiles_update_own_or_admin` (`0003:38`) le permite
  tocar las filas de su centro.

### La consecuencia, en una frase

> **El administrador de un centro cliente puede otorgar "Protocolo Kura+" a su propio
> personal, uno por uno, sin que el centro haya comprado el add-on.**

No requiere nada raro: es un switch en la pantalla de Administración que ese admin ya tiene.
Hoy no hay daño porque el único centro con gente real es Kura+ y el admin eres tú. **Se
activa el día que exista el primer centro cliente**, que es justo lo que estamos preparando.

`premium_insumos` (`0047`) **no** tiene este problema: es solo de centro, sin contraparte por
usuario. El defecto está únicamente en `premium_protocolo_kura`.

---

## 2. El arreglo

Semántica correcta, según el modelo descrito:

```
premium_efectivo(usuario) = organizations.premium_protocolo_kura   -- el centro lo compró
                        AND profiles.premium_enabled                -- el centro se lo dio a esta persona
```

El add-on es la **habilitación** (la compra); la bandera por usuario es el **otorgamiento**
(a quién se lo da el centro). Eso es exactamente "accesibles para todos los que ellos
decidan, no por usuario": el centro paga una vez y reparte internamente.

### Detalle que evita un incidente

Hoy `profiles.premium_enabled` es `default false`. Si se cambia OR → AND sin más, **todo
centro que tenga el add-on pero cuyos miembros no tengan la bandera individual pierde el
premium de golpe.** El cambio va acompañado de un backfill:

```sql
-- Migración: al pasar a AND, otorgar la bandera individual a todos los miembros
-- de centros que YA tienen el add-on, para que nadie pierda acceso.
update public.profiles p
set premium_enabled = true
where exists (
  select 1 from public.organizations o
  where o.id = p.organization_id
    and o.premium_protocolo_kura = true
);
```

### Y un candado que conviene poner

`setUserPremium` debería rechazar el otorgamiento si el centro no tiene el add-on — con
mensaje claro ("este centro no tiene Protocolo Kura+ contratado"), no fallando en silencio.
Idealmente también en la base, con un trigger, para que no dependa del cliente.

---

## 3. Lo que falta: contar licencias

`organizations` tiene 13 columnas de configuración añadidas por migraciones sucesivas
(tipo, branding, agenda, módulos, inventario, escalas, terminal de pago…) y **ninguna de
capacidad contratada**. No hay dónde decir "este centro contrató 5 licencias".

Falta:

1. **Capacidad** en `organizations` (número de licencias contratadas, o un plan que la
   implique).
2. **Estado de la suscripción** — vigente / vencida / suspendida, y qué pasa cuando vence.
   Hoy los add-ons premium son booleanos sin fecha ni estado: una vez prendidos, quedan
   prendidos.
3. **Verificación al dar de alta un usuario**: `createUserWithLogin` y `admin-create-user`
   deben rechazar el alta si no hay licencia disponible.

---

## 4. Dos decisiones comerciales que hay que tomar (no son de código)

### (a) ¿La licencia es por PERSONA o por ROL?

El ejemplo que diste: Eva = `{admin}`, María = `{admin, clinico}`, Juan Carlos = `{clinico}`.
**¿María consume una licencia o dos?**

Mi lectura de lo que describiste —el multirol como ajuste a la necesidad operativa— es
**una persona, una licencia**. Y creo que es lo correcto también por una razón práctica: si
se cobra por rol, el incentivo del centro es crear dos cuentas para María en vez de una
multirol, y eso ensucia el expediente (dos autores para la misma persona), rompe la
auditoría y anula el punto del trabajo de roles que acabamos de hacer.

Conviene dejarlo escrito antes de construir el conteo, porque la fórmula de capacidad
depende de ello.

### (b) ¿Los cuidadores consumen licencia?

El rol `cuidador` es restringido (solo lectura de sus pacientes asignados + sus tareas) y
típicamente es un familiar del paciente, no personal del centro. Supongo que **no** consume
licencia, pero es una línea que hay que fijar: si el centro puede dar de alta cuidadores sin
límite, es un vector de crecimiento de la base de usuarios sin ingreso asociado.

---

## 5. Orden sugerido

1. **§2 — OR → AND, con el backfill y el candado en `setUserPremium`.** Es el hueco de
   ingresos y es acotado: un provider, una migración de backfill, una validación.
2. **§4 — las dos decisiones comerciales.** Bloquean el diseño del conteo.
3. **§3 — capacidad y estado de suscripción**, y la verificación al alta.

Los tres van **antes** del primer centro cliente, no después: retro-aplicar un límite de
licencias a un centro que ya dio de alta a 12 personas es una conversación comercial
incómoda que se evita fijando la regla desde el alta.
