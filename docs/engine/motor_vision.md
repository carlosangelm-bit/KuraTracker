# Motor de visión de heridas (`lib/engine/vision`)

Medición automática de la herida (área, largo, ancho, perímetro) y estimación de
la composición del lecho (granulación / esfacelo / necrosis / epitelización) a
partir de **una fotografía con referencia de escala**, corriendo **en el
dispositivo** (Dart puro, sin plugins nativos → Flutter Web, iOS y Android).
Las fotos no salen del dispositivo (mismo criterio de PHI que el resto de la
app).

Es la **Fase 1b** del plan de `tools/wound_calibrate_proto` (el prototipo
Python validó la geometría; este módulo la porta a Dart y añade segmentación,
tejido y la integración en las pantallas de captura).

> **Apoyo a la decisión clínica — no sustituye el juicio clínico.** El motor
> *propone* largo, ancho y composición; el clínico revisa y edita antes de
> guardar. El origen queda registrado en `wound_measurements.measurement_source`
> y la trazabilidad completa en `vision_meta` (migración `0108`).

## Flujo en la app

Botón **«Medir con foto»** en la sección de medición de la **valoración inicial**
(`wound_capture_screen`) y del **seguimiento** (`follow_up_capture_screen`).
Abre `WoundVisionScreen` (`lib/features/wound_capture/widgets/wound_vision_screen.dart`):

1. **Calibración** (automática al abrir): localiza la **tarjeta WoundCalibrate**
   (4 AprilTags 36h11) → homografía → imagen **rectificada** (vista cenital)
   con `mm/px` conocido; verifica la escala con el círculo de 12,7 mm; y
   **normaliza color y exposición** usando la propia tarjeta (ver abajo). Si no
   hay tarjeta, busca el **disco de referencia** (verde, diámetro conocido): da
   escala pero **no corrige perspectiva ni color** (dos compuertas de aviso).
2. **Delimitación**: el clínico **toca dentro de la herida** (uno o varios
   toques, uno por tipo de tejido si hay varios; p. ej. el borde en
   epitelización solo entra si se toca) o **traza el contorno a mano**.
   Slider de sensibilidad para ampliar/estrechar la región.
3. **Resultado**: largo, ancho, área (planimetría), perímetro, barras de tejido,
   capa de color por tejido sobre la foto y lista de **compuertas de calidad**.
4. **«Aplicar a la valoración»**: pre-llena largo/ancho (a 0,1 cm) y los cuatro
   sliders del lecho; guarda `measurement_source`, `area_planimetric_cm2` y
   `vision_meta`. Si el clínico edita después, `vision_meta.edited = true`.
   «Quitar origen foto» vuelve a `manual` conservando los números.

## Qué mide y cómo

| Medida | Método | Nota |
|---|---|---|
| **Área** | Planimetría: píxeles de la máscara × (mm/px)² | Va a `area_planimetric_cm2`. **`area_cm2` no cambia**: sigue siendo L × A × 0,785 (alimenta el pronóstico, calibrado con ese estimado; ver `medicion_oficial.md`). |
| **Largo (oficial)** | Extensión en el eje **X** de la imagen rectificada (= borde LARGO de la tarjeta) | Convención de **regla** (cabeza-pies). Redondeado a 0,1 cm al aplicar. |
| **Ancho (oficial)** | Extensión en el eje **Y** de la imagen rectificada (borde corto) | Convención de regla (lateral). |
| **Feret máx / ancho perp.** | Mayor distancia entre dos puntos y su perpendicular | **Dato adicional** en `vision_meta` (`feret_length_cm`/`feret_width_cm`). **Nunca** es la medida oficial. |
| **Perímetro** | Polígono simplificado (Douglas–Peucker, ε = 1 px) | Evita la sobreestimación en escalera. |
| **Tejido** | Reglas HSV por píxel + prototipo Lab más cercano | Porcentajes enteros que suman 100. |
| **Profundidad / volumen** | **No se miden** desde una foto | Siguen manuales (Kundin). |

### Convención de largo/ancho: ejes X/Y (regla), no Feret

El expediente lleva largo y ancho en **convención de regla** — los ejes **X/Y**
de la imagen rectificada (el marco métrico de la tarjeta) — porque así fueron
concebidas y validadas la fórmula de Kundin (volumen) y el estimado de elipse
`L × A × 0,785`. **María validó la constante 0,785 contra medidas de regla**, no
contra el eje de Feret.

Antes el motor reportaba **largo = Feret máximo** (mayor distancia entre dos
puntos, en cualquier dirección) y **ancho = su perpendicular**, y alimentaba con
esos valores `ellipseArea` → `area_cm2` (que alimenta el modelo pronóstico
`logarea`) y el volumen de Kundin. Para una herida oblicua al eje del cuerpo el
Feret sobreestima ambos ejes. Medido con una figura de 40×30 mm (área real
12,00 cm²):

