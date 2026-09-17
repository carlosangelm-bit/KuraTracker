import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/app_user.dart';
import '../../models/center_type.dart';
import '../../models/module_key.dart';
import '../../models/user_center_membership.dart';
import '../../services/data_repository.dart';
import '../../engine/cie10_catalog.dart';
import '../../engine/risk/prevention_risk_engine.dart';
import '../../engine/risk/braden_scale.dart';
import '../../engine/risk/scale_applicability.dart';
import '../config/app_config.dart';
import 'active_organization_provider.dart';

/// Estado de sesion. En modo Supabase (produccion), refleja
/// auth.currentUser + la fila de `profiles` correspondiente. En modo demo
/// local, es un estado simplificado sin backend de auth real.
class SessionState {
  final AppUser? user;
  final bool isLoading;
  // Centros a los que el usuario puede entrar (0040). Alimenta el switcher del
  // ícono de apósitos. Vacío o de 1 elemento => no hay a dónde cambiar.
  final List<UserCenterMembership> memberships;
  // Tipo del centro ACTIVO (deriva de organizations.center_type del
  // organization_id del usuario). Determina la paleta (morado/azul/rosa).
  final CenterType activeCenterType;

  const SessionState({
    this.user,
    this.isLoading = false,
    this.memberships = const [],
    this.activeCenterType = CenterType.clinicaHeridas,
  });

  bool get isAuthenticated => user != null;
  // Delegan al getter de CONJUNTO de AppUser (effectiveRoles), NO al rol escalar:
  // comparar `user?.role == AppRole.x` es el acoplamiento al modelo viejo que se
  // rompe con roles combinados (un admin+clinico cuyo `role` escalar no es admin).
  // Hoy nadie los llamaba, pero `session.isAdmin` se lee como lo natural de
  // escribir; así, quien lo use mañana no reintroduce el bug.
  bool get isAdmin => user?.isAdmin ?? false;
  bool get isMaster => user?.isMaster ?? false;

  /// El usuario puede alternar de centro si tiene ≥2 membresías activas.
  bool get canSwitchCenter => memberships.length >= 2;

  SessionState copyWith({
    AppUser? user,
    bool? isLoading,
    List<UserCenterMembership>? memberships,
    CenterType? activeCenterType,
  }) =>
      SessionState(
        user: user ?? this.user,
        isLoading: isLoading ?? this.isLoading,
        memberships: memberships ?? this.memberships,
        activeCenterType: activeCenterType ?? this.activeCenterType,
      );
}

class SessionController extends StateNotifier<SessionState> {
  SessionController() : super(const SessionState()) {
    if (AppConfig.isSupabaseConfigured) {
      // Reintento: leer currentUser UNA sola vez perdía el arranque en frío si la
      // hidratación del perfil aún no había poblado la caché. Escuchar los eventos
      // de auth (tokenRefreshed / signedIn / initialSession posteriores) permite
      // re-resolver la sesión cuando el primer intento no encontró al usuario.
      _authSub = Supabase.instance.client.auth.onAuthStateChange.listen(_onAuthEvent);
      _restoreSupabaseSession();
    }
  }

  StreamSubscription<AuthState>? _authSub;
  // Evita restauraciones concurrentes (constructor + evento de auth simultáneos).
  bool _restoring = false;

  void _onAuthEvent(AuthState data) {
    // El logout lo gobierna logout(); no interferir.
    if (data.event == AuthChangeEvent.signedOut) return;
    // Solo reintenta si Supabase ya tiene usuario pero AÚN no resolvimos el AppUser
    // y no hay una restauración/login en curso (isLoading lo marca).
    final hasAuthUser = Supabase.instance.client.auth.currentUser != null;
    if (hasAuthUser && state.user == null && !state.isLoading && !_restoring) {
      _restoreSupabaseSession();
    }
  }

  @override
  void dispose() {
    _authSub?.cancel();
    super.dispose();
  }

