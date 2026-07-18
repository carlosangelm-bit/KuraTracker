import 'dart:ui';

import 'package:flutter/material.dart';

import '../theme/kura_theme.dart';

/// Tarjeta con estilo "liquid glass" (glassmorphism) reutilizable en toda
/// la app. Solo usa dart:ui (BackdropFilter + ImageFilter.blur), sin
/// paquetes nuevos.
///
/// Composicion:
/// - ClipRRect + BackdropFilter para el vidrio esmerilado (refracta el
///   fondo que quede detras; por eso el dashboard pinta un degradado +
///   blobs de color debajo).
/// - Relleno translucido con un leve gradiente vertical (mas claro arriba)
///   que simula el "sheen" del vidrio, y un borde claro de 1px que hace de
///   reflejo del canto.
/// - Profundidad con sombras EN CAPAS (una cercana de contacto + una amplia
///   y difusa), no una sola.
///
/// [blur] (default true) permite desactivar el BackdropFilter para un modo
/// "glass-lite" (mismo relleno/borde/sombras, sin blur real) — pensado para
/// listas largas donde meter un BackdropFilter por fila causaria jank.
///
/// No gestiona `onTap`: expone un [Material] transparente como ancestro para
/// que cualquier InkWell del [child] pinte su splash, recortado por el mismo
/// radio. Asi cada contenido decide su propia interaccion.
class KuraGlassCard extends StatelessWidget {
  final Widget child;
  final bool blur;
  final double borderRadius;
  final EdgeInsetsGeometry padding;

  /// Tinte opcional (p.ej. color del semaforo) para "colorear" el vidrio de
  /// una metrica urgente: mezcla el color en el relleno y el borde sin
  /// perder la sensacion de vidrio ni el contraste del texto.
  final Color? tint;

  final double blurSigma;

  const KuraGlassCard({
    super.key,
    required this.child,
    this.blur = true,
    this.borderRadius = 24,
    this.padding = const EdgeInsets.all(16),
    this.tint,
    this.blurSigma = 18,
  });

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(borderRadius);

    // Relleno base: blanco mas opaco arriba (0.72) y algo mas translucido
    // abajo (0.55). Alto para no lavar el texto clinico; si aun asi se
    // lavara sobre un fondo mas vivo, subir estos valores.
    const baseTop = Color(0xB8FFFFFF); // blanco ~0.72
    const baseBottom = Color(0x8CFFFFFF); // blanco ~0.55

    final topColor =
        tint == null ? baseTop : Color.alphaBlend(tint!.withOpacity(0.14), baseTop);
    final bottomColor =
        tint == null ? baseBottom : Color.alphaBlend(tint!.withOpacity(0.10), baseBottom);
    final borderColor =
        tint == null ? Colors.white.withOpacity(0.60) : tint!.withOpacity(0.45);

    Widget surface = DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [topColor, bottomColor],
        ),
        borderRadius: radius,
        border: Border.all(color: borderColor, width: 1),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: Padding(padding: padding, child: child),
      ),
    );

    final clipped = ClipRRect(
      borderRadius: radius,
      child: blur
          ? BackdropFilter(
              filter: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
              child: surface,
            )
          : surface,
    );

    // Sombras en capas (fuera del recorte): contacto cercano + profundidad
    // amplia y difusa.
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: [
          BoxShadow(
            color: KuraColors.darkText.withOpacity(0.07),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
          BoxShadow(
            color: KuraColors.darkText.withOpacity(0.10),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: clipped,
    );
  }
}
