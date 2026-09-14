import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:kuratracker/core/design/tokens.dart';
import 'package:kuratracker/core/widgets/kura_action_bar.dart';
import 'package:kuratracker/core/widgets/kura_data_table.dart';
import 'package:kuratracker/core/widgets/kura_empty_state.dart';
import 'package:kuratracker/core/widgets/kura_error_state.dart';
import 'package:kuratracker/core/widgets/kura_module_lock.dart';
import 'package:kuratracker/core/widgets/kura_stat.dart';
import 'package:kuratracker/services/data_repository.dart';

import 'kura_test_helpers.dart';

/// La prueba que atrapa un KuraColors olvidado: rinde los SEIS bajo
/// BrandTokens.hospital y verifica que ningún color resuelto es el morado de marca
/// #7C3AED. Si algo pintó el acento a mano en vez de leerlo del token, aparece aquí
/// aunque el tema sea hospital (azul).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  const kuraViolet = Color(0xFF7C3AED); // KuraPalette.brandPrimary

  testWidgets('los seis bajo hospital: ningún color resuelto es el morado Kura',
      (tester) async {
    final repo = await DataRepository.instance(); // billing_catalog sembrado

    final six = SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          KuraActionBar(
            searchHint: 'Buscar',
            primaryLabel: 'Nuevo',
            onPrimary: () {},
            moreActions: [KuraMenuAction(label: 'Otra', onSelected: () {})],
            filters: [
              KuraFilter(
                  label: 'Bajo umbral', count: 7, selected: true, onTap: () {}),
              KuraFilter(
                  label: 'Todos', count: 40, selected: false, onTap: () {}),
            ],
            showingText: 'Mostrando 12 de 40',
          ),
          const SizedBox(height: 12),
          const KuraStat(
              label: 'Valor', value: '38,420', unit: 'MXN', meaning: 'a costo'),
          const SizedBox(height: 12),
          const KuraStat(
              label: 'Agotados',
              value: '3',
              meaning: 'sin existencia',
              tone: KuraStatTone.danger),
          const SizedBox(height: 12),
          SizedBox(
            width: 700,
            child: KuraDataTable(
              selectable: true,
              columns: const [
                KuraColumn(label: 'Insumo', sortable: true),
                KuraColumn(label: 'Existencia', numeric: true, sortable: true),
              ],
              rows: [
                KuraRow(id: 'a', cells: [
                  KuraCell.identity(name: 'Gasa', identifier: 'SKU-1'),
                  KuraCell.number(0, unit: 'pz', status: KuraCellStatus.danger),
                ]),
                KuraRow(id: 'b', cells: [
                  KuraCell.identity(name: 'Apósito', identifier: 'SKU-2'),
                  KuraCell.number(24, unit: 'pz', status: KuraCellStatus.success),
                ]),
              ],
              totals: [
                KuraCell.pill('Total'),
                KuraCell.number(24, unit: 'pz'),
              ],
            ),
          ),
          const SizedBox(height: 12),
          KuraModuleLock.band(
            repo: repo,
            organizationId: 'brand-test-sin-modulo',
            moduleKey: 'insumos',
            moduleName: 'Insumos',
            description: 'Inventario, mapeo, consumo y reabasto.',
          ),
          const SizedBox(height: 12),
          KuraEmptyState(
            icon: Icons.inventory_2_outlined,
            title: 'Sin insumos',
            message: 'Agrega el primero.',
            primaryLabel: 'Agregar',
            onPrimary: () {},
          ),
          const SizedBox(height: 12),
          KuraErrorState(
            title: 'No pudimos cargar',
            reassurance: 'Tus datos están a salvo.',
            detail: 'Exception: boom',
            onRetry: () {},
          ),
        ],
      ),
    );

    await pumpBrand(tester, six, tokens: BrandTokens.hospital);

    final colors = collectColors(tester);
    expect(colors, isNotEmpty);
    expect(colors.contains(kuraViolet), isFalse,
        reason: 'un color resuelto es el morado Kura → hay un KuraColors/hex a mano');
    // Y el acento SÍ es el azul hospital en alguna parte (el tema se aplicó).
    expect(colors.contains(BrandTokens.hospital.brandPrimary), isTrue);
  });
}
