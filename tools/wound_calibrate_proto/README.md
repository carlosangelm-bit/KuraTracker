# WoundCalibrate — Prototipo del motor de medición (Fase 1a)

Módulo **independiente en Python** para medir heridas de forma **objetiva y
reproducible** a partir de una foto que incluya la tarjeta WoundCalibrate.
**No está integrado en la app Flutter** — es para iterar rápido en la visión y
**probar exactitud** antes de portarlo on-device (Fase 1b).

> ⚠️ **Solo geometría/medición.** Color y clasificación de tejido son Fase 2.

## Qué hace

Dada una foto con la tarjeta visible + `card_spec.json` (geometría real de la
tarjeta), el pipeline:

1. **Detecta los 4 AprilTags 36h11** (`pupil-apriltags`) → ID + posición en px.
2. **Homografía imagen→métrica** con los 4 centros de tag (mm↔px) → **imagen
   rectificada** (vista cenital) con `mm/px` conocido.
3. **Verifica la escala** detectando el círculo de referencia de 12.7 mm en la
   imagen rectificada; reporta el desvío (criterio ±3 %).
4. **Compuertas de calidad** (devuelve el motivo si falla): 4 tags detectados,
   planaridad (error de reproyección independiente), círculo en tolerancia,
   sin sobreexposición, distancia 10–30 cm.
5. **Mide** un contorno de herida (manual en Fase 1: lista de puntos) en el
   espacio métrico → área (cm²), largo, ancho, perímetro.
6. **Salida**: `result.json` (medidas + `mm_por_px` + flags de calidad) +
   `rectified.png` + `overlay.png`.

## Instalación

```bash
cd tools/wound_calibrate_proto
python3 -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
```

## Uso

```bash
# Medir una foto (con contorno de herida trazado a mano)
python run.py --image foto.jpg --spec card_spec.json \
              --contour samples/example_contour.json --out out/

# Ver salida
cat out/result.json      # medidas + mm_por_px + calidad
open out/overlay.png     # rectificada con contorno + medidas dibujadas
```

Flags útiles: `--px-per-mm` (resolución de la rectificada, def. 12),
`--no-gates` (no bloquear la medida si falla una compuerta).

### El contorno de la herida

En Fase 1 el clínico traza el contorno. Se pasa como JSON (ver
[samples/example_contour.json](samples/example_contour.json)):

```json
{ "coords": "rect_px", "points": [[x,y], ...] }
```

`coords`: `"rect_px"` = píxeles de `rectified.png`, o `"mm"` = milímetros en el
marco de la tarjeta. El polígono se cierra solo.

## `card_spec.json` — la "verdad" de la tarjeta

Config **editable** con la geometría física real de la tarjeta impresa
(coordenadas en mm, origen en la esquina sup-izq, **eje Y hacia abajo**):

- IDs de los **4 AprilTags 36h11** (deben ser 4 IDs distintos) + `center_mm` + `size_mm`.
- `reference_circle`: `diameter_mm` = 12.7 (spec de diseño) + `center_mm`.
- `ruler`: origen/orientación/longitud (cross-check opcional).
- `camera.focal_length_px` (opcional): si se conoce, la compuerta de distancia
  se evalúa en cm; si es `null`, se reporta el tamaño de tag en px (proxy).

> 🚧 **El archivo actual tiene `is_placeholder: true`.** Los valores son de
> ejemplo (tarjeta tamaño crédito). **Reemplázalos por los MEDIDOS del impreso
> real** — hasta entonces `run.py` avisa que las medidas no son confiables.

## Validación (parte central del entregable)

### A) Validación sintética — **corre hoy, sin hardware** ✅

`make_synthetic.py` renderiza la tarjeta (4 AprilTags 36h11 reales + disco de
12.7 mm + una **herida sintética de dimensiones conocidas**) y le aplica una
perspectiva simulada. Como conocemos las medidas reales, medimos el error de
toda la cadena:

