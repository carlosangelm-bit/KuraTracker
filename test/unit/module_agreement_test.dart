import 'package:flutter_test/flutter_test.dart';
import 'package:kuratracker/features/platform/derechos/module_agreement.dart';

/// Prueba 5 (§6), parte pura: los CUATRO casos derecho×interruptor. El que importa
/// es "encendido sin derecho", el caso silencioso que justifica el rediseño: exige
/// el texto rojo exacto "Encendido en el centro, pero sin derecho: nadie lo ve."
void main() {
  test('derecho + encendido → normal', () {
    final a = moduleAgreement(hasRight: true, switchOn: true);
    expect(a.kind, ModuleAgreementCase.normal);
  });

  test('derecho + apagado → aviso ámbar', () {
    final a = moduleAgreement(hasRight: true, switchOn: false);
    expect(a.kind, ModuleAgreementCase.rightOff);
    expect(a.message, 'Con derecho, apagado en el centro.');
  });

  test('SIN derecho + encendido → rojo, el caso silencioso', () {
    final a = moduleAgreement(hasRight: false, switchOn: true);
    expect(a.kind, ModuleAgreementCase.onWithoutRight);
    expect(a.message, 'Encendido en el centro, pero sin derecho: nadie lo ve.');
  });

  test('sin derecho + apagado → gris "Sin derecho"', () {
    final a = moduleAgreement(hasRight: false, switchOn: false);
    expect(a.kind, ModuleAgreementCase.noRight);
    expect(a.message, 'Sin derecho');
  });

  test('onWithoutRight acepta texto propio por fila (Clínico habla de asientos)', () {
    final a = moduleAgreement(
      hasRight: false,
      switchOn: true,
      onWithoutRightMessage: 'Con asientos activos pero sin el derecho clínico.',
    );
    expect(a.kind, ModuleAgreementCase.onWithoutRight);
    expect(a.message, 'Con asientos activos pero sin el derecho clínico.');
  });

  test('rightOff acepta texto propio por fila (simétrico a onWithoutRight)', () {
    final a = moduleAgreement(
      hasRight: true,
      switchOn: false,
      rightOffMessage: 'Sin asientos clínicos: nadie puede usar el expediente.',
    );
    expect(a.kind, ModuleAgreementCase.rightOff);
    expect(a.message, 'Sin asientos clínicos: nadie puede usar el expediente.');
  });
}