  /// Si Supabase ya tiene una sesion persistida (p.ej. tras refrescar la
  /// pagina en Flutter Web), la recupera sin pedir login de nuevo.
  /// Construye el estado de sesión completo (usuario + membresías + tipo de
  /// centro activo) desde la cache ya hidratada. Centraliza la resolución del
  /// multi-centro para restore/login/refresh/switch.
  SessionState _buildSession(DataRepository repo, AppUser user) {
    final memberships =
        user.id.isEmpty ? const <UserCenterMembership>[] : repo.listMembershipsFor(user.id);
    return SessionState(
      user: user,
      isLoading: false,
      memberships: memberships,
      activeCenterType: repo.centerTypeFor(user.organizationId),
    );
  }

  Future<void> _restoreSupabaseSession() async {
    if (_restoring) return;
    _restoring = true;
    try {
      final authUser = Supabase.instance.client.auth.currentUser;
      // [SESSION-RELOAD] instrumentación temporal del defecto de recarga web. Traza
      // el tramo que Carlos señaló: currentUser (ya poblado tras setInitialSession),
      // la hidratación del perfil desde profiles (necesita red) y el veredicto. QUITAR
      // al cerrar session-reload-web.
      // identityHashCode diagnostica el DOBLE restore: si aparecen dos hash
      // distintos, hay dos SessionController (dos instancias del provider); si es
      // el mismo dos veces, la guarda _restoring no cerró. Instrumentación, no lógica.
      debugPrint('[SESSION-RELOAD] restore(ctrl#${identityHashCode(this)}): '
          'authUser=${authUser?.email} '
          'session=${Supabase.instance.client.auth.currentSession != null}');
      // Sin sesión: desenlace terminal RESUELTO (sin usuario). El router puede
      // decidir /login con confianza.
      if (authUser == null) {
        state = state.copyWith(isLoading: false);
        return;
      }
      state = state.copyWith(isLoading: true);
      try {
        final repo = await DataRepository.instance();
        await repo.hydrateAfterLogin();
        var user = repo.findUserByEmail(authUser.email ?? '');
        debugPrint('[SESSION-RELOAD] tras hydrate: perfiles=${repo.listUsers().length} '
            'match=${user != null} active=${user?.isActive}');
        if (user != null && user.isActive) {
          user = await _ensureStaffIdForAdmin(repo, user);
          state = _buildSession(repo, user);
          return;
        }
      } catch (e) {
        // Sesion invalida/expirada o perfil aun no disponible; se pedira
        // login manual. Si un evento de auth posterior trae la sesión,
        // _onAuthEvent reintenta.
        debugPrint('[SESSION-RELOAD] EXCEPCIÓN en restore: $e');
      }
      debugPrint('[SESSION-RELOAD] restore SIN usuario → isAuthenticated=false → /login');
      state = state.copyWith(isLoading: false);
    } finally {
      _restoring = false;
    }
  }

  /// Fix admin-clinico (ajuste obligatorio #3): si el usuario es admin y NO
  /// tiene staffId resuelto (p.ej. el admin del seed de demo, o cualquier
  /// admin creado antes de esta funcion / sin pasar por
  /// create_organization_with_admin en Supabase), le aprovisiona su fila de
  /// `staff` de forma perezosa aqui mismo -- una sola vez, de forma
  /// transparente -- para que ConsultationHubScreen/FollowUpCaptureScreen
  /// vean `session.user.staffId` ya resuelto y no necesiten bloquear el
  /// flujo ni conocer este detalle de aprovisionamiento.
  Future<AppUser> _ensureStaffIdForAdmin(DataRepository repo, AppUser user) async {
    if (user.role != AppRole.admin || user.staffId != null) return user;
    try {
      final staffId = await repo.ensureAdminStaffId(user);
      // force: se acaba de escribir la fila de staff; hay que refrescar para verla
      // (solo ocurre en admins SIN staffId, una vez; el caso común sale arriba).
      await repo.hydrateAfterLogin(force: true);
      return repo.findUserByEmail(user.email) ?? user.copyWith(staffId: staffId);
    } catch (_) {
      // Si el aprovisionamiento falla (p.ej. RLS/red), se continua sin
      // staffId: el admin simplemente no podra crear consultas hasta que
      // se resuelva, pero el resto de la sesion sigue siendo utilizable.
      return user;
    }
  }

