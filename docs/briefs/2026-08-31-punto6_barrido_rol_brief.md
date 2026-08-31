# KuraTracker — Punto 6 es un barrido, no una pantalla

**Fecha:** 31-ago-2026 · **Base:** `main` en `ce4d1a2` (Fase B ya fusionada)
**Para:** agente de desarrollo — preparación mientras cierra el CI

---

## El problema

La Fase B hizo que el conjunto gobierne **en la base de datos**: `has_role()` reemplazó
a `current_user_role()` en ~23 políticas, y `app_user.dart` ya expone `hasRole`,
`isAdmin`, `isNurse`, `canDiagnose` leyendo `effectiveRoles`.

Pero **la app todavía le pregunta al espejo escalar en 52 lugares**:

```
$ grep -rn "\.role == AppRole\.\|\.role != AppRole\." lib/ --include=*.dart | wc -l
52
```

Desglose por rol comparado: `admin` 37 · `master` 12 · `cuidador` 7 · `clinico` 6 ·
`enfermeria` 4.

`role` es el espejo que produce `primary_role(roles)`, y `primary_role` es **por
precedencia**: `master > admin > clinico > enfermeria > cuidador`. Un escalar no puede
expresar dos roles. Por lo tanto:

| conjunto | espejo `role` | qué se rompe |
|---|---|---|
| `{admin, clinico}` | `admin` | **toda comparación `role == clinico` da falso** |
| `{master, admin}` | `master` | **toda comparación `role == admin` da falso** |
| `{clinico, enfermeria}` | `clinico` | las de `enfermeria` dan falso |

Este es el gemelo, del lado de la app, de la MINA 2 que ya resolviste en la base.

## El caso vivo, hoy

`lib/features/risk/risk_board_screen.dart:119`

```dart
(user?.role == AppRole.clinico && user?.staffId != null)
```

Las cuatro cuentas de Kura+ tienen `{admin, clinico}` → espejo `admin` → **falso**.
La base (post-`0098`, vía `has_role('clinico')`) dice que sí; la pantalla dice que no.

Ese es el peor modo de falla posible: **divergencia silenciosa**. No hay excepción, no
hay log, no hay error. El usuario ve una función que "no sirve" y nada explica por qué.
No es una regresión de la Fase B —antes del `0096` el comportamiento era el mismo— pero
sí es la razón por la que **el multi-rol no se va a notar hasta que se haga el barrido**.

## Inconsistencia concreta en el candado de compra

```
lib/features/insumos/purchase_guard.dart:11   user?.role == AppRole.admin || (user?.isMaster ?? false)
lib/features/insumos/inventario_screen.dart:351   final isAdmin = user?.role == AppRole.admin;
lib/features/insumos/inventario_screen.dart:563   final isAdmin = ... user?.role == AppRole.admin;
```

`purchase_guard` rescata al master con el `|| isMaster`; las dos de `inventario_screen`
no. Un master no puede editar precios ni alcance de inventario, pero sí comprar. Es
inconsistente hoy y desaparece solo con el cambio a `isAdmin`.

---

## Qué hacer en el punto 6

**Es un barrido de 52 sitios, no una pantalla de checkboxes.** Sugerido, en este orden:

1. **Sustitución mecánica** de los predicados de capacidad:
   - `user.role == AppRole.admin` → `user.isAdmin`
   - `user.role == AppRole.clinico` → `user.canDiagnose` (o `hasRole(AppRole.clinico)`
     cuando lo que se pregunta es el rol, no la capacidad de diagnosticar)
   - `user.role == AppRole.enfermeria` → `user.isNurse`
   - `user.role == AppRole.master` → `user.isMaster`
2. **Revisar a mano, no sustituir, los que hablan de OTRO usuario** (`u.role != ...` en
   `admin_home_screen`): esos son la UI de gestión de usuarios y se reescriben completos
   como parte del multi-rol. Ahí `u.roles` es lo que hay que mostrar y editar.
3. **Dejar en paz** los que sí quieren el rol primario para *mostrarlo* como etiqueta
   (`login_screen.dart:307-309`, listados): mostrar un rol representativo está bien.
   El criterio: **si decide un permiso → conjunto; si solo pinta texto → espejo.**
4. **Los 7 sitios `staffId == null && role == AppRole.admin`** son los `ensureAdminStaffId`
   perezosos. Cambian a `isAdmin` igual, pero verifica que sigan disparando: si dejan de
   hacerlo, un admin sin fila de `staff` vuelve a no poder crear consultas
   (`consultations.staff_id` es NOT NULL).

**Criterio de aceptación del punto 6:** no debe quedar ninguna comparación
`\.role == AppRole\.` que decida un permiso. El `grep` de arriba es la prueba; lo que
sobreviva debe ser solo presentación, y con comentario que lo diga.

## Orden sugerido

El barrido (punto 6) **antes** de la UI multi-rol. Si primero se da la capacidad de
asignar dos roles y la app sigue leyendo el escalar, el primer usuario multi-rol que se
cree va a exhibir exactamente la divergencia de arriba, y el bug se va a atribuir al
formulario nuevo en vez de a los 52 sitios viejos.
