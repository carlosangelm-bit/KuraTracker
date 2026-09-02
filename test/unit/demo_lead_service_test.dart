import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:kuratracker/services/demo/demo_lead_service.dart';

/// Fase 1 del formulario de captura: sin LEADS_ENDPOINT configurado (el default
/// en test), el envío siempre "falla" → todo lead se encola y la demo sigue.
/// Eso hace estos tests deterministas sin backend ni red.
void main() {
  DemoLead lead({String first = 'Ana', String? phone, String? other}) => DemoLead(
        firstName: first,
        lastName: 'García',
        email: 'ANA@x.com',
        phone: phone,
        userType: 'Atiendo heridas en una clínica o consultorio',
        otherText: other,
        createdAt: '2026-09-01T10:00:00Z',
      );

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('toJson lleva la fuente fija y omite campos vacíos', () {
    final j = lead().toJson();
    expect(j['source'], 'Demo KuraTracker');
    expect(j['first_name'], 'Ana');
    expect(j.containsKey('phone'), isFalse); // opcional, no dado
    expect(j.containsKey('other_text'), isFalse);

    final j2 = lead(phone: '5512345678', other: 'Investigación').toJson();
    expect(j2['phone'], '5512345678');
    expect(j2['other_text'], 'Investigación');
  });

  test('round-trip JSON del lead', () {
    final j = lead(phone: '55').toJson();
    final back = DemoLead.fromJson(j);
    expect(back.firstName, 'Ana');
    expect(back.phone, '55');
    expect(back.userType, 'Atiendo heridas en una clínica o consultorio');
  });

  test('capture: marca el lead, guarda el nombre y ENCOLA si no hay endpoint',
      () async {
    expect(await DemoLeadService.hasLead(), isFalse);
    await DemoLeadService.capture(lead(first: 'Rosa'));
    expect(await DemoLeadService.hasLead(), isTrue);
    expect(await DemoLeadService.firstName(), 'Rosa');
    expect(await DemoLeadService.pending(), 1); // no hay backend → encolado
  });

  test('clearActiveLead borra bandera y nombre pero NO la cola', () async {
    await DemoLeadService.capture(lead());
    expect(await DemoLeadService.pending(), 1);

    await DemoLeadService.clearActiveLead();
    expect(await DemoLeadService.hasLead(), isFalse);
    expect(await DemoLeadService.firstName(), isNull);
    // La cola de pendientes se conserva (§5.4): reiniciar no pierde leads.
    expect(await DemoLeadService.pending(), 1);
  });

  test('retryPending sin endpoint conserva los pendientes (no los pierde)',
      () async {
    await DemoLeadService.capture(lead());
    await DemoLeadService.capture(lead(first: 'Luis'));
    expect(await DemoLeadService.pending(), 2);

    await DemoLeadService.retryPending();
    expect(await DemoLeadService.pending(), 2); // siguen sin poderse enviar
  });
}
