// Dos defectos de la casa, encontrados verificando la etapa 1 en el sandbox:
//
//  1. La reserva inferior de las listas estaba a mano (`88`) mientras la esquina, tras
//     apilar el lanzador de Ayuda sobre el FAB, pasó a ocupar ~200 px: el último elemento
//     de una lista corta quedaba tapado, sin poder scrollear. La reserva pasa a derivarse
//     de las mismas constantes que el FAB y el lanzador (kuraListBottomInset).
//  2. Los interruptores estaban tokenizados a medias (solo el encendido, vía activeColor:
//     suelto); el apagado caía en los grises de Material. Ahora el switchTheme del tema
//     los define en los cuatro estados, con tokens de marca y de borde.
//
// Tres pruebas, cada una roja antes del arreglo:
//  1. Escaneo de fuente bajo lib/features/: sin `, 88)` de reserva ni activeColor: en un
//     Switch/SwitchListTile.
//  2. Widget: lista de 3 elementos + KuraPrimaryFab a 1400×900; el último elemento no
//     queda bajo la huella del FAB ni la del lanzador.
//  3. El tema expone switchTheme y un Switch apagado resuelve su contorno al token de
//     borde, no al outline por defecto de Material.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kuratracker/core/design/tokens.dart';
import 'package:kuratracker/core/theme/kura_theme.dart';
import 'package:kuratracker/core/widgets/kura_primary_fab.dart';
import 'package:kuratracker/models/center_type.dart';

/// ¿Algún `Switch(`/`SwitchListTile(` en [src] trae `activeColor`? Empareja paréntesis
/// para no confundirse con el activeColor de un Slider/Checkbox vecino.
bool _switchHasActiveColor(String src) {
  for (final m in RegExp(r'\bSwitch(?:ListTile)?\s*\(').allMatches(src)) {
    var depth = 0;
    var i = m.end - 1; // en el '('
    for (; i < src.length; i++) {
      final c = src[i];
      if (c == '(') {
        depth++;
      } else if (c == ')') {
        depth--;
        if (depth == 0) break;
      }
    }
    if (src.substring(m.end, i).contains('activeColor')) return true;
  }
  return false;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('lib/features: sin reserva 88 a mano ni activeColor en un Switch', () {
    final bad88 = <String>[];
    final badSwitch = <String>[];
    for (final e in Directory('lib/features').listSync(recursive: true)) {
      if (e is! File || !e.path.endsWith('.dart')) continue;
      final src = e.readAsStringSync();
      if (src.contains(', 88)')) bad88.add(e.path);
      if (_switchHasActiveColor(src)) badSwitch.add(e.path);
    }
    expect(bad88, isEmpty,
        reason: 'reserva inferior a mano; usa kuraListBottomInset(context): $bad88');
    expect(badSwitch, isEmpty,
        reason: 'activeColor en un Switch; el color lo da el switchTheme: $badSwitch');
  });

  testWidgets('lista de 3 + FAB a 1400×900: el último no queda bajo el FAB ni Ayuda',
      (t) async {
    t.view.physicalSize = const Size(1400, 900);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);

    await t.pumpWidget(MaterialApp(
      theme: ThemeData(extensions: <ThemeExtension<dynamic>>[BrandTokens.kura]),
      home: Builder(builder: (context) {
        return Stack(
          children: [
            Scaffold(
              body: ListView(
                // La reserva bajo prueba: deriva de la huella del FAB + lanzador.
                padding: EdgeInsets.only(bottom: kuraListBottomInset(context)),
                children: [
                  for (var i = 0; i < 3; i++)
                    Container(
                      key: ValueKey('item$i'),
                      height: 300,
                      color: Colors.blueGrey.shade50,
                      alignment: Alignment.bottomRight,
                      child: Text('u$i'),
                    ),
                ],
              ),
              floatingActionButton: KuraPrimaryFab(
                icon: Icons.add,
                label: 'Nuevo',
                onPressed: () {},
              ),
            ),
            // El lanzador de Ayuda con su MISMA geometría (kura_primary_fab): apilado
            // sobre el FAB en escritorio. Se representa con una caja de su tamaño.
            Positioned(
              right: 16,
              bottom: kuraLauncherBottom(context),
              child: Container(
                  key: const ValueKey('launcher'),
                  width: 44,
                  height: 44,
                  color: Colors.green),
            ),
          ],
        );
      }),
    ));
    await t.pumpAndSettle();

    // Scroll hasta el FINAL: la reserva se consume abajo y el último elemento se eleva
    // por encima de ella. Con la reserva vieja (88) el último quedaba bajo la esquina.
    final scrollable = t.state<ScrollableState>(find.byType(Scrollable).first);
    scrollable.position.jumpTo(scrollable.position.maxScrollExtent);
    await t.pumpAndSettle();

    final last = t.getRect(find.byKey(const ValueKey('item2')));
    final fab = t.getRect(find.byType(FloatingActionButton));
    final launcher = t.getRect(find.byKey(const ValueKey('launcher')));
    expect(last.overlaps(fab), isFalse,
        reason: 'el último elemento queda bajo el FAB');
    expect(last.overlaps(launcher), isFalse,
        reason: 'el último elemento queda bajo el lanzador de Ayuda');
  });

  test('el tema expone switchTheme y el apagado usa el token de borde', () {
    final tokens = BrandTokens.forCenterType(CenterType.hospital); // marca azul
    final theme = KuraTheme.forType(CenterType.hospital);
    final outline = theme.switchTheme.trackOutlineColor;
    expect(outline, isNotNull, reason: 'el tema debe exponer switchTheme con contorno');
    expect(outline!.resolve(<WidgetState>{}), tokens.border,
        reason: 'el contorno apagado usa el token de borde, no el outline de Material');
    expect(outline.resolve(<WidgetState>{WidgetState.selected}), Colors.transparent,
        reason: 'encendido: track relleno de marca, sin contorno');
  });
}
