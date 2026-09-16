import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/theme/kura_theme.dart';
import '../../core/providers/session_provider.dart';
import '../../core/config/app_config.dart';
import '../../core/utils/caregiver_login.dart';
import '../../models/app_user.dart';

enum _LoginMode { personal, cuidador }

/// Traduce el error que Supabase manda cuando el enlace de restablecimiento no sirve, a un
/// mensaje humano (o null si no hay error). Función PURA para poder probarla contra la URL real
/// de producción. Los params (`error`, `error_code`, `error_description`) llegan como query
/// string: a veces arriba en /login, a veces anidados dentro de `?from=` porque el redirect del
/// guard capturó la location original (/login?from=/?error=...). Se miran los DOS lugares.
/// NO diagnostica la causa de fondo (pedido dos veces / escáner de correo / expiración real);
/// solo DICE que el enlace no sirve para que la pantalla no quede muda.
String? authLinkErrorMessage(Map<String, String> query) {
  String? code = query['error_code'];
  String? err = query['error'];
  String? desc = query['error_description'];
  final from = query['from'];
  if (from != null && from.isNotEmpty) {
    final nested = Uri.tryParse(from);
    if (nested != null) {
      code ??= nested.queryParameters['error_code'];
      err ??= nested.queryParameters['error'];
      desc ??= nested.queryParameters['error_description'];
    }
  }
  if (code == null && err == null && desc == null) return null;
  if (code == 'otp_expired' || err == 'access_denied') {
    return 'El enlace de restablecimiento ya no es válido: caducó o ya se usó. '
        'Pide uno nuevo y ábrelo apenas llegue a tu correo.';
  }
  return desc ?? 'El enlace de acceso no es válido. Pide uno nuevo.';
}

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  // En modo demo local se precarga un correo de ejemplo y la contrasena es
  // decorativa (cualquier valor funciona). En modo Supabase (produccion)
  // ambos campos se dejan vacios y se valida la contrasena real.
  final _emailCtrl = TextEditingController(
    text: AppConfig.isSupabaseConfigured ? '' : 'ana.martinez@curamas.mx',
  );
  final _passCtrl = TextEditingController(
    text: AppConfig.isSupabaseConfigured ? '' : 'demo',
  );
  // Modo cuidador: teléfono + clave (sin correo).
  final _phoneCtrl = TextEditingController();
  final _claveCtrl = TextEditingController();
  _LoginMode _mode = _LoginMode.personal;
  String? _error;

  Future<void> _doLogin(String email, {String? password}) async {
    setState(() => _error = null);
    final ok = await ref
        .read(sessionProvider.notifier)
        .login(email, password ?? _passCtrl.text.trim());
    if (!ok) {
      setState(() => _error = AppConfig.isSupabaseConfigured
          ? 'Correo o contraseña incorrectos, o usuario inactivo.'
          : 'Usuario no encontrado o inactivo.');
      return;
    }
    if (!mounted) return;
    // Respeta el destino pretendido (?from=…) que el redirect guardó al mandarnos
    // aquí desde un enlace profundo; si no hay, al dashboard. El redirect reajusta
    // por rol (master→/platform, etc.) en la siguiente pasada.
    final from = GoRouterState.of(context).uri.queryParameters['from'];
    context.go(from != null && from.isNotEmpty && !from.startsWith('/login')
        ? from
        : '/');
  }

  /// Login del cuidador: teléfono → correo sintético + clave.
  Future<void> _doCaregiverLogin() async {
    final email = CaregiverLogin.syntheticEmail(_phoneCtrl.text.trim());
    if (email == null) {
      setState(() => _error = 'Teléfono inválido (mínimo 8 dígitos).');
      return;
    }
    await _doLogin(email, password: _claveCtrl.text);
  }

  /// Envía el correo de "restablecer contraseña" (Supabase). El enlace regresa
  /// a la app y dispara el flujo de /reset-password (ver app_router). Mensaje
  /// genérico por seguridad: no revela si el correo existe.
  Future<void> _forgotPassword() async {
    final ctrl = TextEditingController(text: _emailCtrl.text.trim());
    final email = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Restablecer contraseña'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
                'Te enviaremos un enlace a tu correo para crear una nueva '
                'contraseña.'),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              keyboardType: TextInputType.emailAddress,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Correo electrónico',
                prefixIcon: Icon(Icons.email_outlined),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
              child: const Text('Enviar')),
        ],
      ),
    );
    if (email == null || email.isEmpty || !mounted) return;
    try {
      await Supabase.instance.client.auth.resetPasswordForEmail(
        email,
        redirectTo: kIsWeb ? Uri.base.origin : null,
      );
    } catch (_) {
      // No se revela si el correo existe (seguridad): mismo mensaje siempre.
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
            'Si el correo está registrado, te enviamos un enlace para '
            'restablecer la contraseña.'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider);
    final repoAsync = ref.watch(dataRepositoryProvider);
    final linkError =
        authLinkErrorMessage(GoRouterState.of(context).uri.queryParameters);

    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: KuraColors.primary,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Icon(Icons.healing, color: Colors.white, size: 28),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      'KuraTracker',
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: KuraColors.darkText,
                          ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'Kura+ / CuraMás · Cuidado avanzado de heridas',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: KuraColors.darkText.withOpacity(0.6),
                      ),
                ),
                const SizedBox(height: 32),
                // §prod: el enlace de restablecimiento no sirvió (Supabase lo dijo por query
                // string). Se DICE, con la salida a la mano —pedir otro—, en vez de dejar el login
                // mudo como si el producto estuviera roto.
                if (linkError != null) ...[
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: KuraColors.warning.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: KuraColors.warning.withValues(alpha: 0.4)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(Icons.link_off,
                                size: 18, color: KuraColors.warning),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(linkError,
                                  style: const TextStyle(fontSize: 13)),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Align(
                          alignment: Alignment.centerRight,
                          child: FilledButton.tonalIcon(
                            icon: const Icon(Icons.mail_outline, size: 18),
                            label: const Text('Pedir otro enlace'),
                            onPressed: _forgotPassword,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text('Iniciar sesión',
                            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                  fontWeight: FontWeight.w700,
                                )),
                        const SizedBox(height: 16),
                        // Modo de acceso: personal (correo) o cuidador (teléfono).
                        SegmentedButton<_LoginMode>(
                          segments: const [
                            ButtonSegment(
                                value: _LoginMode.personal,
                                icon: Icon(Icons.badge_outlined),
                                label: Text('Profesional')),
                            ButtonSegment(
                                value: _LoginMode.cuidador,
                                icon: Icon(Icons.volunteer_activism_outlined),
                                label: Text('Cuidador')),
                          ],
                          selected: {_mode},
                          onSelectionChanged: (s) =>
                              setState(() { _mode = s.first; _error = null; }),
                        ),
                        const SizedBox(height: 16),
                        if (_mode == _LoginMode.personal) ...[
                          TextField(
                            controller: _emailCtrl,
                            decoration: const InputDecoration(
                              labelText: 'Correo electrónico',
                              prefixIcon: Icon(Icons.email_outlined),
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _passCtrl,
                            obscureText: true,
                            onSubmitted: (_) {
                              if (!session.isLoading) {
                                _doLogin(_emailCtrl.text.trim());
                              }
                            },
                            decoration: InputDecoration(
                              labelText: AppConfig.isSupabaseConfigured
                                  ? 'Contraseña'
                                  : 'Contraseña (demo, cualquier valor)',
                              prefixIcon: const Icon(Icons.lock_outline),
                            ),
                          ),
                        ] else ...[
                          TextField(
                            controller: _phoneCtrl,
                            keyboardType: TextInputType.phone,
                            decoration: const InputDecoration(
                              labelText: 'Teléfono',
                              prefixIcon: Icon(Icons.phone_outlined),
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _claveCtrl,
                            obscureText: true,
                            onSubmitted: (_) {
                              if (!session.isLoading) _doCaregiverLogin();
                            },
                            decoration: const InputDecoration(
                              labelText: 'Clave',
                              prefixIcon: Icon(Icons.lock_outline),
                            ),
                          ),
                        ],
                        if (_error != null) ...[
                          const SizedBox(height: 8),
                          Text(_error!, style: const TextStyle(color: KuraColors.danger)),
                        ],
                        const SizedBox(height: 20),
                        FilledButton(
                          onPressed: session.isLoading
                              ? null
                              : () => _mode == _LoginMode.personal
                                  ? _doLogin(_emailCtrl.text.trim())
                                  : _doCaregiverLogin(),
                          style: FilledButton.styleFrom(
                            backgroundColor: KuraColors.primary,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: session.isLoading
                              ? const SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Text('Entrar'),
                        ),
                        if (AppConfig.isSupabaseConfigured &&
                            _mode == _LoginMode.personal) ...[
                          const SizedBox(height: 4),
                          TextButton(
                            onPressed:
                                session.isLoading ? null : _forgotPassword,
                            child: const Text('¿Olvidaste tu contraseña?'),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                if (!AppConfig.isSupabaseConfigured)
                repoAsync.when(
                  data: (repo) {
                    final users = repo.listUsers();
                    return Card(
                      color: KuraColors.chipBg,
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Cuentas de demostración',
                              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                            ),
                            const SizedBox(height: 8),
                            ...users.map((u) => Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 4),
                                  child: InkWell(
                                    onTap: () {
                                      _emailCtrl.text = u.email;
                                      _doLogin(u.email);
                                    },
                                    child: Row(
                                      children: [
                                        Icon(
                                          u.role == AppRole.master
                                              ? Icons.hub_outlined
                                              : u.role == AppRole.admin
                                                  ? Icons.admin_panel_settings
                                                  : Icons.medical_services_outlined,
                                          size: 18,
                                          color: KuraColors.primary,
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            '${u.fullName} — ${u.role.label}${u.premiumEnabled ? " · Premium" : ""}',
                                            style: const TextStyle(fontSize: 13),
                                          ),
                                        ),
                                        Text(
                                          u.email,
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: KuraColors.darkText.withOpacity(0.5),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                )),
                          ],
                        ),
                      ),
                    );
                  },
                  loading: () => const CircularProgressIndicator(),
                  error: (e, st) => Text('Error: $e'),
                ),
                const SizedBox(height: 24),
                Text(
                  'Herramienta de apoyo a la decisión clínica. No sustituye el juicio del profesional de salud.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 11,
                    color: KuraColors.darkText.withOpacity(0.5),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
