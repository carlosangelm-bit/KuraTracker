import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:go_router/go_router.dart';

import 'core/theme/kura_theme.dart';
import 'core/router/app_router.dart';
import 'core/config/app_config.dart';
import 'services/supabase/supabase_bootstrap.dart';

Future<void> main() async {
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
    return MaterialApp.router(
      title: 'KuraTracker',
      debugShowCheckedModeBanner: false,
      theme: KuraTheme.light,
      routerConfig: router,
    );
  }
}
