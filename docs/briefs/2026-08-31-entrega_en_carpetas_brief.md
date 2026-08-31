# KuraTracker — Entrega en carpetas de archivos (reemplaza el expediente en PDF)

**Fecha:** 31-ago-2026 · **Base:** `main` en `952640c`
**Para:** agente de desarrollo
**Reemplaza** §3.3, §3.4 y §2 de `KuraTracker_expediente_pdf_y_divulgacion_brief.md`.
El §3 de ese documento (registro de divulgación `data_disclosures`) **sigue vigente sin
cambios** y sigue siendo el primer paso.

---

## 0. La decisión y por qué es la correcta

**Decisión de Carlos:** en lugar de generar PDFs, producir **carpetas de archivos** —fotos,
mediciones, diagnósticos, consultas— que el usuario exporta a donde quiera.

No es solo más simple: **escala mejor**, y por una razón concreta. El plan del PDF tenía un
riesgo que iba a aparecer con los 300+ pacientes de Kura+: para armar un PDF hay que
*renderizar* —cargar cada foto en memoria, componer página, mantener el documento entero
hasta escribirlo. Con carpetas **nunca se sostiene el entregable completo en memoria**: cada
archivo se escribe y se suelta. El techo de memoria desaparece en vez de administrarse.

Y para quien recibe es mejor: un árbol de carpetas es navegable por una persona **y**
parseable por otro sistema. Un PDF no es ninguna de las dos.

**Lo único que se pierde** es el caso "entregar un documento impreso/firmado de UN paciente".
Eso queda como función aparte, opcional y posterior — no bloquea la entrega de salida. Los
generadores que ya existen (`referral_pdf.dart`, `prevention_report_pdf.dart`) siguen ahí
para cuando se quiera.

---

## 1. Cómo se entrega "a donde quiera" en Flutter Web

Flutter Web no puede escribir un árbol de carpetas en el disco por sí solo. Dos caminos, y
conviene implementar **los dos**:

### (a) ZIP descargable — la base que siempre funciona

Un solo archivo, el usuario lo descomprime donde quiera. Funciona en cualquier navegador.
Requiere agregar **`archive`** a `pubspec.yaml` (no está hoy).

**Crítico:** usar escritura **por streaming** (`ZipFileEncoder` con `addFile`/`addArchiveFile`
incremental), **no** construir el `Archive` completo en memoria. Con gigabytes de fotos, la
versión en memoria falla.

### (b) Selector de carpeta — el que de verdad hace lo que pediste

La **File System Access API** (`window.showDirectoryPicker()`) permite que la app web escriba
un árbol real en la carpeta que el usuario elija. Es **solo Chromium** (Chrome, Edge; no
Safari ni Firefox).

El proyecto ya tiene el patrón exacto para llegar ahí: `lib/services/csv_download_web.dart`
usa `dart:js_interop` + `package:web`. Misma técnica, con la fábrica condicional que ya existe
en `csv_download.dart` (`stub` / `web` / `io`).

**Y es el camino técnicamente superior para exportaciones grandes:** escribe incrementalmente
a disco, así que no tiene techo de memoria ni de tamaño. El ZIP es el respaldo para navegadores
que no lo soportan.

**Detección:** si `showDirectoryPicker` no existe, ofrecer solo ZIP, sin mensaje de error —
degradación silenciosa.

## 2. Estructura de carpetas propuesta

```
<centro>_<YYYY-MM-DD>/
  manifiesto.csv                  ← qué se exportó, conteos, fecha, quién
  mediciones.csv                  ← todas (la exportación que ya existe)
  consultas.csv                   ← todas (la exportación que ya existe)
  pacientes/
    <folio>/
      datos.csv                   ← demográficos, diagnósticos, comorbilidades
      mediciones.csv              ← solo de este paciente
      consultas.csv               ← solo de este paciente
      heridas/
        <herida_id>_<etiologia>/
          mediciones.csv
          fotos/
            2026-03-14_<id>.jpg
            2026-03-21_<id>.jpg
```

### El detalle que sustituye al PDF

En el plan del PDF, la utilidad clínica dependía de poner **la foto junto a las medidas de su
misma fecha**. Aquí se consigue gratis: **las fotos se nombran con la fecha al inicio**, así
que cualquier explorador de archivos las ordena cronológicamente y la serie evolutiva se lee
sola. El `mediciones.csv` de esa carpeta tiene la misma fecha como llave.

Es más legible que el PDF, no menos.

### Notas de nomenclatura

- El `<folio>` como nombre de carpeta, **no el nombre del paciente**: evita problemas de
  acentos, mayúsculas y caracteres inválidos en distintos sistemas de archivos, y el nombre
  ya va dentro de `datos.csv`.
- Sanear todo componente de ruta (quitar `/ \ : * ? " < > |`, recortar longitud). Un folio con
  un carácter raro no debe romper la exportación completa.
- CSVs con **BOM UTF-8**, igual que `downloadCsv` ya hace, para que Excel no rompa los acentos.

## 3. Fotos: bytes originales, sin reescalar

El bucket es **privado**; se accede con `createSignedUrl(path, 3600)`
(`lib/services/photo_upload_service.dart:86`). Una petición por imagen.

Con carpetas **no hay razón para reescalar**: se entrega el archivo original, que es la
evidencia clínica real. Eso además elimina el paso de transcodificación y su costo.

Lo que sí hay que manejar: **la hora de expiración de las URLs firmadas.** Una exportación de
300 pacientes puede tardar más que los 3600 s si se generan todas las URLs al inicio. Genera
la URL firmada **justo antes de descargar cada foto**, no en un lote inicial.

## 4. Progreso y robustez

- Progreso visible por paciente (`142 / 317`), no una barra indeterminada.
- **Una foto que falle no debe abortar la entrega:** registrarla en el manifiesto como
  faltante y continuar. Al final, decir cuántas faltaron y cuáles.
- Poder reanudar, o al menos reintentar solo los faltantes.
- Confirmar el conteo final contra la base: si el manifiesto dice 317 pacientes y el centro
  tiene 317, la entrega está completa. **Ese contraste es lo que hace defendible la entrega**,
  y es lo que hoy no existe en el proceso manual.

## 5. Orden

1. **`data_disclosures`** (§3 del brief anterior, sin cambios) + escritura desde las dos CSV
   ya en producción. Sigue siendo el primer paso: cierra el hueco que abrió el último deploy.
2. **Un paciente en carpeta** — genera el árbol de un solo paciente y descárgalo como ZIP.
   Valida estructura, nombres y fotos con un caso real antes de escalar.
3. **`archive` + ZIP por streaming** para la entrega completa del centro.
4. **Selector de carpeta** (File System Access API) donde el navegador lo soporte, siguiendo
   el patrón de `csv_download_web.dart`.
5. Pantalla que liste las divulgaciones del centro.

El PDF por paciente queda **fuera de alcance** hasta que alguien lo pida para imprimir.
