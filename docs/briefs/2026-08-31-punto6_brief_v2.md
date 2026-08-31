# KuraTracker — Punto 6: multi-rol en la app. **Corrige el brief anterior.**

**Fecha:** 31-ago-2026 · **Base:** `main` en `530f07a` (puntos 5, 7 y Fases A/B en prod)
**Reemplaza** a `KuraTracker_punto6_barrido_rol_brief.md`.

---

## 0. Lo que estaba mal en mi brief anterior

Recomendé una "sustitución mecánica": `role == AppRole.x` → `hasRole(x)` / los getters.
**Ese cambio, aplicado tal cual, introduce regresiones.** Lo verifiqué leyendo los sitios
uno por uno, que es lo que debí hacer antes de dar la recomendación.

La razón es que hay dos clases de predicado y se comportan al revés:

| clase | forma | qué pasa con un conjunto |
|---|---|---|
| **capacidad positiva** | "puede X *porque tiene* el rol R" | los roles **suman**: `hasRole(R)` es correcto |
| **restricción negativa** | "*no* puede X porque *solo* es R" | `hasRole(R)` hace que **la restricción gane sobre la concesión** — mal |

Un espejo escalar con precedencia (`master > admin > clinico > enfermeria > cuidador`)
implementa **correctamente** la segunda clase, por accidente afortunado: `role == 'enfermeria'`
es verdadero solo si la persona no tiene nada más amplio. Cambiarlo a
`hasRole('enfermeria')` rompe al usuario `{clinico, enfermeria}`.

**Regla corregida:** *positivo → conjunto. Negativo → conjunto **más** la ausencia de todo
rol que conceda lo que la restricción quita.* Nunca `hasRole` a secas en un predicado
negativo.

### Los dos casos concretos donde mi consejo habría causado el bug

**(a) `app_router.dart:120` — `isNurse`**
```dart
final isNurse = session.user?.role == AppRole.enfermeria;
...
if (loggedIn && isNurse) { /* bloquea /patients/new, /edit, /consultation/new ... */ }
```
Es una restricción. Con `hasRole(enfermeria)`, un `{clinico, enfermeria}` quedaría sin
poder crear consultas **teniendo el rol clínico**. Forma correcta:
```dart
final isNurse = (u?.hasRole(AppRole.enfermeria) ?? false)
    && !(u?.canDiagnose ?? false) && !(u?.isAdmin ?? false) && !(u?.isMaster ?? false);
```

**(b) `risk_board_screen.dart:119` — el que yo declaré "bug vivo". No lo es.**
```dart
// Base de pacientes: clínico ve los suyos; los demás (admin/enfermería) ven
// los del CENTRO ACTIVO.
(user?.role == AppRole.clinico && user?.staffId != null)
```
El comentario dice la intención: **es alcance por rol primario**, no una capacidad. Para
`{admin, clinico}` el comportamiento de hoy —ver todo el centro— es **el deseado**.
Migrarlo a `canDiagnose` le *reduciría* a Carlos la vista de todo el centro a solo sus
pacientes asignados. Sería una regresión, no un arreglo. Forma correcta si se toca:
```dart
final soloClinico = (user?.hasRole(AppRole.clinico) ?? false)
    && !(user?.isAdmin ?? false) && !(user?.isMaster ?? false);
```

Me equivoqué al llamarlo bug: leí la comparación sin leer el comentario de arriba.

---

## 1. Hallazgo nuevo: **hay una TERCERA vía legacy, y sigue abierta**

El punto 7 cerró las dos vías de **alta**. Pero el **cambio de rol** sigue escribiendo el
escalar:

`lib/services/data_repository.dart:400`
```dart
Future<void> setUserRole(String userId, AppRole role) async {
  await _store.updateRow(Collections.profiles, userId, {'role': role.dbValue});
}
```

Rama UPDATE del trigger: `new.role is distinct from old.role` → `new.roles := {admin, clinico}`.

**Consecuencia:** hoy, en producción, usar el menú "cambiar rol → Administrador" del panel
de Administración le otorga `clinico` a esa persona, sin que nadie lo pida. Es exactamente
el atajo que el punto 7 cerró, por una puerta que no revisamos.

Se llama desde `admin_home_screen.dart:538-570` (el menú de roles).

