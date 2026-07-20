import 'package:flutter/material.dart';

import '../design/tokens.dart';
import '../router/app_shell.dart' show kFloatingNavBarHeight;

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
    // lo tape. La barra vive en el Scaffold del SHELL y el FAB en el de cada
    // pantalla (Scaffolds distintos), asi que el FAB NO se desplaza solo por la
    // barra: hay que elevarlo su huella completa = inset del sistema
    // (viewPadding.bottom, safe-area) + alto de la barra + su margen inferior.
    // Se usa viewPadding (no padding) para que sea estable con extendBody y sin
    // depender del teclado.
    final t = BrandTokens.of(context);
    final lift = MediaQuery.of(context).viewPadding.bottom + kFloatingNavBarHeight + 12;
    return Padding(
      padding: EdgeInsets.only(bottom: lift),
      child: DecoratedBox(
        decoration: const BoxDecoration(
          borderRadius: AppRadii.pillR,
          boxShadow: AppShadows.brandFab,
        ),
        child: FloatingActionButton.extended(
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
