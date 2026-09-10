import 'package:flutter_test/flutter_test.dart';
import 'package:kuratracker/models/license_summary.dart';

/// §10.4: hasProtocoloAddon era una tautología (`contracted >= 0`, siempre true
/// para un conteo finito) → la rama "Add-on no contratado" era código muerto y un
/// centro con seat:protocolo=0 se veía como si tuviera el add-on. Debe ser
/// `contracted > 0`: -1 (sin derecho) y 0 (derecho con 0 asientos) = NO tiene.
void main() {
  LicenseSummary withProtocolo(int contracted) => LicenseSummary(
        clinicalSeats: const LicenseCounter(used: 0, contracted: 3),
        adminSlots: const LicenseCounter(used: 0, contracted: 3),
        caregivers: 0,
        protocolo: LicenseCounter(used: 0, contracted: contracted),
        plan: 'basico',
        pastDue: false,
        patientsUsed: 0,
      );

  test('hasProtocoloAddon: >0 sí; 0 y -1 no', () {
    expect(withProtocolo(4).hasProtocoloAddon, isTrue);
    expect(withProtocolo(1).hasProtocoloAddon, isTrue);
    expect(withProtocolo(0).hasProtocoloAddon, isFalse); // derecho con 0 asientos
    expect(withProtocolo(-1).hasProtocoloAddon, isFalse); // sin derecho
  });
}