**Arreglo (parte del punto 6, no puede esperar a después de la UI):** `setUserRole` pasa a
recibir un conjunto y escribir `roles`:
```dart
Future<void> setUserRoles(String userId, Set<AppRole> roles) async {
  await _store.updateRow(Collections.profiles, userId,
      {'roles': roles.map((r) => r.dbValue).toList()});
}
```
El trigger deriva el espejo. Validar del lado del cliente lo mismo que valida la Edge
Function: no vacío, sin `master`, `cuidador` exclusivo. (La RLS + el trigger
`prevent_profile_privilege_escalation` ya cubren `roles` desde el `0096`, así que la base
rechaza la escalada aunque el cliente falle.)

---

## 2. Los 16 sitios, clasificados de verdad

**A. Capacidad positiva → `hasRole` / getters (migración directa)**
| sitio | cambio |
|---|---|
| `features/tour/tour_scope.dart:52` | `hasRole(clinico) \|\| hasRole(admin)` |
| `features/patients/patient_detail_screen.dart:993` | `u.hasRole(cuidador)` (filtro de cuidadores asignables) |
| `services/data_repository.dart:482,485` | recibe conjunto: crea `staff` si contiene `clinico` o `enfermeria`; `roleTitle` derivado del conjunto |

**B. Restricción negativa → conjunto + ausencia de rol más amplio (ver §0)**
| sitio | nota |
|---|---|
| `core/router/app_router.dart:120` (`isNurse`) | bloqueo de rutas de escritura |
| `core/router/app_router.dart:116` (`isCaregiver`) | redirect que encierra en `/caregiver` |
| `core/router/app_shell.dart:49` | nav reducida del cuidador |
| `features/admin/admin_home_screen.dart:274,476` | "todos menos cuidador" |

Los tres de `cuidador` son hoy equivalentes en cualquier forma, porque el punto 7 ya
impone exclusividad en el servidor. Escribirlos explícitos igual, para que la próxima
persona no tenga que redescubrir por qué eran seguros.

**C. Alcance por rol primario → NO migrar sin decidir el producto**
| sitio | decisión |
|---|---|
| `features/risk/risk_board_screen.dart:119` | ¿un admin+clínico ve todo el centro (hoy) o solo sus pacientes? Si se deja como está, poner un comentario que diga que el espejo es intencional |

**D. Estado del formulario / UI de gestión → los reescribe la pantalla nueva**
`admin_home_screen.dart:558,562,566,570` (menú "cambiar rol a X") y `:638,678,791`
(`_role` local del formulario de alta). No son bugs; desaparecen con la UI multi-rol.

---

## 3. La pantalla

1. **Alta de usuario**: el selector único pasa a **casillas** sobre
   `{admin, clinico, enfermeria, cuidador}`. `master` nunca aparece.
2. **Validación en cliente, igual a la del servidor**: conjunto no vacío; marcar
   `cuidador` limpia y deshabilita las demás; sin `master`.
3. `primarySiteId` y `cedulaProfesional` se piden cuando el conjunto contiene `clinico`
   (hoy dependen de `_role == clinico`).
4. Manda `roles: [...]` a `admin-create-user` (ya lo acepta desde el punto 7). Deja de
   mandar `role`.
5. **Edición de roles de un usuario existente**: mismas casillas, guardando por
   `setUserRoles` (§1). Reemplaza el menú de "cambiar rol".
6. Mostrar el conjunto en el listado de usuarios, no solo el primario.

### Criterio de aceptación

- Crear un usuario con `{admin, clinico}` desde la app y verificar en la base:
  `roles = {admin,clinico}`, `role = 'admin'`.
- Cambiar un `{clinico}` a `{admin}` por la pantalla de edición y verificar que **no**
  aparece `clinico`. (Hoy aparece — es el hallazgo de §1.)
- Un usuario `{clinico, enfermeria}` puede crear una consulta. (Hoy también puede; la
  prueba es que **siga** pudiendo después del cambio — es la regresión de §0(a).)

---

## 4. Orden sugerido

1. **§1 primero** (`setUserRoles`): es un hueco abierto en producción hoy, y es media hora.
2. Grupo A (3 sitios).
3. Grupo B (4 sitios), con la forma explícita de §0.
4. La pantalla (§3), que se lleva el grupo D consigo.
5. Grupo C: decidir con Carlos antes de tocar.
6. Los 31 restantes de `admin`/`master`: higiene, otra ronda. Son confiables por
   precedencia salvo que alguien tenga `{master, admin}` a la vez.
