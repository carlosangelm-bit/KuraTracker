// §13.2 — Los diálogos se visten desde el TEMA, no en los ~87 sitios de llamada. Un
// AlertDialog PELÓN bajo el tema real de un centro HOSPITAL (azul) debe resolver su fondo y
// su forma desde los tokens de ESE tipo —no de Material 3 (radio 28, tinte de elevación) ni
// del morado de la clínica—. Así el diálogo cambia de color con el tipo de centro sin que
// nadie lo pida.
//
// CI-ONLY: KuraTheme.forType usa GoogleFonts → google_fonts, que la toolchain local (3.44)
// no compila. `flutter analyze` valida; corre en CI (3.27.1).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kuratracker/core/design/tokens.dart';
import 'package:kuratracker/core/theme/kura_theme.dart';
import 'package:kuratracker/models/center_type.dart';

void main() {
  testWidgets('AlertDialog pelón toma fondo y forma del tema HOSPITAL (azul), no Material',
      (t) async {
    final hospital = BrandTokens.forCenterType(CenterType.hospital);
    final clinica = BrandTokens.forCenterType(CenterType.clinicaHeridas);

    await t.pumpWidget(MaterialApp(
      theme: KuraTheme.forType(CenterType.hospital),
      home: Scaffold(
        body: Builder(
          builder: (ctx) => Center(
            child: ElevatedButton(
              onPressed: () => showDialog<void>(
                context: ctx,
                builder: (_) => const AlertDialog(title: Text('Título')),
              ),
              child: const Text('abrir'),
            ),
          ),
        ),
      ),
    ));
    await t.tap(find.text('abrir'));
    await t.pumpAndSettle();

    // La superficie del diálogo: el primer Material dentro del Dialog.
    final material = t.widget<Material>(
      find.descendant(of: find.byType(Dialog), matching: find.byType(Material)).first,
    );

    // Fondo = surface del hospital, sin tinte.
    expect(material.color, hospital.surface, reason: 'el fondo no salió del token surface');
    expect(material.surfaceTintColor, Colors.transparent,
        reason: 'no debe haber tinte de elevación de Material 3');

    // Forma = borde del hospital (AZUL) + radio 16 (mdR), como las tarjetas — NO el radio
    // 28 por defecto de Material ni el borde morado de la clínica.
    final shape = material.shape as RoundedRectangleBorder;
    expect(shape.borderRadius, AppRadii.mdR, reason: 'radio ≠ 16 (mdR)');
    expect(shape.side.color, hospital.border, reason: 'el borde no salió del token del hospital');
    expect(shape.side.color, isNot(clinica.border),
        reason: 'el borde es del hospital (azul), no del morado de la clínica');
  });
}
