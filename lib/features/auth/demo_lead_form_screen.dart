import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/config/app_config.dart';
import '../../core/providers/session_provider.dart';
import '../../core/theme/kura_theme.dart';
import '../../services/demo/demo_lead_service.dart';
import 'demo_persona_screen.dart';

/// URL del aviso de privacidad. PENDIENTE de Carlos (Fase 3): mientras esté
/// vacía, la leyenda no ofrece enlace, solo el texto de consentimiento.
const String _avisoUrl = String.fromEnvironment('AVISO_URL', defaultValue: '');

/// Una opción del selector "¿con qué tipo de usuario te identificas?", en las
/// palabras del prospecto (§2), con el email del perfil demo al que entra.
class _UserTypeOption {
  final String label;
  final String personaEmail;
  final bool isOther;
  const _UserTypeOption(this.label, this.personaEmail, {this.isOther = false});
}

// MAPEO PROVISIONAL (§2), pendiente de confirmación de Carlos. "Otro" cae en el
// perfil principal (Especialista) porque es el que mejor muestra el producto.
const _userTypeOptions = <_UserTypeOption>[
  _UserTypeOption(
      'Atiendo heridas en una clínica o consultorio', DemoPersonaEmail.especialista),
  _UserTypeOption(
      'Trabajo por mi cuenta y soy mi propio centro', DemoPersonaEmail.independiente),
  _UserTypeOption('Dirijo o administro una clínica', DemoPersonaEmail.admin),
  _UserTypeOption('Soy de enfermería en un hospital', DemoPersonaEmail.enfermeria),
  _UserTypeOption(
      'Cuido a un familiar o paciente en casa', DemoPersonaEmail.cuidador),
  _UserTypeOption('Otro', DemoPersonaEmail.especialista, isOther: true),
];

/// Pantalla de captura previa a la demo. Toma nombre, apellido, correo, teléfono
/// (opcional) y el tipo de usuario, con consentimiento explícito. Al enviar:
/// captura el lead (lo reenvía a Bitrix por la portera, o lo encola si no hay
/// red) y entra DIRECTO al perfil mapeado, sin pasar por el selector.
class DemoLeadFormScreen extends ConsumerStatefulWidget {
  const DemoLeadFormScreen({super.key});

  @override
  ConsumerState<DemoLeadFormScreen> createState() => _DemoLeadFormScreenState();
}

class _DemoLeadFormScreenState extends ConsumerState<DemoLeadFormScreen> {
  final _firstName = TextEditingController();
  final _lastName = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _other = TextEditingController();
  final _honeypot = TextEditingController(); // trampa anti-bot (oculta)

  _UserTypeOption? _userType;
  bool _consent = false;
  bool _submitting = false;
  String? _error;

  static final _emailRe = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  @override
  void initState() {
    super.initState();
    for (final c in [_firstName, _lastName, _email, _other]) {
      c.addListener(() => setState(() {}));
    }
  }

  @override
  void dispose() {
    for (final c in [_firstName, _lastName, _email, _phone, _other, _honeypot]) {
      c.dispose();
    }
    super.dispose();
  }

  bool get _valid {
    if (_firstName.text.trim().isEmpty) return false;
    if (_lastName.text.trim().isEmpty) return false;
    if (!_emailRe.hasMatch(_email.text.trim())) return false;
    if (_userType == null) return false;
    if (_userType!.isOther && _other.text.trim().isEmpty) return false;
    if (!_consent) return false;
    return true;
  }

  Future<void> _submit() async {
    if (!_valid || _submitting) return;
    // Honeypot: un bot llena el campo oculto; una persona no. Si viene lleno, se
    // hace como que "entró" sin capturar nada, para no darle señal al bot.
    final isBot = _honeypot.text.isNotEmpty;

    setState(() {
      _submitting = true;
      _error = null;
    });

    final option = _userType!;
    if (!isBot) {
      final lead = DemoLead(
        firstName: _firstName.text.trim(),
        lastName: _lastName.text.trim(),
        email: _email.text.trim().toLowerCase(),
        phone: _phone.text.trim().isEmpty ? null : _phone.text.trim(),
        userType: option.label,
        otherText: option.isOther ? _other.text.trim() : null,
        event: AppConfig.demoEvent.isEmpty ? null : AppConfig.demoEvent,
        createdAt: DateTime.now().toUtc().toIso8601String(),
      );
      // capture() nunca lanza por red: envía con timeout y, si falla, encola.
      await DemoLeadService.capture(lead);
    }

    // Entra directo al perfil mapeado (la contraseña es decorativa en demo).
    final ok =
        await ref.read(sessionProvider.notifier).login(option.personaEmail, 'demo');
    if (!mounted) return;
    if (ok) {
      context.go('/');
    } else {
      setState(() {
        _submitting = false;
        _error = 'No se pudo abrir la demo. Recarga la página e inténtalo de nuevo.';
      });
    }
  }

