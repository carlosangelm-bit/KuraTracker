import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/kura_theme.dart';
import '../../core/providers/session_provider.dart';
import '../../core/config/app_config.dart';
import '../../core/utils/caregiver_login.dart';
import '../../models/app_user.dart';

enum _LoginMode { personal, cuidador }

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
    if (mounted) context.go('/');
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

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider);
    final repoAsync = ref.watch(dataRepositoryProvider);

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
                                label: Text('Personal')),
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
