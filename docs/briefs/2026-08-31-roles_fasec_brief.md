# KuraTracker — Roles: se cancela la Fase C, se fusiona `0098` tal cual, y aparece el hallazgo real

**Fecha:** 31-ago-2026
**Reemplaza por completo** la versión anterior de este archivo (la que pedía la migración `0099`/`0098` de limpieza). Esa recomendación era incorrecta; abajo el porqué.
**Para:** agente de desarrollo (VS Code)

---

## 0. El padrón completo

```
carlos.angel@kuramas.com  | carlos.angel@kuramas.com    | admin | {admin,clinico}
carlosangelm@gmail.com    | carlosangelm@gmail.com      | admin | {admin,clinico}
ktqaverify2026@gmail.com  | QA Verificacion KuraTracker | admin | {admin,clinico}
smoketest@curamas.mx      | smoketest@curamas.mx        | admin | {admin,clinico}
```

Cuatro administradores, una sola organización (Kura+), cero usuarios de enfermería.
La cuenta real es `carlosangelm@gmail.com`; las otras tres son instrumentos.

---

## 1. Por qué se cancela la Fase C

La Fase C proponía quitar `clinico` a las tres cuentas de prueba, con el argumento de
que "no son clínicas, son instrumentos". Ese argumento no resiste el código:

- El commit de la rama lo dice explícitamente: **`un {admin}-only (Fase B) NO diagnostica`**.
  `app_user.dart:91` → `canDiagnose => hasRole(AppRole.clinico)`, ya sin `|| admin`.
- `0062_test_staff_cedula.sql` existe **precisamente** para darle cédula de prueba a
  `carlos.angel@kuramas.com` "para jugar con Paciente Prueba". Quitarle `clinico`
  inutiliza la cuenta para lo único que fue creada.
- `ktqaverify2026@gmail.com` es la cuenta con la que se verifican los flujos clínicos.
  Sin `clinico`, después de `0098` deja de poder capturar consultas y de definir planes
  (`patient_detail_screen.dart:110`, `patient_risk_screen.dart:783`). **La cuenta de QA
  dejaría de poder hacer QA.**

Y el argumento de seguridad tampoco aplica: **las cuatro cuentas son nuestras.** El
ensanchamiento que introduce `0098` (un admin ahora sí obtiene hospital-write Grupo A)
se otorga exclusivamente a Kura+. No hay tercero expuesto porque no hay centros cliente.

**Conclusión: `{admin, clinico}` es el conjunto correcto para las cuatro cuentas hoy.**
No hay migración de limpieza. No hay renumeración. `0098_roles_set_phaseB.sql` se
fusiona tal cual, con su número actual, y es la siguiente migración de `main` (que va
en `0097`). El problema de orden que detectaste desaparece porque desaparece la
migración que lo causaba — tu análisis era correcto, la premisa era mía y estaba mal.

---

## 2. El hallazgo real: la compuerta legacy reparte `clinico` sola

En `0098`, el trigger bidireccional conserva el atajo de compatibilidad:

```sql
new.roles := case when new.role = 'admin'::public.user_role
                  then array['admin', 'clinico']::public.user_role[]
                  else array[new.role] end;
```

Está en las dos ramas del trigger (INSERT legacy y UPDATE de writer legacy). Significa:

> **Todo administrador creado por la vía legacy — `role = 'admin'` — recibe `clinico`
> automáticamente, para siempre, sin que nadie lo decida.**

Hoy es inofensivo: los cuatro admins somos nosotros. Pero el RPC
`create_organization_with_admin` (`0011_organizations.sql`) es exactamente la vía por la
que se dará de alta el **administrador de cada centro cliente**. El día que se onboardee
el primer centro, su administrador —una persona ajena a Kura+, probablemente
administrativa y no clínica— nace con escritura clínica a nivel de base de datos.

Ese es el riesgo que la Fase C creía estar atacando, y lo estaba atacando en el lugar
equivocado: no está en las cuatro filas de hoy, está en el trigger que gobierna las de
mañana.

### Qué hacer

**No ahora, pero sí antes del primer centro cliente.** Va como parte del punto 7
(alta de usuario por el admin del centro), no como parche suelto:

1. Que el alta de usuario escriba `roles` **explícitamente** (la Fase B ya lo permite:
   si `roles` viene poblado, es la autoridad y el trigger solo deriva el espejo `role`).
2. Que `create_organization_with_admin` escriba `roles = '{admin}'` salvo que quien da
   de alta marque que esa persona también atiende pacientes — el caso del profesional
   independiente que "hace todo" y por tanto tiene todos los roles.
3. Recién cuando ninguna vía de alta dependa del atajo, retirar el `case` de compat del
   trigger. Mientras exista un writer legacy, quitarlo rompe altas.

**Criterio de aceptación del punto 7:** dar de alta un admin de centro por la UI y
verificar que queda en `{admin}`, no en `{admin, clinico}`.

---

## 3. Plan de ejecución

1. **Merge de `feat/roles-as-set-phaseB` (`0098`) tal cual.** CI verde → aplicada.
2. Verificación posterior (solo lectura, la corre Carlos):
   ```sql
   select email, full_name, role, roles from public.profiles order by email;
   ```
   Esperado: sin cambios en los cuatro admins; el espejo `role` consistente con
   `primary_role(roles)` en todas las filas.
3. Puntos 6-8, con el punto 7 ampliado según §2.
4. Todo por CI (`main` → GitHub Actions → `supabase db push`). Nada a mano en el
   SQL Editor.

---

## 4. Dos temas que no son de roles pero salen de esta misma tabla

**(a) El único administrador real del sistema es una cuenta de Gmail personal.**
`carlosangelm@gmail.com` es hoy la única identidad real con control administrativo sobre
una base con datos de pacientes. Recuperación de cuenta, custodia y baja del titular
dependen de una cuenta de consumo fuera del control de la empresa. Es decisión de Carlos,
no tarea de código, pero conviene resolverla antes de sumar centros cliente.

**(b) Nada distingue una cuenta de prueba de una real.** Tres de las cuatro filas tienen
`full_name` igual al email; la única forma de saber que `carlos.angel@kuramas.com` es de
prueba es leer el comentario de `0062`. Es el mismo problema que "Paciente Prueba".
Sugerido (bajo, no bloquea nada): `profiles.is_test boolean not null default false`, y
que las consultas de KPI lo excluyan. Sin eso, cualquier métrica de adopción que se saque
del padrón cuenta instrumentos como usuarios.
