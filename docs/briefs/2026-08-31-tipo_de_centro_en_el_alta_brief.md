# KuraTracker — Tipo de centro en el alta (pendiente #1 de centros externos)

**Fecha:** 31-ago-2026 · **Base:** `main` en `fa2107f`
**Para:** agente de desarrollo. Cambio chico, sin migración obligatoria.

---

## 0. Corrección a cómo lo describí antes

Dije que un hospital mal tipificado "nace mal y queda mal". **Eso es inexacto y lo verifiqué.**
La resolución de módulos y de RLS es **en vivo**, no sembrada al crear:

- `isModuleEnabled` (`data_repository.dart:689`) lee `centerTypeFor(organizationId)` en cada
  consulta.
- `has_hospital_org_access` (`0045:37-51`) evalúa `o.center_type = 'hospital'` en cada
  política.

Así que **corregir el tipo después con `setCenterType` sí arregla todo retroactivamente.** No
hay corrupción permanente.

## 1. Entonces por qué sigue importando, y bastante

El problema no es que sea irreversible: es que **los síntomas no se parecen a una mala
configuración, se parecen a defectos del producto.** Mientras un hospital esté tipificado como
`clinica_heridas`:

1. **Los módulos hospitalarios no aparecen** (prevención, escalas). Se lee como "la
   plataforma no tiene eso".
2. **Y no se pueden encender.** `isModuleEnabled:692` —
   `if (!module.availableFor(centerType)) return false;` — apaga el módulo *siempre*, sin
   importar los ajustes. Es decir: el master entra a configuración, prende el interruptor,
   y **no pasa nada, sin explicación**. Ese es el tipo de falla que quema un día de soporte.
3. **El personal de enfermería no puede escribir nada.** Las 23 políticas de escritura
   hospitalaria exigen `has_hospital_org_access`, que exige `center_type = 'hospital'`. En un
   hospital, enfermería es la mayor parte del personal que reporta.

Nadie va a diagnosticar eso como "el tipo de centro está mal". Van a reportar que la app no
funciona.

## 2. El cambio

**`createOrganization` recibe el tipo, obligatorio:**

```dart
// data_repository.dart:730 — hoy: createOrganization(String name)
Future<Organization> createOrganization(String name, CenterType centerType) async {
  final data = {
    'id': _uuid.v4(),
    'name': name,
    'center_type': centerType.dbValue,   // ← explícito, no el default del 0040
    'is_active': true,
  };
  ...
}
```

**El diálogo de alta pide el tipo** (`platform_home_screen.dart`, el `AlertDialog` "Nuevo
centro (organización)", `_submit` en la línea ~940). Tres opciones desde
`CenterType.values` — `clinicaHeridas`, `hospital`, `cuidadores` — como radio buttons o
dropdown, **sin valor preseleccionado**, para que elegir sea un acto y no un descuido.

Con una línea de ayuda por opción, porque quien crea el centro decide su superficie de
permisos:

- **Clínica de heridas** — consulta, seguimiento, insumos. El caso más común.
- **Hospital** — activa prevención, escalas y el acceso centrado en el centro: cualquier
  profesional de turno ve a todos los pacientes del centro, y enfermería puede reportar.
- **Cuidadores** — centro de monitoreo domiciliario.

**Validación:** no permitir enviar sin tipo. Mismo trato que el nombre.

**Sin migración obligatoria.** La columna ya existe (`0040:27`) con `default 'clinica_heridas'`.
**No quites el default** — hay otras rutas de inserción que dependen de él (el RPC
`create_organization_with_admin`, y sembrados). Lo que cambia es que la app deje de apoyarse
en él.

## 3. La red de seguridad, que cuesta menos que el bug

En la lista de centros del área Plataforma, **mostrar el tipo de cada centro** como etiqueta
visible. Hoy hay que entrar a la configuración de cada uno para saberlo. Con la etiqueta, un
centro mal tipificado se ve de un vistazo en vez de descubrirse por un reporte de "no
funciona".

## 4. Aprovecha el mismo formulario para el pendiente #3

El pendiente #3 (`is_test`) incluye `organizations.is_test`. **Es un campo en este mismo
diálogo.** Hacerlo aquí cuesta casi nada y evita volver a abrir la pantalla:

```sql
-- Migración: marcar los centros de andamio.
alter table public.organizations
  add column if not exists is_test boolean not null default false;
```

Más la casilla "Centro de pruebas" en el diálogo, y la etiqueta correspondiente en el listado
(junto a la del tipo, §3).

**No** marques los centros existentes tú: deja la consulta y que Carlos decida.

```sql
select id, name, center_type, is_active from public.organizations order by name;
-- 'Centro hospitalario de prueba' y 'Cuidador de prueba' son candidatos evidentes,
-- pero la decisión es de Carlos.
```

`profiles.is_test` y `patients.is_test` —y los filtros de KPI— van aparte, en la ronda del
pendiente #3 completo.

## 5. Verificación

1. Crear un centro tipo `hospital` desde Plataforma y confirmar en la base:
   `select name, center_type from public.organizations where name = '<nuevo>';`
   → `hospital`, no `clinica_heridas`.
2. Con una cuenta de enfermería con membresía en ese centro, confirmar que puede registrar
   una valoración de riesgo. Es la prueba de que las políticas hospitalarias reconocen el
   centro.
3. Confirmar que el diálogo no deja crear sin tipo seleccionado.