  /// Login. En modo Supabase (produccion) valida email+password real
  /// contra Supabase Auth y luego resuelve el perfil (`profiles`) para
  /// obtener rol/nombre/premium/staff_id. En modo demo local, la
  /// contrasena no se valida (cualquier valor sirve).
  Future<bool> login(String email, String password) async {
    state = state.copyWith(isLoading: true);

    if (AppConfig.isSupabaseConfigured) {
      try {
        await Supabase.instance.client.auth.signInWithPassword(
          email: email,
          password: password,
        );
      } on AuthException catch (_) {
        state = state.copyWith(isLoading: false);
        return false;
      }

      final repo = await DataRepository.instance();
      await repo.hydrateAfterLogin();
      var user = repo.findUserByEmail(email);
      if (user != null && user.isActive) {
        user = await _ensureStaffIdForAdmin(repo, user);
        state = _buildSession(repo, user);
        return true;
      }
      // Autenticado en Supabase Auth pero sin perfil activo visible
      // (posible error de RLS/perfil no creado): cierra la sesion de auth
      // para no dejar un estado inconsistente.
      await Supabase.instance.client.auth.signOut();
      state = state.copyWith(isLoading: false);
      return false;
    }

    // Modo demo local (sin credenciales de Supabase configuradas).
    final repo = await DataRepository.instance();
    var user = repo.findUserByEmail(email);
    await Future.delayed(const Duration(milliseconds: 400));
    if (user != null && user.isActive) {
      user = await _ensureStaffIdForAdmin(repo, user);
      state = _buildSession(repo, user);
      return true;
    }
    state = state.copyWith(isLoading: false);
    return false;
  }

  Future<void> logout() async {
    if (AppConfig.isSupabaseConfigured) {
      await Supabase.instance.client.auth.signOut();
      final repo = await DataRepository.instance();
      repo.clearCacheOnLogout();
    }
    state = const SessionState();
  }

  Future<void> refreshUser() async {
    if (state.user == null) return;
    final repo = await DataRepository.instance();
    final refreshed = repo.findUserByEmail(state.user!.email);
    if (refreshed != null) {
      state = _buildSession(repo, refreshed);
    }
  }

  /// Cambia el centro ACTIVO del usuario (ícono de apósitos). Valida membresía
  /// vía el RPC set_active_center (Supabase) o actualiza el perfil en demo, y
  /// reconstruye la sesión → repinta la paleta y recomputa lo que dependa del
  /// centro. Devuelve false si falla (p.ej. sin membresía).
  Future<bool> switchCenter(String organizationId) async {
    final user = state.user;
    if (user == null) return false;
    if (user.organizationId == organizationId) return true;
    state = state.copyWith(isLoading: true);
    try {
      final repo = await DataRepository.instance();
      await repo.setActiveCenter(user.id, organizationId);
      final refreshed = repo.findUserByEmail(user.email) ?? user;
      state = _buildSession(repo, refreshed);
      return true;
    } catch (_) {
      state = state.copyWith(isLoading: false);
      return false;
    }
  }
}

final sessionProvider = StateNotifierProvider<SessionController, SessionState>(
  (ref) => SessionController(),
);

/// true cuando Supabase emitió el evento passwordRecovery (el usuario abrió el
/// enlace del correo de "restablecer contraseña"). El router lo usa para forzar
/// la navegación a /reset-password aunque la app no tenga sesión propia; la
/// pantalla lo limpia al terminar o cancelar.
final passwordRecoveryProvider = StateProvider<bool>((ref) => false);

