/// Login simplificado del cuidador: identificador = TELÉFONO (sin correo real).
///
/// Por debajo se usa un correo SINTÉTICO derivado del teléfono para autenticar
/// contra Supabase (email+password), pero el cuidador nunca ve ni necesita un
/// correo: entra con su teléfono + una clave que le comparte el centro.
///
/// El correo sintético debe ser DETERMINISTA (mismo teléfono → mismo correo) y
/// generarse igual al crear la cuenta (alta) y al iniciar sesión (login).
class CaregiverLogin {
  const CaregiverLogin._();

  /// Dominio de los correos sintéticos de cuidadores. No recibe correo real
  /// (la confirmación de correo está desactivada); solo sirve de identificador
  /// único e interno.
  static const String syntheticDomain = 'cuidador.kuramas.com';

  /// Normaliza un teléfono a solo dígitos (para que "55-1234-5678" y
  /// "5512345678" produzcan el mismo identificador).
  static String normalizePhone(String phone) =>
      phone.replaceAll(RegExp(r'\D'), '');

  /// Correo sintético determinista para un teléfono, o null si el teléfono no
  /// tiene dígitos suficientes (mínimo 8).
  static String? syntheticEmail(String phone) {
    final digits = normalizePhone(phone);
    if (digits.length < 8) return null;
    return '$digits@$syntheticDomain';
  }

  /// Longitud mínima de la clave (Supabase exige ≥6 para la contraseña).
  static const int minClaveLength = 6;
}
