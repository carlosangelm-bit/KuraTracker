import 'package:flutter/material.dart';

import '../design/tokens.dart';
import '../router/app_shell.dart' show kFloatingNavBarHeight;

/// FAB de acción principal de la app ("Nuevo paciente", "Nuevo usuario"…): usa
/// el color de MARCA del centro activo (morado/azul/rosa) sólido, con icono y
/// texto en blanco y sombra en capas para dar profundidad. Deliberadamente
/// sólido y sin blur: debe resaltar como acción principal.
///
/// Responsivo: en pantallas anchas es EXTENDIDO (icono + texto); en móvil
/// (compacto) es solo ICONO —el texto va como tooltip— para no ocupar espacio.
/// Se eleva por encima de la barra de navegación flotante para que no lo tape.
class KuraPrimaryFab extends StatelessWidget {
  final VoidCallback? onPressed;
  final IconData icon;
  final String label;

  const KuraPrimaryFab({
    super.key,
    required this.onPressed,
    required this.icon,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    // Se eleva su huella completa = inset del sistema (viewPadding.bottom,
    // safe-area) + alto de la barra flotante + su margen. La barra vive en el
    // Scaffold del SHELL y el FAB en el de cada pantalla (Scaffolds distintos),
    // así que el FAB NO se desplaza solo: hay que elevarlo a mano.
    final t = BrandTokens.of(context);
    final lift =
        MediaQuery.of(context).viewPadding.bottom + kFloatingNavBarHeight + 12;
    // Móvil (compacto): solo icono. Ancho: extendido con texto.
    final compact = MediaQuery.of(context).size.width < 600;
    return Padding(
      padding: EdgeInsets.only(bottom: lift),
      child: DecoratedBox(
        decoration: BoxDecoration(
          shape: compact ? BoxShape.circle : BoxShape.rectangle,
          borderRadius: compact ? null : AppRadii.pillR,
          boxShadow: AppShadows.brandFab,
        ),
        child: compact
            ? FloatingActionButton(
                backgroundColor: t.brandPrimary,
                foregroundColor: Colors.white,
                elevation: 0,
                focusElevation: 0,
                hoverElevation: 0,
                highlightElevation: 0,
                tooltip: label,
                onPressed: onPressed,
                child: Icon(icon),
              )
            : FloatingActionButton.extended(
                backgroundColor: t.brandPrimary,
                foregroundColor: Colors.white,
                // Solo las sombras en capas de arriba (elevation 0 en todos los
                // estados) para que la profundidad sea consistente.
                elevation: 0,
                focusElevation: 0,
                hoverElevation: 0,
                highlightElevation: 0,
                onPressed: onPressed,
                icon: Icon(icon),
                label: Text(label),
              ),
      ),
    );
  }
}
