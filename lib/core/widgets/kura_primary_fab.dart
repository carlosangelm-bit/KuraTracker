import 'package:flutter/material.dart';

import '../design/tokens.dart';
import '../router/app_shell.dart' show kFloatingNavBarHeight;

// --- Geometría de la esquina inferior-derecha (FAB + lanzador de Ayuda) ---------------
// FUENTE ÚNICA. El FAB (abajo), el lanzador de Ayuda apilado encima (tour_scope) y la
// RESERVA inferior de las listas (kuraListBottomInset) derivan de estas constantes, para
// que no queden números a mano que se desincronicen. Fue el bug: las listas reservaban
// 88 mientras la esquina, tras apilar Ayuda sobre el FAB, pasó a ocupar ~200 px.
const double kFabExtendedHeight = 48; // alto de FloatingActionButton.extended (Material)
const double kFabEndFloatMargin = 16; // margen de FloatingActionButtonLocation.endFloat
const double _kLauncherGap = 12; // separación FAB ↔ lanzador de Ayuda
const double _kLauncherSize = 44; // huella del lanzador (icono 22 + padding 11×2)
const double _kContentGap = 12; // separación final entre el contenido y el control

/// Cuánto se eleva el FAB sobre el borde inferior para librar la barra de navegación
/// flotante (móvil) y el safe-area. El FAB se aplica esta elevación a sí mismo, y de
/// aquí derivan el anclaje del lanzador y la reserva de las listas.
double kuraFabLift(BuildContext context) =>
    MediaQuery.of(context).viewPadding.bottom + kFloatingNavBarHeight + 12;

/// Distancia al borde inferior a la que el lanzador de Ayuda se ancla en ESCRITORIO:
/// justo ENCIMA de la huella del FAB (su elevación + margen endFloat + alto + separación).
/// La usa tour_scope para no repetir la fórmula.
double kuraLauncherBottom(BuildContext context) =>
    kuraFabLift(context) + kFabEndFloatMargin + kFabExtendedHeight + _kLauncherGap;

/// Reserva inferior de una LISTA scrolleable que convive con el FAB (y, en escritorio,
/// con el lanzador de Ayuda apilado encima). Deja libre la esquina inferior ocupada para
/// que el último elemento no quede tapado —ni siquiera cuando la lista es tan corta que
/// no scrollea, que era el defecto—. Reemplaza el `88` escrito a mano. En pantallas sin
/// lanzador ([hasLauncher] false) reserva menos. En móvil el lanzador va a la izquierda,
/// así que no suma a la huella del FAB.
double kuraListBottomInset(BuildContext context, {bool hasLauncher = true}) {
  final wide = MediaQuery.of(context).size.width >= 900;
  final fabTop = kuraFabLift(context) + kFabEndFloatMargin + kFabExtendedHeight;
  final top = (wide && hasLauncher)
      ? fabTop + _kLauncherGap + _kLauncherSize
      : fabTop;
  return top + _kContentGap;
}

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
    final lift = kuraFabLift(context); // misma fuente que la reserva de las listas
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
