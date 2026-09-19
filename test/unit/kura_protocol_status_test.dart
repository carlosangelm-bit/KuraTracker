// #2 (Carlos): premium_enabled deja de ser una trampa. kuraProtocolStatusProvider expone el
// MOTIVO —no solo un booleano— para que las pantallas digan por qué el Protocolo Kura+ está
// vacío en vez de desaparecer. Se clava la distinción clave: centro-pagó-pero-usuario-sin-premium
// (la trampa) vs centro-sin-add-on vs habilitado.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:kuratracker/core/providers/active_organization_provider.dart';
import 'package:kuratracker/core/providers/session_provider.dart';
import 'package:kuratracker/models/app_user.dart';
import 'package:kuratracker/services/data_repository.dart';
import 'package:kuratracker/services/local_db/local_store.dart';

class _FakeSession extends SessionController {
  _FakeSession(AppUser? user) {
    state = SessionState(user: user);
  }
}

AppUser _user(String org, {required bool premium}) => AppUser(
      id: 'u-$org-$premium', role: AppRole.clinico, fullName: 'X',
      email: 'x@y.test', organizationId: org, premiumEnabled: premium,
    );

const _orgCon = 'org-con-addon'; // seat:protocolo qty 1
const _orgSin = 'org-sin-addon'; // sin seat:protocolo

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<DataRepository> repoWithAddon() async {
    final repo = await DataRepository.instance();
    final store = await LocalStore.instance();
    // El centro _orgCon tiene el add-on (seat:protocolo con cupo); _orgSin no.
    await store.upsert(Collections.orgEntitlements, {
      'id': '$_orgCon-seat-protocolo', 'organization_id': _orgCon,
      'kind': 'seat', 'key': 'protocolo', 'quantity': 1,
      'status': 'active', 'source': 'master',
    });
    return repo;
  }

  Future<KuraProtocolStatus> statusFor(AppUser? user) async {
    final repo = await repoWithAddon();
    final c = ProviderContainer(overrides: [
      sessionProvider.overrideWith((ref) => _FakeSession(user)),
      dataRepositoryProvider.overrideWith((ref) => Future.value(repo)),
      activeOrgOverrideProvider
          .overrideWith((ref) => ActiveOrgOverride.withValue(null)),
    ]);
    addTearDown(c.dispose);
    await c.read(dataRepositoryProvider.future); // resuelve el repo (valueOrNull != null)
    return c.read(kuraProtocolStatusProvider);
  }

  test('centro con add-on + usuario premium → enabled', () async {
    expect(await statusFor(_user(_orgCon, premium: true)),
        KuraProtocolStatus.enabled);
  });

  test('LA TRAMPA: centro con add-on + usuario SIN premium → userMissingPremium', () async {
    expect(await statusFor(_user(_orgCon, premium: false)),
        KuraProtocolStatus.userMissingPremium);
  });

  test('centro SIN add-on → centerMissingAddon (aunque el usuario sea premium)', () async {
    expect(await statusFor(_user(_orgSin, premium: true)),
        KuraProtocolStatus.centerMissingAddon);
  });

  test('sin sesión → noUser', () async {
    expect(await statusFor(null), KuraProtocolStatus.noUser);
  });

  test('kuraProtocolEnabledProvider == (status enabled)', () async {
    final repo = await repoWithAddon();
    final c = ProviderContainer(overrides: [
      sessionProvider
          .overrideWith((ref) => _FakeSession(_user(_orgCon, premium: false))),
      dataRepositoryProvider.overrideWith((ref) => Future.value(repo)),
      activeOrgOverrideProvider
          .overrideWith((ref) => ActiveOrgOverride.withValue(null)),
    ]);
    addTearDown(c.dispose);
    await c.read(dataRepositoryProvider.future);
    // La trampa: enabled es false, pero el status DICE por qué (no es un vacío mudo).
    expect(c.read(kuraProtocolEnabledProvider), isFalse);
    expect(c.read(kuraProtocolStatusProvider),
        KuraProtocolStatus.userMissingPremium);
  });
}
