import 'package:flutter/material.dart';

/// Página PÚBLICA (sin sesión) a la que Stripe redirige al PACIENTE tras pagar
/// el link. No es parte de la app del personal: solo confirma el resultado.
class PaymentResultScreen extends StatelessWidget {
  final bool success;
  const PaymentResultScreen({super.key, required this.success});

  @override
  Widget build(BuildContext context) {
    final color = success ? const Color(0xFF1B8A5A) : const Color(0xFFB4232A);
    return Scaffold(
      backgroundColor: const Color(0xFFF6F5F8),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  success ? Icons.check_circle_rounded : Icons.cancel_rounded,
                  size: 72,
                  color: color,
                ),
                const SizedBox(height: 20),
                Text(
                  success ? '¡Gracias! Recibimos tu pago' : 'Pago no completado',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 10),
                Text(
                  success
                      ? 'Tu pago se procesó correctamente. Ya puedes cerrar esta '
                          'ventana. Tu clínica verá el pago reflejado.'
                      : 'El pago no se completó. Si fue un error, pide a tu clínica '
                          'que te reenvíe el link o inténtalo de nuevo.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 14, color: Colors.black.withValues(alpha: 0.6)),
                ),
                const SizedBox(height: 24),
                Text(
                  'Kura+',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: color.withValues(alpha: 0.9)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
