import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'core/theme/kura_theme.dart';
import 'core/router/app_router.dart';

void main() {
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
