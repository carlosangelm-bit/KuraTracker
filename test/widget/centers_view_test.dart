// Plataforma · Centros (§5.1), la vista responsiva. Local: centers_view es fonts-free.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:kuratracker/core/design/tokens.dart';
import 'package:kuratracker/core/widgets/dashed_border_box.dart';
import 'package:kuratracker/features/platform/centers_view.dart';
import 'package:kuratracker/features/platform/derechos/center_license_data.dart';
import 'package:kuratracker/features/platform/derechos/module_agreement.dart';
import 'package:kuratracker/services/data_repository.dart';

Widget _wrap(Widget child, {double width = 1200}) => MaterialApp(
      theme: ThemeData(extensions: <ThemeExtension<dynamic>>[BrandTokens.kura]),
      home: Scaffold(
        body: Center(child: SizedBox(width: width, height: 900, child: child)),
      ),
    );

ModuleLicenseRow _row(String key, bool hasRight) => ModuleLicenseRow(
      key: key,
      label: key,
      ent: null,
      hasRight: hasRight,
      hasSwitch: true,
      switchOn: !hasRight, // deliberadamente OPUESTO: la píldora sigue al derecho
      seatDerived: false,
      agreement: const ModuleAgreement(ModuleAgreementCase.normal, 'x'),
      amountCents: null,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('píldora rellena si hay derecho (aunque el interruptor esté opuesto)',
      (t) async {
    // hasRight=true, switchOn=false → RELLENA (sin contorno punteado).
    await t.pumpWidget(_wrap(CenterModulePills(rows: [_row('insumos', true)])));
    expect(find.byType(DashedBorderBox), findsNothing,
        reason: 'con derecho la píldora es rellena, no punteada');

    // hasRight=false, switchOn=true → PUNTEADA.
    await t.pumpWidget(_wrap(CenterModulePills(rows: [_row('insumos', false)])));
    expect(find.byType(DashedBorderBox), findsOneWidget,
        reason: 'sin derecho la píldora es punteada');
  });

  testWidgets('sin desbordamiento a 1000 y a 430 px', (t) async {
    final repo = await DataRepository.instance();
    final orgs = repo.listOrganizations();
    Widget view(double w) => _wrap(
          PlatformCentersView(
            repo: repo,
            organizations: orgs,
            selectedOrgId: orgs.isEmpty ? null : orgs.first.id,
            onSelect: (_) {},
            onChanged: () {},
            onMembers: (_) {},
          ),
          width: w,
        );
    for (final w in [1000.0, 430.0]) {
      await t.pumpWidget(view(w));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull, reason: 'desbordamiento a $w px');
    }
  });

  testWidgets('desactivar pide confirmación; cancelar no cambia nada', (t) async {
    final repo = await DataRepository.instance();
    final active = repo.listOrganizations().where((o) => o.isActive).toList();
    expect(active, isNotEmpty, reason: 'el demo debe tener centros activos');
    final target = active.first;

    await t.pumpWidget(_wrap(
      PlatformCentersView(
        repo: repo,
        organizations: [target], // un solo centro → un solo Switch
        selectedOrgId: target.id,
        onSelect: (_) {},
        onChanged: () {},
        onMembers: (_) {},
      ),
      width: 430,
    ));
    await t.pumpAndSettle();

    await t.tap(find.byType(Switch).first);
    await t.pumpAndSettle();
    expect(find.textContaining('¿Desactivar'), findsOneWidget,
        reason: 'apagar debe pedir confirmación que nombra el centro');

    await t.tap(find.text('Cancelar'));
    await t.pumpAndSettle();
    final after = repo.listOrganizations().firstWhere((o) => o.id == target.id);
    expect(after.isActive, isTrue, reason: 'cancelar no debe desactivar el centro');
  });
}
