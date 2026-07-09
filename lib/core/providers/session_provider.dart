import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/app_user.dart';
import '../../services/data_repository.dart';

/// Estado de sesion simplificado para la demo (sin backend de auth real).
/// En produccion, este provider se conecta a Supabase Auth
/// (supabase_flutter) y refleja auth.currentUser + profiles.
class SessionState {
  final AppUser? user;
  final bool isLoading;

  const SessionState({this.user, this.isLoading = false});

  bool get isAuthenticated => user != null;
  bool get isAdmin => user?.role == AppRole.admin;

  SessionState copyWith({AppUser? user, bool? isLoading}) => SessionState(
        user: user ?? this.user,
        isLoading: isLoading ?? this.isLoading,
      );
}

class SessionController extends StateNotifier<SessionState> {
  SessionController() : super(const SessionState());

  Future<bool> login(String email, String password) async {
    state = state.copyWith(isLoading: true);
    final repo = await DataRepository.instance();
    // Demo: password no se valida (cualquier valor sirve); en produccion
    // esto se delega a Supabase Auth (email+password, magic link, etc.)
    final user = repo.findUserByEmail(email);
    await Future.delayed(const Duration(milliseconds: 400));
    if (user != null && user.isActive) {
      state = SessionState(user: user, isLoading: false);
      return true;
    }
    state = state.copyWith(isLoading: false);
    return false;
  }

  void logout() {
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