final dataRepositoryProvider = FutureProvider<DataRepository>((ref) {
  return DataRepository.instance();
});

/// Tipo del centro ACTIVO. Lo observa el MaterialApp para elegir la paleta
/// (morado/azul/rosa) de forma reactiva al cambiar de centro.
final activeCenterTypeProvider = Provider<CenterType>((ref) {
  return ref.watch(sessionProvider).activeCenterType;
});

/// Conjunto de módulos habilitados para el usuario en su centro ACTIVO (Fase 2).
/// Lo consumen el shell (para el nav) y el router (para bloquear rutas de
/// módulos apagados). Se recomputa al cambiar de centro (watch sessionProvider).
/// Fallback seguro a los defaults del tipo de centro si el repo aún no cargó.
final enabledModulesProvider = Provider<Set<ModuleKey>>((ref) {
  final session = ref.watch(sessionProvider);
  final user = session.user;
  if (user == null) return const {};
  final repo = ref.watch(dataRepositoryProvider).valueOrNull;
  if (repo == null) {
    // Fallback SEGURO (Fase 1 §4): con el AND por licencia, mientras el repo (y
    // por tanto los derechos) no ha cargado, el conjunto es VACÍO. Es preferible
    // un nav vacío por un instante que mostrar un módulo sin derecho. Antes se
    // devolvían los defaults del tipo de centro.
    return const {};
  }
  return repo.enabledModules(
    organizationId: user.organizationId,
    siteId: repo.primarySiteIdForProfile(user.id),
    profileId: user.id,
  );
});

/// ¿Puede el usuario actual usar el Protocolo Kura+? Es el AND de:
/// - el add-on premium "Protocolo Kura+" comprado por el CENTRO (0049), y
/// - `premium_enabled` por USUARIO (a quién decide dárselo el centro).
/// El add-on se compra a nivel centro (licencia) y el centro asigna la
/// activación individual; sin el add-on del centro, la activación por usuario no
/// habilita nada (modelo de licencias, brief 31-ago-2026 §4). Antes era un OR,
/// que regalaba Kura+ a todo el centro o a cualquier usuario marcado — hueco de
/// ingresos. Se recomputa al cambiar de centro/usuario.
final kuraProtocolEnabledProvider = Provider<bool>((ref) {
  final user = ref.watch(sessionProvider).user;
  if (user == null) return false;
  final repo = ref.watch(dataRepositoryProvider).valueOrNull;
  // Capacidad sobre el centro ACTIVO (no el de origen). No-master → == origen.
  final centerHasAddon =
      repo?.premiumProtocoloKuraFor(ref.watch(activeOrganizationIdProvider)) ??
          false;
  return centerHasAddon && user.premiumEnabled;
});

/// Catálogo CIE-10 de heridas crónicas (asset empaquetado, reference data
/// estática). Se carga una vez y se cachea; lo consumen el picker y la
/// pantalla de diagnósticos del expediente.
final cie10CatalogProvider = FutureProvider<Cie10Catalog>((ref) {
  return Cie10Catalog.load();
});

/// Catálogo de reglas de prevención/riesgo (asset). Borrador PENDIENTE de
/// validación clínica de María. Lo consumen el tablero de riesgo y la ficha
/// de riesgo del expediente.
final preventionRulesProvider = FutureProvider<PreventionRulesCatalog>((ref) {
  return PreventionRulesCatalog.load();
});

/// Definición de la escala de Braden (asset). Alimenta el formulario por
/// subescalas de la ficha de riesgo.
final bradenScaleProvider = FutureProvider<BradenScale>((ref) {
  return BradenScale.load();
});

/// Motor de aplicabilidad de escalas (asset): a partir del triage + expediente
/// decide qué escalas debe realizar cada paciente. Borrador PENDIENTE de
/// validación clínica.
final scaleApplicabilityProvider =
    FutureProvider<ScaleApplicabilityCatalog>((ref) {
  return ScaleApplicabilityCatalog.load();
});
