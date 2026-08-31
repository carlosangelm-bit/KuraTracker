# KuraTracker — Los tres caminos de alta, y qué le falta a cada uno

**Fecha:** 31-ago-2026 · **Base:** `main` en `22b74c1`
**Reemplaza el §1 de** `KuraTracker_listo_para_centros_externos.md`, que trataba el alta de
centro como una sola puerta. Son tres, con requisitos distintos.

---

## El modelo, según Carlos

| camino | tipo de centro | cómo entra |
|---|---|---|
| **A** | Hospitalario | **A la medida.** Sin registro de usuarios. El master crea toda la configuración |
| **B** | Clínica de heridas, **profesional único** | **Autoservicio.** Paga en el sitio web y empieza a usar la plataforma |
| **C** | Clínica de heridas, **centro con admin y varios profesionales** | Como el hospitalario: se configura desde el master |

Consecuencia inmediata: **dos de los tres caminos son consola de master, y uno es
autoservicio.** Retiro lo que dije antes sobre "la puerta de entrada está rota": el INSERT
de `createOrganization` es la herramienta del master, y para A y C es el camino correcto.
Lo que está mal es otra cosa.

---

## Caminos A y C — la consola del master: existe, necesita endurecerse

La pantalla de Plataforma ya crea centros y el master ya administra usuarios. Dos huecos:

### A.1 `center_type` no se fija al crear, y aquí sí está en la ruta crítica

`createOrganization` (`data_repository.dart:730`) inserta `{id, name, is_active}`. `0040:27`
define `center_type text not null default 'clinica_heridas'`.

Antes lo llamé "falla silenciosa en un caso borde". **No es borde: la configuración por
master es EL camino para A y C, así que este default se aplica en cada alta de hospital que
hagas.** Un hospital nace como clínica de heridas, y `has_hospital_org_access` exige
`center_type = 'hospital'` — las 23 políticas hospitalarias quedan inertes hasta que alguien
recuerde `setCenterType`. El centro funciona, con la superficie de permisos equivocada.

**Arreglo:** el tipo se elige **en el formulario de alta**, no después. Es un campo y un
parámetro.

### A.2 Falta la lista de lo que compone "toda la configuración"

Para A y C, la calidad del alta depende de que el master no olvide nada. Hoy eso vive en la
cabeza de quien configura. Vale escribir la **checklist de alta de centro** y, mejor,
convertirla en un asistente por pasos con estado de "configuración incompleta" visible:

- tipo de centro · sitios/sedes · módulos habilitados · catálogo de conceptos de nota ·
  escalas aplicables · nivel de inventario (propio vs. espejo) · membresías del personal de
  Kura+ que va a operar ahí · primer administrador del centro.

Sin ese estado explícito, un centro mal configurado es indistinguible de uno bien
configurado hasta que alguien tropieza.

### A.3 Los roles por centro pesan más en el camino A

En un hospital, la membresía administrativa produce hoy `clinico` fabricado por el atajo del
trigger, y post-Fase B eso es **escritura clínica a nivel de base de datos**. En un despliegue
hospitalario a la medida eso deja de ser una molestia de modelo y pasa a ser una pregunta de
cumplimiento: quién puede escribir en el expediente, y por qué. Detalle en
`KuraTracker_roles_por_centro_brief.md`.

---

## Camino B — autoservicio: **no existe ninguna de sus piezas**

Verificado en el repo:

| pieza | estado |
|---|---|
| Registro público (signup) | **No existe.** No hay `signUp` en `lib/features/auth/`; las rutas son solo `/login` y `/demo` |
| Cobro recurrente / suscripción | **No existe.** `stripe-create-checkout` usa `mode: "payment"` — cobro único ligado a un `charge_id` de insumos, no una suscripción |
| Vínculo pago → creación de centro | **No existe** |
| Modelo de licencia / plan | **No existe.** `premium_enabled` es un booleano **por perfil** que un admin prende a mano (`data_repository.dart:392`); no está ligado a ningún pago |

La única pieza que sí existe es `create_organization_with_admin` — y hace exactamente lo
correcto para este camino: crea el centro y promueve **al propio solicitante** a admin, con
`p_admin_is_clinical := true` para el todólogo. **Es el último paso de un flujo cuyos tres
primeros pasos no existen.** Eso explica por qué no se llama desde ninguna parte.

### Decisión de modelo, antes de construir

`premium_enabled` vive en `profiles`. Para una licencia de centro es el **grano equivocado**:
una clínica con cinco clínicos necesitaría prenderlo cinco veces, y nada garantiza que se
mantengan consistentes. Antes de escribir el flujo de pago hay que decidir:

> **¿La licencia es del centro o de la persona?**

Si es del centro (lo natural para B y C), la bandera —y el estado de suscripción— van en
`organizations`, y `premium_enabled` de `profiles` se deprecia o pasa a ser un permiso
individual distinto.

### Y es el único camino con superficie de ataque

A y C son seguros por construcción: un master humano configura cada centro. **B es el único
donde un desconocido toca el sistema sin supervisión** — registro público, pago,
y creación automática de organización. Merece su propia revisión de seguridad, no salir
junto con lo demás.

---

## Orden sugerido

1. **A.1 — tipo de centro en el formulario de alta.** Un campo. Hoy cada hospital que crees
   nace mal tipificado.
2. **Roles por centro (A.3)** — una migración: `roles` en `user_center_memberships` +
   `set_active_center` copiando el conjunto.
3. **A.2 — checklist / asistente de alta con estado de configuración incompleta.**
4. **`is_test`** en `profiles`, `organizations` y `patients`, antes del primer cliente real.
5. **Camino B como proyecto aparte**, empezando por la decisión de licencia (centro vs.
   persona) y con revisión de seguridad propia. No es un arreglo, es un producto.

Los caminos A y C pueden recibir clientes en cuanto estén 1, 2 y 3. **El camino B no tiene
fecha hasta que se decida el modelo de licencia.**
