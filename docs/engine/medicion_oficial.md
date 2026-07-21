# Medición oficial de la herida (Prompt 6, fix (b))

Aclaración de la fuente oficial de medición, para evitar confusión sobre el
área.

## Qué rige

- **Medición cuantitativa oficial del seguimiento: el VOLUMEN por la fórmula de
  Kundin** — `V = largo × ancho × profundidad × 0.327`
  ([core/utils/wound_volume.dart](../../lib/core/utils/wound_volume.dart)). Se
  captura en las consultas de **valoración** y **seguimiento** y es la métrica
  volumétrica de referencia del expediente.
- **Área trazada (planimetría): eKare**, cuando el dato proviene de la
  integración eKare (import/export, `ekareExternalId`).

## El área 2D in-app es un estimado

El área que calcula la app es **`largo × ancho` (rectángulo)**, un **estimado
manual 2D**, no la fórmula de elipse (`0.785 × L × A`). **No se cambió a elipse
a propósito**: el modelo pronóstico consume `logarea = log(1 + area_cm2)` como
*feature* ya calibrada
([kura_prognosis_model.dart](../../lib/engine/kura_prognosis_model.dart)).
Cambiar la fórmula desplazaría todas las áreas ~21.5% y perturbaría el modelo
sin recalibrar (mismo tipo de riesgo que el techo de ABI del fix arterial, que
requirió aprobación clínica).

**Si se desea adoptar la elipse (0.785) para el estimado 2D**, debe hacerse
junto con una **recalibración del modelo pronóstico** (con datos y aprobación de
María), como cambio separado.
