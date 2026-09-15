import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Control de regreso EXPLÍCITO para pantallas que se abren con `context.go` (que REEMPLAZA
/// la ubicación, no apila) o a las que se entra por URL directa / recarga —el caso normal en
/// web—. En esos casos `Navigator.canPop` es false, así que el AppBar NO pinta su flecha y no
/// hay salida salvo el botón del navegador. Cambiar a `context.push` no lo arregla: la flecha
/// desaparecería igual al recargar o entrar por URL. Por eso el regreso es explícito con un
/// [fallback] REQUERIDO: si hay algo en la pila se vuelve (`pop`), si no se va al fallback —su
/// punto de entrada—. Se usa como `leading:` del AppBar.
class KuraBackButton extends StatelessWidget {
  /// Destino cuando no hay nada que desapilar (entrada por URL directa / recarga).
  final String fallback;
  const KuraBackButton({super.key, required this.fallback});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.arrow_back),
      tooltip: 'Volver',
      onPressed: () =>
          context.canPop() ? context.pop() : context.go(fallback),
    );
  }
}