| | Largo × Ancho | Estimado elipse |
|---|---|---|
| Convención regla (X/Y) | 4,0 × 3,0 | **9,4 cm²** |
| Feret (antes) | 5,0 × 4,8 | 18,8 cm² |

Es decir, un centro premium habría tenido pronósticos corridos ~2× frente a uno
básico. Hoy: **largo = extensión en X, ancho = extensión en Y**; el Feret y su
ancho perpendicular se conservan en `vision_meta` (`feret_length_cm` /
`feret_width_cm`) como dato de inspección, nunca como la medida oficial. El área
por planimetría (`area_planimetric_cm2`) **no cambia**: sigue siendo la medida
real, en su columna aparte, a la espera de validación clínica.

**Protocolo de captura (sin ambigüedad):** la tarjeta es apaisada (85,6 × 54 mm).
Coloca su **borde LARGO paralelo al eje cabeza-pies** del paciente (el borde largo
a lo largo del cuerpo/miembro, como se pondría una regla). La rectificación lleva
el borde largo al eje X, así que con esa colocación **largo = cabeza-pies** y
**ancho = lateral**. Es la posición que un clínico hace por inercia al dejar la
tarjeta junto a la herida; la pista en pantalla lo muestra con un diagrama.

```
      cabeza ↑
       ┌───┐
       │   │   borde LARGO de la tarjeta
       │ ● │   ∥ eje cabeza-pies  (● = herida al lado)
       │   │
       └───┘
      pies  ↓
```

## Normalización de color: por qué la tarjeta también es referencia de color

El clasificador de tejido usa umbrales de tono y brillo **absolutos** (rojo =
granulación, amarillo = esfacelo, oscuro = necrosis), así que depende de la luz
de la sala y del balance de blancos del teléfono. Medido sobre la escena
sintética (`test/engine/vision/illumination_test.dart`), **sin normalizar**:

| Luz | Área | Tejido (verdad 60/30/10) |
|---|---|---|
| Referencia D65 | 0,0 % | 60/30/10 |
| **Lámpara cálida** | **−29,9 %** | **86/0/14** |
| **Subexpuesta −40 %** | **−29,7 %** | **85/0/15** |
| Sombra fría / fluorescente / sobreexpuesta | ≤ 0,1 % | 60/30/10 |

No es solo que clasifique mal: **la segmentación pierde el parche de esfacelo**
y el área cae ~30 %. Y para el seguimiento serial —de lo que vive el producto—
importa aún más: un cambio de sala entre visitas movería los porcentajes del
lecho y contaminaría la tendencia que consume el checkpoint de Sheehan.

**No hizo falta rediseñar la tarjeta**: el papel blanco y la tinta negra de los
marcadores ya son dos referencias neutras. Se estiman por percentiles dentro de
la región de la tarjeta y se aplica una corrección diagonal (von Kries) por
canal, `out = (in − negro)/(blanco − negro) × objetivo`, a la imagen rectificada
completa antes de segmentar. Con eso, las seis condiciones quedan dentro de
**±0,5 % de área y ±1 punto de tejido**. Parámetros en `vision_params.json →
illumination`; ganancias y diagnóstico viajan en `vision_meta.calibration.illumination`.

**Límites, en orden de importancia:**

1. **El disco de respaldo no corrige color** (es verde, no neutro). Con disco,
   los porcentajes de tejido quedan a merced de la luz — la compuerta lo dice.
   Para composición del lecho, tarjeta.
2. **Iluminación no uniforme**: si la tarjeta queda a la sombra y la herida
   iluminada (o al revés), una ganancia global no lo arregla.
3. Es una corrección **diagonal**: normaliza el cast global y la exposición, no
   la respuesta espectral de la cámara. Para eso harían falta parches cromáticos
   con valores Lab **medidos con espectrofotómetro** — una impresión de oficina
   no los garantiza y además se decoloran. Vale la pena solo si, con fotos
   reales, la corrección diagonal se queda corta.
4. Si la tarjeta sale **quemada** (papel saturado en algún canal), la corrección
   es aproximada; la compuerta avisa y pide evitar el flash directo.

Nota: la imagen rectificada que se guarda y se muestra al clínico es la
**corregida** (es la que el motor mide). La foto original intacta sigue en
`wound_photos`, y las ganancias quedan en `vision_meta` para poder deshacerla.

## Arquitectura