  Future<void> _openAviso() async {
    if (_avisoUrl.isEmpty) return;
    final uri = Uri.tryParse(_avisoUrl);
    if (uri != null) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
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
                      child: const Icon(Icons.healing,
                          color: Colors.white, size: 28),
                    ),
                    const SizedBox(width: 12),
                    Text('KuraTracker',
                        style: Theme.of(context)
                            .textTheme
                            .headlineSmall
                            ?.copyWith(
                                fontWeight: FontWeight.w800,
                                color: KuraColors.darkText)),
                  ],
                ),
                const SizedBox(height: 16),
                Text('Conoce la demo',
                    textAlign: TextAlign.center,
                    style: Theme.of(context)
                        .textTheme
                        .titleLarge
                        ?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 6),
                Text(
                  'Déjanos tus datos y entra a recorrer KuraTracker con el perfil '
                  'que más se parece a ti.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 13,
                      color: KuraColors.darkText.withValues(alpha: 0.7)),
                ),
                const SizedBox(height: 20),
                _field(_firstName, 'Nombre', autofillHints: [AutofillHints.givenName]),
                const SizedBox(height: 12),
                _field(_lastName, 'Apellido',
                    autofillHints: [AutofillHints.familyName]),
                const SizedBox(height: 12),
                _field(_email, 'Correo electrónico',
                    keyboardType: TextInputType.emailAddress,
                    autofillHints: [AutofillHints.email]),
                const SizedBox(height: 12),
                _field(_phone, 'Teléfono (opcional)',
                    keyboardType: TextInputType.phone,
                    autofillHints: [AutofillHints.telephoneNumber]),
                const SizedBox(height: 12),
                DropdownButtonFormField<_UserTypeOption>(
                  value: _userType,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: '¿Con qué tipo de usuario te identificas?',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    for (final o in _userTypeOptions)
                      DropdownMenuItem(
                        value: o,
                        child: Text(o.label, overflow: TextOverflow.ellipsis),
                      ),
                  ],
                  onChanged: _submitting
                      ? null
                      : (v) => setState(() => _userType = v),
                ),
                if (_userType?.isOther ?? false) ...[
                  const SizedBox(height: 12),
                  _field(_other, '¿A qué te dedicas?'),
                ],
                // Trampa anti-bot: fuera de pantalla, sin foco por teclado.
                Offstage(
                  offstage: true,
                  child: TextField(
                    controller: _honeypot,
                    autofillHints: const [],
                    decoration:
                        const InputDecoration(labelText: 'No llenar'),
                  ),
                ),
                const SizedBox(height: 12),
                _consentRow(context),
                if (_error != null) ...[
                  const SizedBox(height: 10),
                  Text(_error!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: KuraColors.danger)),
                ],
                const SizedBox(height: 16),
                FilledButton(
                  style: FilledButton.styleFrom(
                      backgroundColor: KuraColors.primary,
                      padding: const EdgeInsets.symmetric(vertical: 14)),
                  onPressed: (_valid && !_submitting) ? _submit : null,
                  child: _submitting
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Text('Ver la demo'),
                ),
                const SizedBox(height: 8),
                TextButton.icon(
                  onPressed: _submitting ? null : () => context.go('/login'),
                  icon: const Icon(Icons.login, size: 18),
                  label: const Text('Prefiero iniciar sesión manualmente'),
                ),
                const SizedBox(height: 8),
                Text(
                  'Modo demostración · datos de ejemplo locales. Herramienta de '
                  'apoyo a la decisión clínica; no sustituye el juicio del '
                  'profesional de salud.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 11,
                      color: KuraColors.darkText.withValues(alpha: 0.5)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _field(TextEditingController c, String label,
      {TextInputType? keyboardType, List<String>? autofillHints}) {
    return TextField(
      controller: c,
      enabled: !_submitting,
      keyboardType: keyboardType,
      autofillHints: autofillHints,
      maxLength: 120,
      buildCounter: (_, {required currentLength, maxLength, required isFocused}) =>
          null,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
    );
  }

  Widget _consentRow(BuildContext context) {
    final linkStyle = TextStyle(
        color: KuraColors.primary,
        fontWeight: FontWeight.w600,
        decoration: TextDecoration.underline);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Checkbox(
          value: _consent,
          onChanged: _submitting
              ? null
              : (v) => setState(() => _consent = v ?? false),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text.rich(
              TextSpan(
                style: TextStyle(
                    fontSize: 12.5,
                    color: KuraColors.darkText.withValues(alpha: 0.8)),
                children: [
                  const TextSpan(
                      text:
                          'Al enviar, aceptas que Kuramas use tus datos para ponerse '
                          'en contacto contigo sobre KuraTracker.'),
                  if (_avisoUrl.isNotEmpty) ...[
                    const TextSpan(text: ' Consulta el '),
                    TextSpan(
                      text: 'aviso de privacidad',
                      style: linkStyle,
                      recognizer: TapGestureRecognizer()..onTap = _openAviso,
                    ),
                    const TextSpan(text: '.'),
                  ],
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
