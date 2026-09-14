import 'package:flutter_test/flutter_test.dart';
import 'package:kuratracker/features/platform/derechos/center_license_data.dart';
import 'package:kuratracker/models/org_entitlement.dart';

OrgEntitlement _ent({required String source, String? grantType, String? reason}) =>
    OrgEntitlement(
      id: 'x',
      organizationId: 'o',
      kind: 'module',
      key: 'insumos',
      quantity: null,
      status: 'active',
      currentPeriodEnd: null,
      source: source,
      grantType: grantType,
      reason: reason,
      grantedBy: null,
      isPermanent: false,
    );

void main() {
  group('grantTypeLabel (corrección b): español, no el valor crudo', () {
    test('comercial → "Acuerdo comercial"', () {
      expect(grantTypeLabel('comercial'), 'Acuerdo comercial');
    });
    test('cortesia → "Cortesía" (con acento)', () {
      expect(grantTypeLabel('cortesia'), 'Cortesía');
    });
    test('null / desconocido → "—"', () {
      expect(grantTypeLabel(null), '—');
      expect(grantTypeLabel('otro'), '—');
    });
  });

  group('moduleReasonLine (corrección c): motivo entre comillas, solo a mano', () {
    test('fila a mano con motivo → lo renderiza entre comillas', () {
      expect(
        moduleReasonLine(_ent(source: 'master', reason: 'Cliente piloto del norte')),
        '"Cliente piloto del norte"',
      );
    });
    test('fila de Stripe → null (no muestra comillas vacías)', () {
      expect(moduleReasonLine(_ent(source: 'stripe', reason: null)), isNull);
    });
    test('a mano pero sin motivo real → null (no comillas vacías)', () {
      expect(moduleReasonLine(_ent(source: 'master', reason: '   ')), isNull);
      expect(moduleReasonLine(_ent(source: 'master', reason: null)), isNull);
    });
    test('sin fila → null', () {
      expect(moduleReasonLine(null), isNull);
    });
  });
}
