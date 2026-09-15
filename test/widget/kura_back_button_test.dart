// §13.1 — La conducta del KuraBackButton, aislada y LOCAL (solo go_router + material, sin
// google_fonts): si hay algo que desapilar vuelve (pop); si no —entrada por URL directa /
// recarga, el caso normal en web— va al fallback. La reja que lo aplica a las ocho pantallas
// profundas vive en admin_deep_back_button_test (CI-only).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:kuratracker/core/widgets/kura_back_button.dart';

GoRouter _router() => GoRouter(
      initialLocation: '/home',
      routes: [
        GoRoute(path: '/home', builder: (c, s) => const Scaffold(body: Text('home'))),
        GoRoute(
          path: '/deep',
          builder: (c, s) => Scaffold(
            appBar: AppBar(
              leading: const KuraBackButton(fallback: '/config'),
              title: const Text('profunda'),
            ),
          ),
        ),
        GoRoute(path: '/config', builder: (c, s) => const Scaffold(body: Text('config'))),
      ],
    );

String _loc(GoRouter r) => r.routerDelegate.currentConfiguration.uri.toString();

void main() {
  testWidgets('con pila: desapila (vuelve a de donde vino)', (t) async {
    final r = _router();
    await t.pumpWidget(MaterialApp.router(routerConfig: r));
    await t.pumpAndSettle();
    // push apila /deep sobre /home (canPop == true). Nota: go_router NO cambia la URL en
    // push, así que se verifica por presencia del widget, no por _loc.
    r.push('/deep');
    await t.pumpAndSettle();
    expect(find.byType(KuraBackButton), findsOneWidget, reason: '/deep quedó arriba');
    await t.tap(find.byType(KuraBackButton));
    await t.pumpAndSettle();
    expect(find.byType(KuraBackButton), findsNothing,
        reason: 'con algo en la pila debe hacer pop (se fue /deep)');
    expect(find.text('home'), findsOneWidget);
  });

  testWidgets('sin pila (URL directa): va al fallback', (t) async {
    final r = _router();
    await t.pumpWidget(MaterialApp.router(routerConfig: r));
    await t.pumpAndSettle();
    r.go('/deep'); // reemplaza: canPop == false
    await t.pumpAndSettle();
    await t.tap(find.byType(KuraBackButton));
    await t.pumpAndSettle();
    expect(_loc(r), '/config', reason: 'sin pila debe ir al fallback');
  });
}
