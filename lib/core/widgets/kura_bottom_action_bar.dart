import 'package:flutter/material.dart';

import '../design/tokens.dart';

/// Barra de acción INFERIOR fija: el CIERRE de un flujo —confirmar un pedido con su total,
/// el checkout de un carrito— pertenece abajo, a lo ancho, no a un FAB que flota sobre el
/// contenido (§8.2). A diferencia del FAB, no se superpone a la lista: se ancla como
/// `bottomNavigationBar` y el contenido termina por encima. Una sola acción primaria
/// (sólida, brandPrimary del centro), con estado ocupado; un [leading] opcional para el
/// resumen/total a la izquierda. Color desde [BrandTokens].
class KuraBottomActionBar extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final bool busy;
  final Widget? leading;
  const KuraBottomActionBar({
    super.key,
    required this.label,
    this.icon,
    this.onPressed,
    this.busy = false,
    this.leading,
  });

  @override
  Widget build(BuildContext context) {
    final t = BrandTokens.of(context);
    return Material(
      color: t.surface,
      elevation: 8,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          child: Row(
            children: [
              if (leading != null) Expanded(child: leading!) else const Spacer(),
              const SizedBox(width: 12),
              FilledButton.icon(
                onPressed: busy ? null : onPressed,
                icon: busy
                    ? SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(t.onBrand),
                        ),
                      )
                    : Icon(icon ?? Icons.check, size: 18),
                label: Text(label),
                style: FilledButton.styleFrom(
                  backgroundColor: t.brandPrimary,
                  foregroundColor: t.onBrand,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
