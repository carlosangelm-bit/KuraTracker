# Sistema de diseño — tokens (KuraTracker)

KuraTracker es una herramienta **clínica**, no una app de consumidor. La UI
sigue prácticas de UI clínica: paleta calmada, acento reservado, jerarquía
clara, alta legibilidad y consistencia entre pantallas.

Todo el color/espaciado/tipografía vive en **tokens semánticos**
(`tokens.dart`). Los componentes NO usan valores hex sueltos por pantalla.

## Regla de oro

1. **El acento de marca (`brandPrimary`) es solo para ACCIONES.** CTA primario
   (FAB "Nuevo paciente", botón principal) e item de navegación activo. Nunca
   para superficies grandes, fondos ni decoración.
2. **Los colores de ESTADO son CLÍNICOS.** `statusDanger` (no avanza),
   `statusWarning` (con reservas), `statusSuccess` (avanza) y `statusNeutral`
   (sin datos) son los únicos rojo/amarillo/verde de la app y su significado es
   clínico (semáforo de trayectoria de Sheehan), no decorativo.
3. **Superficies neutras y calmadas.** `background`, `surface` y el vidrio
   (`surfaceGlassHigh/Low`) son neutros; el color se gana, no se reparte.

## Cómo usar

```dart
final t = BrandTokens.of(context);
color: t.textSecondary          // texto secundario, legible
color: t.statusDanger           // SOLO estado clínico
color: t.brandPrimary           // SOLO acciones/CTA
```

- **Colores:** `BrandTokens.of(context)` (ThemeExtension). Cae a `BrandTokens.kura`
  si el tema no la registró (tests).
- **Espaciado:** `AppSpacing.xs…xxl` (múltiplos de 4).
- **Radios:** `AppRadii.sm/md/lg/pill` (y sus `BorderRadius` `smR/mdR/lgR/pillR`).
- **Sombras:** `AppShadows.card` (en capas, tarjetas/vidrio) y `AppShadows.brandFab` (FAB).
- **Tipografía:** la fuente la aplica el tema (Nunito, google_fonts). Tamaños y
  pesos estandarizados en `AppType`.

`KuraColors` sigue existiendo como **alias delgado** hacia los tokens (compat
hacia atrás); el código nuevo debe consumir `BrandTokens`.

## Multi-marca (a futuro)

`BrandTokens` es una abstracción por marca. Hoy solo existe `BrandTokens.kura`.
Para agregar otra marca (p.ej. FWD/plataforma) se define otra instancia y se
registra en el `ThemeData` correspondiente — **sin reescribir componentes**,
porque estos ya consumen `BrandTokens.of(context)`.

## ⚠️ Pendiente para Carlos — colisión de color marca ↔ alerta

`brandPrimary` (`0xFFEC0244`, magenta-rojo) y `statusDanger` (`0xFFC0392B`,
rojo) son **ambos rojizos** y pueden confundirse: el acento de acción y la
alerta clínica compiten visualmente. Esta refactorización **restringe** el uso
del acento a acciones (mitiga la colisión al no repartir el rojo de marca por
todos lados), pero **no cambia la identidad de marca**.

Recomendación (decisión de Carlos, no la tomé por mi cuenta):
- Mantener `statusDanger` como el rojo clínico y **diferenciar el acento** de
  marca hacia el lado magenta/rosa (o reservar el acento a formas no rojas en
  contextos donde conviva con alertas), **o**
- Reforzar la distinción por iconografía/forma (el semáforo ya usa icono además
  de color), dejando el acento solo en botones sólidos.

No se aplicó ningún cambio de marca en esta rama.
