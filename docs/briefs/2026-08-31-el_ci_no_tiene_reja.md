# KuraTracker — El CI no valida nada. Y hay otra máquina escribiendo en el repo.

**Fecha:** 31-ago-2026 · **Base:** `main` en `9d5ffa7`
**Prioridad:** antes de `0104` (roles por centro).

---

## 1. Corrección: el CI no corre `flutter analyze` NI `flutter test`

El agente reportó: *"no bloquea el deploy (el CI valida con `flutter analyze`, no test)"*.

Verificado sobre `.github/workflows/`:

```
$ grep -rn "flutter test\|flutter analyze" .github/workflows/
(sin resultados)
```

**Ninguno de los dos corre en CI.** Los pasos reales de `build_deploy` son:

1. `flutter --version`
2. verificar secrets
3. `flutter pub get`
4. una guardia `grep` contra interpolaciones con dólar escapado
5. `flutter build web`

Es decir: **el único filtro de calidad es que compile**, más un `grep`. El `flutter analyze`
que el agente reporta como verde lo corre **en su máquina**, no el pipeline.

## 2. Lo que eso significa a la luz de hoy

Hoy salieron **seis despliegues a producción**, todos reportados en verde, tocando:

- RLS y helpers de permisos (Fases A/B de roles, 23 políticas recreadas)
- la compuerta de compra de insumos
- inmutabilidad de consulta y conciliación de pagos
- el modelo de premium (OR → AND) y el registro de divulgaciones
- tres vías de alta de usuarios y el alta de centros
- exportación de expedientes clínicos completos, con fotos

Ninguno pasó por una prueba automatizada. El verde significaba "compiló".

Eso no invalida el trabajo —la verificación fue por lectura de código y consultas a la base,
y encontró cosas reales— pero sí significa que **no hay red bajo el trapecio**, y hoy se
trabajó muy alto.

## 3. Y hay un segundo escritor en el repositorio

Del reporte del agente:

> *"viene del `demo_seed.dart` que modificó **la otra máquina** en el último pull"*

Es la cuarta señal en el día de un actor externo sobre este trabajo:

1. Contenido de otro proyecto (retornables/CEYE/OEM) apareciendo en los insumos del agente.
2. Lo mismo, una segunda vez.
3. Conectores (`Consensus`, `StubHub`) pidiendo autorización en el entorno del agente.
4. **Ésta: código commiteado por otra máquina, que rompió una prueba.**

Las tres primeras eran ruido. **Ésta es escritura sobre `main`.**

### Por qué importa concretamente

- **Numeración de migraciones.** Vamos en `0103` y la numeración es manual. Si la otra máquina
  crea una migración, el número puede colisionar. Y ya establecimos que `supabase db push` sin
  `--include-all` ante una migración fuera de orden **o falla o la salta en silencio** — y el
  silencio es el modo peligroso.
- **RLS sobrescrita.** Varias migraciones de hoy hacen `drop policy` + `create policy`. Dos
  escritores sin coordinación pueden deshacer una corrección de permisos sin que nadie lo note,
  porque no hay prueba que lo detecte (§1).
- **Un revert silencioso de una corrección de seguridad** es el peor caso, y hoy se
  desplegaron varias.

**Esto es una pregunta para Carlos, no una tarea:** ¿qué es la otra máquina? Si es un segundo
entorno tuyo, hay que coordinar (ramas, quién toca migraciones). Si no sabes qué es, eso hay
que resolverlo antes de seguir desplegando.

## 4. Qué hacer antes de `0104`

`0104` reescribe cómo se resuelven los roles al cambiar de centro. Es el cambio de la lista
donde un error se traduce en **alguien perdiendo permisos sin darse cuenta** — precisamente lo
que ninguna prueba detectaría hoy.

**Tarea, en este orden:**

1. **Job `checks` en el CI**, del que dependan `migrations` y `build_deploy`:
   ```yaml
   checks:
     runs-on: ubuntu-latest
     steps:
       - uses: actions/checkout@v4
       - uses: subosito/flutter-action@v2
         with: { flutter-version: '3.27.1' }   # el pin que ya usa el proyecto
       - run: flutter pub get
       - run: flutter analyze
       - run: flutter test
   ```
   Y en los otros dos jobs: `needs: checks`.

2. **Arreglar el test del seed** (`patients_redesign_test.dart`, `PatientWoundSummary` /
   `EXP2025-0001`). No como aseo: **una suite roja que no bloquea es peor que no tener
   suite**, porque entrena a todos a ignorarla. Si va a ser reja, tiene que estar verde.

3. Recién entonces `0104`.

## 5. Nota sobre el alcance de esta recomendación

No estoy pidiendo cobertura de pruebas. La suite que existe es la que existe. Lo que cambia es
**quién la corre**: hoy la corre una persona en su máquina y reporta el resultado; mañana la
corre el pipeline y el resultado bloquea. Es la diferencia entre una afirmación y una garantía
— y hoy tuvimos un ejemplo de que las afirmaciones sobre el pipeline pueden estar equivocadas.
