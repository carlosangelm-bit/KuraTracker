// Centro ACTIVO (decisión Carlos 17-sep-2026): la CAPACIDAD (premium*For) se
// pregunta sobre el centro ACTIVO, no el de ORIGEN. Estas pruebas clavan las tres
// propiedades que Carlos pidió:
//  1) NO-MASTER byte-idéntico: activeOrganizationId == sessionUser.organizationId,
//     IGNORANDO cualquier anulación (propiedad de seguridad).
//  2) La puerta (premiumInsumosFor) abre cuando el ACTIVO tiene el módulo aunque el
//     ORIGEN no — para master (vía anulación) y para no-master (activo==origen).
//  3) META-GUARD de fuente: falla si aparece un premium*For(sessionUser/user.organizationId)
//     nuevo — deben preguntar por el centro activo.
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:kuratracker/core/providers/active_organization_provider.dart';
import 'package:kuratracker/core/providers/session_provider.dart';
import 'package:kuratracker/models/app_user.dart';
import 'package:kuratracker/services/data_repository.dart';
import 'package:kuratracker/services/local_db/local_store.dart';

class _FakeSession extends SessionController {
  _FakeSession(AppUser user) {
    state = SessionState(user: user);
  }
}

AppUser _user(AppRole role, String org) => AppUser(
      id: 'u-${role.name}', role: role, fullName: 'X', email: 'x@y.test',
      organizationId: org,
    );

const _orgSin = 'org-sin-modulo'; // origen: SIN insumos
const _orgCon = 'org-con-modulo'; // seleccionado: CON insumos

Future<void> _seedInsumos(LocalStore store, String org) => store.upsert(
      Collections.orgEntitlements,
      {
        'id': '$org-insumos', 'organization_id': org, 'kind': 'module',
        'key': 'insumos', 'status': 'active', 'source': 'master',
      },
    );

ProviderContainer _container(AppUser user, {String? override}) => ProviderContainer(
      overrides: [
        sessionProvider.overrideWith((ref) => _FakeSession(user)),
        activeOrgOverrideProvider
            .overrideWith((ref) => ActiveOrgOverride.withValue(override)),
      ],
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('1 · NO-MASTER: activo == origen SIEMPRE, ignora la anulación (byte-idéntico)',
      () {
    // Anulación residual apuntando a otro centro: un no-master JAMÁS la aplica.
    final c = _container(_user(AppRole.admin, _orgSin), override: _orgCon);
    expect(c.read(activeOrganizationIdProvider), _orgSin,
        reason: 'no-master resuelve exactamente su centro de origen');
    c.dispose();
    // Y sin anulación, igual.
    final c2 = _container(_user(AppRole.clinico, _orgSin));
    expect(c2.read(activeOrganizationIdProvider), _orgSin);
    c2.dispose();
  });

  test('2 · MASTER: la anulación de /platform manda; sin ella, su origen', () {
    final c = _container(_user(AppRole.master, _orgSin), override: _orgCon);
    expect(c.read(activeOrganizationIdProvider), _orgCon,
        reason: 'master inspecciona el centro seleccionado');
    c.dispose();
    final c2 = _container(_user(AppRole.master, _orgSin));
    expect(c2.read(activeOrganizationIdProvider), _orgSin,
        reason: 'sin anulación, master cae a su origen');
    c2.dispose();
  });

  test('3 · la PUERTA abre sobre el centro ACTIVO aunque el origen no tenga el módulo, '
      'para AMBOS roles', () async {
    final store = await LocalStore.instance();
    final repo = await DataRepository.instance();
    await _seedInsumos(store, _orgCon); // solo _orgCon tiene insumos

    // MASTER: origen SIN, anulación CON → activo=CON → puerta ABRE.
    final master = _container(_user(AppRole.master, _orgSin), override: _orgCon);
    final masterActive = master.read(activeOrganizationIdProvider);
    expect(repo.premiumInsumosFor(masterActive), isTrue,
        reason: 'master: la capacidad se lee del centro activo (seleccionado)');
    master.dispose();

    // NO-MASTER: activo == origen; en el centro CON → ABRE; en el SIN → CIERRA.
    final adminEn = _container(_user(AppRole.admin, _orgCon), override: _orgCon);
    expect(repo.premiumInsumosFor(adminEn.read(activeOrganizationIdProvider)), isTrue,
        reason: 'admin en el centro con módulo: abre');
    adminEn.dispose();

    final adminFuera = _container(_user(AppRole.admin, _orgSin), override: _orgCon);
    expect(repo.premiumInsumosFor(adminFuera.read(activeOrganizationIdProvider)),
        isFalse,
        reason: 'admin en el centro SIN módulo: cierra (ignora la anulación)');
    adminFuera.dispose();
  });

  test('META-GUARD · ningún premium*For pregunta por el centro de ORIGEN '
      '(user/session.organizationId); deben usar el centro activo', () {
    final offenders = <String>[];
    // premiumXFor( <arg con user/session .organizationId> )
    final bad = RegExp(
      r'premium\w+For\(\s*(user\??\.|session\.user\??\.|sessionUser\??\.)organizationId',
    );
    for (final f in Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))) {
      final src = f.readAsStringSync();
      for (final m in bad.allMatches(src)) {
        final line = '\n'.allMatches(src.substring(0, m.start)).length + 1;
        offenders.add('${f.path}:$line');
      }
    }
    expect(offenders, isEmpty,
        reason: 'estos premium*For preguntan por el centro de ORIGEN; deben preguntar '
            'por el centro ACTIVO (activeOrganizationIdProvider):\n${offenders.join('\n')}');
  });
}
