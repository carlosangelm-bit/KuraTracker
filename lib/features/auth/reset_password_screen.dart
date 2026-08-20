import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/theme/kura_theme.dart';
import '../../core/providers/session_provider.dart';

/// Pantalla de RESTABLECER CONTRASEÑA. Se abre cuando el usuario llega desde el
/// enlace del correo de recuperación de Supabase: el SDK ya dejó una sesión de
/// recuperación válida y emitió `passwordRecovery` (ver app_router). Aquí el
/// usuario escribe su nueva contraseña (`auth.updateUser`), se cierra la sesión
/// temporal y vuelve al login para entrar con la contraseña nueva.
class ResetPasswordScreen extends ConsumerStatefulWidget {
  const ResetPasswordScreen({super.key});

  @override
  ConsumerState<ResetPasswordScreen> createState() =>
      _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends ConsumerState<ResetPasswordScreen> {
  final _passCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  bool _saving = false;
  bool _done = false;
  String? _error;

  @override
  void dispose() {
    _passCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final pass = _passCtrl.text;
    if (pass.length < 8) {
      setState(() => _error = 'La contraseña debe tener al menos 8 caracteres.');
      return;
    }
    if (pass != _confirmCtrl.text) {
      setState(() => _error = 'Las contraseñas no coinciden.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await Supabase.instance.client.auth
          .updateUser(UserAttributes(password: pass));
    } on AuthException catch (e) {
      setState(() {
        _saving = false;
        _error = e.message;
      });
      return;
    } catch (_) {
      setState(() {
        _saving = false;
        _error = 'No se pudo actualizar la contraseña. Intenta de nuevo.';
      });
      return;
    }
    // Limpia el estado de recuperación y cierra la sesión temporal: el usuario
    // vuelve al login y entra con su nueva contraseña.
    ref.read(passwordRecoveryProvider.notifier).state = false;
    await Supabase.instance.client.auth.signOut();
    if (!mounted) return;
    setState(() {
      _saving = false;
      _done = true;
    });
  }

  void _backToLogin() {
    ref.read(passwordRecoveryProvider.notifier).state = false;
    context.go('/login');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: _done ? _successView() : _formView(),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _formView() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('Restablecer contraseña',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                )),
        const SizedBox(height: 4),
        Text('Escribe tu nueva contraseña.',
            style: TextStyle(
                color: KuraColors.darkText.withValues(alpha: 0.6),
                fontSize: 13)),
        const SizedBox(height: 20),
        TextField(
          controller: _passCtrl,
          obscureText: true,
          decoration: const InputDecoration(
            labelText: 'Nueva contraseña',
            prefixIcon: Icon(Icons.lock_outline),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _confirmCtrl,
          obscureText: true,
          onSubmitted: (_) {
            if (!_saving) _submit();
          },
          decoration: const InputDecoration(
            labelText: 'Confirmar contraseña',
            prefixIcon: Icon(Icons.lock_outline),
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 8),
          Text(_error!, style: const TextStyle(color: KuraColors.danger)),
        ],
        const SizedBox(height: 20),
        FilledButton(
          onPressed: _saving ? null : _submit,
          style: FilledButton.styleFrom(
            backgroundColor: KuraColors.primary,
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          child: _saving
              ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Text('Guardar contraseña'),
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: _saving ? null : _backToLogin,
          child: const Text('Cancelar'),
        ),
      ],
    );
  }

  Widget _successView() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.check_circle, color: KuraColors.primary, size: 48),
        const SizedBox(height: 12),
        Text('Contraseña actualizada',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                )),
        const SizedBox(height: 6),
        Text('Ya puedes iniciar sesión con tu nueva contraseña.',
            textAlign: TextAlign.center,
            style: TextStyle(
                color: KuraColors.darkText.withValues(alpha: 0.6),
                fontSize: 13)),
        const SizedBox(height: 20),
        FilledButton(
          onPressed: _backToLogin,
          style: FilledButton.styleFrom(
            backgroundColor: KuraColors.primary,
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          child: const Text('Ir a iniciar sesión'),
        ),
      ],
    );
  }
}
