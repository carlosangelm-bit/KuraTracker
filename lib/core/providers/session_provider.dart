import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/app_user.dart';
import '../../services/data_repository.dart';
import '../../engine/cie10_catalog.dart';
import '../config/app_config.dart';

/// Estado de sesion. En modo Supabase (produccion), refleja
/// auth.currentUser + la fila de `profiles` correspondiente. En modo demo
/// local, es un estado simplificado sin backend de auth real.
class SessionState {
  final AppUser? user;
  final bool isLoading;

  const SessionState({this.user, this.isLoading = false});

  bool get isAuthenticated => user != null;
  bool get isAdmin => user?.role == AppRole.admin;
  bool get isMaster => user?.role == AppRole.master;

  SessionState copyWith({AppUser? user, bool? isLoading}) => SessionState(
        user: user ?? this.user,
        isLoading: isLoading ?? this.isLoading,
      );
}

class SessionController extends StateNotifier<SessionState> {
  SessionController() : super(const SessionState()) {
    if (AppConfig.isSupabaseConfigured) {
      _restoreSupabaseSession();
    }
  }

  /// Si Supabase ya tiene una sesion persistida (p.ej. tras refrescar la
  /// pagina en Flutter Web), la recupera sin pedir login de nuevo.
  Future<void> _restoreSupabaseSession() async {
    final authUser = Supabase.instance.client.auth.currentUser;
    if (authUser == null) return;
    state = state.copyWith(isLoading: true);
    try {
      final repo = await DataRepository.instance();
      await repo.hydrateAfterLogin();
      var user = repo.findUserByEmail(authUser.email ?? '');
      if (user != null && user.isActive) {
        user = await _ensureStaffIdForAdmin(repo, user);
        state = SessionState(user: user, isLoading: false);
        return;
      }
    } catch (_) {
      // Sesion invalida/expirada o perfil aun no disponible; se pedira
      // login manual.
    }
    state = state.copyWith(isLoading: false);
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
      await repo.hydrateAfterLogin();
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
        state = SessionState(user: user, isLoading: false);
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
      state = SessionState(user: user, isLoading: false);
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
      state = state.copyWith(user: refreshed);
    }
  }
}

final sessionProvider = StateNotifierProvider<SessionController, SessionState>(
  (ref) => SessionController(),
);

final dataRepositoryProvider = FutureProvider<DataRepository>((ref) {
  return DataRepository.instance();
});

/// Catálogo CIE-10 de heridas crónicas (asset empaquetado, reference data
/// estática). Se carga una vez y se cachea; lo consumen el picker y la
/// pantalla de diagnósticos del expediente.
final cie10CatalogProvider = FutureProvider<Cie10Catalog>((ref) {
  return Cie10Catalog.load();
});
