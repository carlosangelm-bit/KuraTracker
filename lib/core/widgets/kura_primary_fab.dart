import 'package:flutter/material.dart';

import '../router/app_shell.dart' show kFloatingNavBarHeight;
import '../theme/kura_theme.dart';

/// FAB de accion principal de la app ("Nuevo paciente"): rojo de marca Kura
/// SOLIDO con icono y texto en BLANCO (contraste claro sobre cualquier fondo)
/// y sombra EN CAPAS para darle profundidad. Deliberadamente solido y sin
/// blur: debe resaltar como accion principal, no fundirse con el vidrio del
/// resto de la UI.
class KuraPrimaryFab extends StatelessWidget {
  final VoidCallback onPressed;
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
    // Se eleva por encima de la barra de navegacion flotante para que esta no
    // lo tape. Tanto la barra (via SafeArea) como la posicion por defecto del
    // FAB (el Scaffold respeta el safe-area) se desplazan igual con el inset
    // del sistema, asi que una elevacion constante sirve en web y en movil.
    // (kFloatingNavBarHeight 64 + margen inferior de la barra 12 - margen por
    // defecto del FAB 16 + holgura 12 ≈ 72.)
    return Padding(
      padding: const EdgeInsets.only(bottom: kFloatingNavBarHeight + 8),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: KuraColors.primary.withOpacity(0.30),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
          BoxShadow(
            color: KuraColors.primary.withOpacity(0.22),
            blurRadius: 22,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: FloatingActionButton.extended(
        backgroundColor: KuraColors.primary,
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
