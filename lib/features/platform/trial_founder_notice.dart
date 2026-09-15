import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../services/data_repository.dart' show CreatedUser;

/// Envío del correo de "establece tu contraseña". Inyectable para pruebas; por defecto
/// usa el MISMO camino que Usuarios (users_screen.dart): resetPasswordForEmail. El
/// correo SÍ está configurado — la afirmación vieja de que no lo estaba era falsa.
typedef SetupEmailSender = Future<void> Function(String email);

Future<void> _realSetupEmailSender(String email) async {
  await Supabase.instance.client.auth.resetPasswordForEmail(
    email,
    redirectTo: kIsWeb ? Uri.base.origin : null,
  );
}

/// Resultado de avisar al fundador de un centro de prueba.
class TrialFounderNotice {
  final String email;
  final bool emailSent;
  /// Motivo REAL del fallo del envío (no una afirmación fija). Null si se envió.
  final String? error;
  /// Contraseña temporal, respaldo visible SOLO si el envío falló.
  final String? tempPassword;
  const TrialFounderNotice({
    required this.email,
    required this.emailSent,
    this.error,
    this.tempPassword,
  });
}

/// Al crear el fundador de un centro de prueba, se le envía el correo para que ponga su
/// propia contraseña —igual que Usuarios—, en vez de mostrar una temporal en pantalla y
/// afirmar que no hay otra vía. La temporal queda como respaldo SOLO si el envío falla,
/// con el motivo real.
Future<TrialFounderNotice> notifyTrialFounder(
  CreatedUser founder, {
  SetupEmailSender? send,
}) async {
  final sender = send ?? _realSetupEmailSender;
  try {
    await sender(founder.email);
    return TrialFounderNotice(email: founder.email, emailSent: true);
  } catch (e) {
    return TrialFounderNotice(
      email: founder.email,
      emailSent: false,
      error: e.toString().replaceFirst('Exception: ', ''),
      tempPassword: founder.tempPassword,
    );
  }
}