```bash
python make_synthetic.py --n 3       # genera fotos + ground_truth.json
python validate.py                   # mide error de área/longitud vs verdad
```

**Resultado actual del algoritmo sobre imágenes sintéticas:**

| Métrica            | Medido   | Criterio  | Estado |
|--------------------|----------|-----------|--------|
| Error de **área**  | ≤ 0.16 % | < 5 %     | ✅ PASA |
| Error de **largo** | 0.00 %   | < 3 %     | ✅ PASA |
| Cross-check círculo| ≤ 0.16 % | ±3 %      | ✅ PASA |
| Reproducibilidad (3 fotos) | 0.07 % | ~< 5 % | ✅ PASA |

Esto prueba que **la matemática del motor es correcta** (detección → homografía
→ escala → medición). No sustituye la validación con hardware.

### B) Validación real — **pendiente de hardware** 🚧

Para un número de exactitud confirmado se necesita:

1. **`card_spec.json` real** — geometría medida de la tarjeta impresa.
2. **Tarjetas impresas** de prueba.
3. **Un objeto de medida conocida** (el propio disco de 12.7 mm + algo medido
   con regla) fotografiado junto a la tarjeta.

Con eso, `validate.py` se extiende para reportar el error contra la regla.
**Hasta tener (1)+(2)+(3), el prototipo queda armado pero sin número de
exactitud real confirmado.**

## Estructura

```
tools/wound_calibrate_proto/
├── card_spec.json          # "verdad" de la tarjeta (EDITAR con valores reales)
├── requirements.txt
├── run.py                  # CLI: foto -> result.json + rectified + overlay
├── make_synthetic.py       # genera fotos sintéticas + ground truth
├── validate.py             # mide error de área/longitud vs ground truth
├── wound_calibrate/
│   ├── spec.py             # carga/valida card_spec.json
│   ├── detect.py           # AprilTags 36h11 (pupil-apriltags)
│   ├── homography.py       # homografía + rectificación + planaridad
│   ├── scale.py            # verificación de escala con el círculo
│   ├── quality.py          # compuertas de calidad
│   ├── measure.py          # área/largo/ancho/perímetro
│   ├── overlay.py          # dibujo del overlay
│   └── pipeline.py         # orquestación
└── samples/
    ├── example_contour.json
    └── synthetic/          # (generado) fotos + ground_truth.json
```

## Notas de diseño / decisiones

- **Homografía con centros de tag** (no esquinas): robusta a la orientación del
  tag; no hay que emparejar esquina-con-esquina.
- **Error de reproyección independiente**: como 4 centros definen la homografía
  de forma exacta, su residual sería ~0 y no serviría de señal. La planaridad se
  mide aparte: se rectifican las esquinas de cada tag y se comparan sus lados con
  `size_mm`. Si la tarjeta no está plana, se desvían.
- **Escala del círculo**: se mide el borde externo de la marca (exacto para un
  disco/marca sólida). Si la tarjeta real usa un **anillo fino**, ajustar
  `scale.py` para medir la línea media del anillo.
- **Distancia en cm**: requiere `focal_length_px`. Sin ella se reporta el tamaño
  de tag en px como proxy y la compuerta en cm se marca omitida.

## Fase 1b (integración on-device) — HECHA en `lib/engine/vision`

El algoritmo se portó a **Dart puro** (sin OpenCV ni detector nativo: corre en
Flutter Web y móvil, las fotos no salen del dispositivo), incluyendo el detector
AprilTag 36h11, y se añadieron segmentación de la herida, clasificación de tejido
por reglas y la integración en las pantallas de captura. Ver
[docs/engine/motor_vision.md](../../docs/engine/motor_vision.md).

Este prototipo Python sigue siendo útil para **iterar rápido** sobre fotos reales
y comparar contra el motor Dart (misma matemática). El `card_spec.json` real debe
copiarse a `assets/engine/vision/card_spec.json` (con `is_placeholder=false`).
