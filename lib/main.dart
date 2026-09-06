import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_web_plugins/url_strategy.dart';

import 'core/theme/kura_theme.dart';
import 'core/router/app_router.dart';
import 'core/config/app_config.dart';
import 'core/providers/session_provider.dart';
import 'features/tour/tour_scope.dart';
import 'services/supabase/supabase_bootstrap.dart';

/// Hardening (bug "pantalla en blanco al crear concepto de catalogo",
/// 2026-07-15): por defecto, en modo release Flutter reemplaza cualquier
/// widget cuyo build() lance una excepcion no capturada por un
/// ErrorWidget gris practicamente invisible (efecto "pantalla en blanco")
/// y NO imprime nada visible en pantalla, aunque FlutterError.onError si
/// recibe el detalle. Esto hace casi imposible diagnosticar en produccion
/// sin acceso a la consola del navegador.
///
/// Este override global reemplaza ese comportamiento por un mensaje de
/// diagnostico visible (excepcion + stack) en el lugar exacto del arbol de
/// widgets donde ocurrio el fallo, en TODOS los modos (debug y release).
/// No sustituye la necesidad de capturar el stack real en la consola del
/// navegador (FlutterError.onError sigue reenviando a
/// dumpErrorToConsole/console.error), pero asegura que el usuario final
/// (o quien reproduzca el bug) vea el texto del error en la UI misma y
/// pueda copiarlo/reportarlo, en vez de una pantalla en blanco silenciosa.
void _installErrorWidgetHardening() {
  ErrorWidget.builder = (FlutterErrorDetails details) {
    return Material(
      color: Colors.red.shade50,
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.error_outline, color: Colors.red.shade700),
                  const SizedBox(width: 8),
                  Text(
                    'Error de interfaz (no se pudo construir esta pantalla)',
                    style: TextStyle(
                      color: Colors.red.shade900,
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SelectableText(
                details.exceptionAsString(),
                style: TextStyle(
                  color: Colors.red.shade900,
                  fontFamily: 'monospace',
                  fontSize: 12,
                ),
              ),
              if (details.stack != null) ...[
                const SizedBox(height: 12),
                const Text(
                  'Stack trace:',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
                ),
                const SizedBox(height: 4),
                SelectableText(
                  details.stack.toString(),
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 10),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  };

  // Complemento: cualquier excepcion de framework (no solo de build()) que
  // Flutter capture (p.ej. en callbacks de gestos, animaciones) se sigue
  // reportando por el canal normal (consola/dumpErrorToConsole) pero
  // ademas queda registrada aqui por si se agrega en el futuro un canal
  // de reporte remoto (Sentry, etc.) sin tener que tocar este archivo de
  // nuevo.
  final previousOnError = FlutterError.onError;
  FlutterError.onError = (FlutterErrorDetails details) {
    previousOnError?.call(details);
    if (kDebugMode) {
      // ignore: avoid_print
      print('FlutterError capturado: ${details.exceptionAsString()}');
    }
  };
}

Future<void> main() async {
  _installErrorWidgetHardening();

  // URLs limpias en Flutter Web (sin '#'). El fallback SPA correspondiente
  // para Cloudflare Pages vive en web/_redirects ('/* /index.html 200'),
  // que se copia automaticamente a build/web/_redirects en el build.
  usePathUrlStrategy();

  // Inicializa el cliente Supabase (Auth + Postgrest + Storage) si hay
  // credenciales configuradas via --dart-define. En modo demo local (sin
  // credenciales) la app sigue funcionando 100% con el almacen local.
  if (AppConfig.isSupabaseConfigured) {
    await SupabaseBootstrap.initialize();
  }

  runApp(const ProviderScope(child: KuraTrackerApp()));
}

class KuraTrackerApp extends ConsumerWidget {
  const KuraTrackerApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    // Paleta reactiva al tipo de centro ACTIVO (morado/azul/rosa). Al alternar
    // de centro desde el ícono de apósitos, el tema se reconstruye.
    final centerType = ref.watch(activeCenterTypeProvider);
    return MaterialApp.router(
      title: 'KuraTracker',
      debugShowCheckedModeBanner: false,
      theme: KuraTheme.forType(centerType),
      routerConfig: router,
      // Recorrido guiado (solo demo): navega por los flujos y explica cada
      // pantalla. En producción es transparente (no se muestra).
      builder: (context, child) => TourScope(
        child: SandboxBanner(child: child ?? const SizedBox.shrink()),
      ),
    );
  }
}

/// Franja fija "SANDBOX · datos de prueba" en la parte superior de la app,
/// SOLO cuando el build se compiló con `--dart-define=APP_ENV=sandbox` (rama
/// `staging`). En producción y en la demo no agrega nada al árbol.
class SandboxBanner extends StatelessWidget {
  const SandboxBanner({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!AppConfig.isSandbox) return child;
    return Column(
      children: [
        const Material(
          color: Color(0xFFE65100),
          child: SafeArea(
            bottom: false,
            child: SizedBox(
              height: 22,
              width: double.infinity,
              child: Center(
                child: Text(
                  'SANDBOX · entorno de pruebas · datos sintéticos, no es el expediente real',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.6,
                  ),
                ),
              ),
            ),
          ),
        ),
        Expanded(child: child),
      ],
    );
  }
}