```
lib/engine/vision/
├── wound_vision_engine.dart   # orquestador: calibratePhoto → analyze / analyzeManualTrace
├── reference_calibrator.dart  # tarjeta (homografía, rectificación, planaridad, círculo) y disco
├── illumination_corrector.dart # normalización de color/exposición con la tarjeta como referencia neutra
├── apriltag_detector.dart     # AprilTag 36h11 en Dart puro (umbral adaptativo, quads, refinado, decodificación)
├── tag36h11_table.dart        # 587 códigos (hex; dart2js trunca bit a bit a 32 bits)
├── wound_segmenter.dart       # WoundSegmenter (contrato) + ColorRegionSegmenter (clásico)
├── tissue_classifier.dart     # TissueClassifier (contrato) + RuleTissueClassifier (reglas JSON)
├── wound_measurer.dart        # área / Feret / ancho / perímetro
├── rasters.dart               # RgbRaster, GrayRaster, BitMask (CC, morfología, contorno de Moore)
├── color_spaces.dart          # sRGB → Lab / HSV
├── vision_geometry.dart       # Pt, Homography (DLT), envolvente, Feret, Douglas–Peucker
├── vision_params.dart         # CardSpec + VisionParams (assets) + VisionAssets.load()
└── wound_vision_models.dart   # resultados, compuertas, vision_meta
assets/engine/vision/
├── card_spec.json             # geometría de la tarjeta (⚠ is_placeholder=true hasta medir el impreso)
└── vision_params.json         # TODOS los umbrales del motor (nada clínico en el código)
```

`WoundSegmenter` y `TissueClassifier` son **contratos**: cuando exista dataset
propio etiquetado, un modelo aprendido (TFLite en móvil / ONNX-web en el
navegador) se enchufa ahí sin tocar UI ni persistencia.

`package:image` (ya en `pubspec`) se usa solo para decodificar/codificar; todo
el numérico corre sobre listas tipadas propias, lo que lo hace portable a
isolates (`compute`) — en Web corre en el mismo hilo (~1–2 s por foto de 1600 px).

## Validación

**Sintética (corre en `flutter test`)** — `test/engine/vision/`: se renderiza la
tarjeta con AprilTags reales + herida elíptica con parches de tejido de
fracción conocida y se aplica una perspectiva de cámara conocida. Resultado del
algoritmo (mismo pipeline validado antes en Python):

| Métrica | Sintético | Criterio |
|---|---|---|
| Error de área | < 1 % (tilt 0–0,22, heridas 16×12 a 70×30 mm) | < 5 % |
| Error de largo / ancho | < 1 % | < 3 % |
| Planaridad (lados de tag) | < 1 % | ≤ 5 % |
| Cross-check círculo 12,7 mm | < 0,2 % | ±3 % |
| Composición del lecho | exacta al 1 % | — |
| Disco de respaldo (cenital) | área −0,6 % | < 5 % |
| Estabilidad ante 6 condiciones de luz | área ±0,5 %, tejido ±1 punto | — |

**Real — pendiente (bloqueante para uso clínico):**
1. **Imprimir la tarjeta** desde `tools/wound_calibrate_proto/print/` (generada con
   `make_print_card.py` a partir del mismo `card_spec.json` que lee el motor, así que la
   geometría es conocida por construcción). Imprimir al 100 %, comprobar con regla que la
   escala impresa mide 50 mm (y la de control de la hoja, 100 mm) → entonces
   `is_placeholder=false` (hasta entonces el motor muestra la compuerta «Geometría de la
   tarjeta» en aviso). Si se manda a imprenta con otro diseño, medir el impreso y actualizar
   el spec.
2. Fotos reales con tarjeta + objeto de medida conocida → error contra regla.
3. Ajustar `tissue.rules` / `prototypes_lab` con fotos etiquetadas por el equipo
   clínico (María). Los colores de tejido reales varían mucho más que los
   sintéticos. **Etiquetar sobre la imagen YA normalizada**, no sobre la foto
   cruda: si no, se calibran umbrales contra la luz de ese día.
4. Disco de respaldo: fijar el insumo (diámetro y color) y ajustar `fallback_disc`.

## Compuertas de calidad (`vision_params.json → quality`)

`tags` (4/4) · `planarity` (≤ 5 %) · `scale_check` (círculo ±3 %, o `skip`) ·
`distance` (tag ≥ 28 px; aviso) · `color` (normalización con la tarjeta; avisa si
no se pudo, si la tarjeta salió quemada, o —en modo disco— que no hay referencia
neutra) · `exposure` (≤ 2 % quemado en la herida; aviso) · `card_spec` (aviso
mientras sea provisional) · en disco: `disc_tilt` (≥ 0,90) y `perspective`
(aviso permanente). `fail` no bloquea la aplicación en esta fase:
se muestra en rojo y viaja en `vision_meta.gates` para que el análisis
posterior pueda filtrar mediciones de baja calidad. Decidir con María si alguna
compuerta debe bloquear.

## Decisiones

- **Dart puro** en vez de TFLite/OpenCV: la app es Flutter Web hoy; no hay
  dataset propio; y las fotos no deben salir del dispositivo. El precio es
  segmentación clásica (color), mitigada con toques múltiples, sensibilidad y
  trazo manual.
- **Tarjeta principal + disco de respaldo**: la tarjeta corrige perspectiva y
  verifica escala; el disco es para cuando no hay tarjeta a la mano.
- **`area_cm2` intacto**: el pronóstico se calibró con el estimado; el área real
  vive en `area_planimetric_cm2` hasta recalibrar (misma cautela que el cambio
  rectángulo → elipse).
- **Los umbrales viven en JSON**, no en código (misma disciplina que
  `ClinicalParams`).
