import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/config/app_config.dart';
import '../../core/design/tokens.dart';
import '../../core/providers/session_provider.dart';
import '../../core/theme/kura_theme.dart';
import '../../models/center_type.dart';
import '../../services/data_repository.dart';

/// Capa PREVIA al login que solo se muestra en la DEMO (sin Supabase): el
/// visitante elige su perfil a partir de una explicación clara y entra con el
/// usuario de demostración que le corresponde. En producción (Supabase
/// configurado) no se usa; el router manda a /login.
class DemoPersonaScreen extends ConsumerStatefulWidget {
  const DemoPersonaScreen({super.key});

  @override
  ConsumerState<DemoPersonaScreen> createState() => _DemoPersonaScreenState();
}

class _Persona {
  final String title;
  final String email; // usuario demo sembrado (DemoSeed)
  final IconData icon;
  final CenterType? centerType; // null = plataforma (master)
  final String description;
  const _Persona({
    required this.title,
    required this.email,
    required this.icon,
    required this.centerType,
    required this.description,
  });

  Color get color => centerType != null
      ? BrandTokens.forCenterType(centerType!).brandPrimary
      : KuraColors.primary;
  String get contextLabel => centerType?.label ?? 'Plataforma';
}

const _personas = <_Persona>[
  _Persona(
    title: 'Kuradora / Médico',
    email: 'ana.martinez@curamas.mx',
    icon: Icons.medical_services_outlined,
    centerType: CenterType.clinicaHeridas,
    description:
        'Profesional clínico de una clínica de heridas. Valora heridas, corre '
        'el motor Kura+, registra el seguimiento en 5 fases y firma notas. Es '
        'el perfil principal del sistema.',
  ),
  _Persona(
    title: 'Profesional independiente',
    email: 'independiente@demo.kuramas.com',
    icon: Icons.medical_information_outlined,
    centerType: CenterType.clinicaHeridas,
    description:
        'Atiende por su cuenta y es su propio centro: administra y trata. '
        'Lleva el expediente completo de sus pacientes, corre el motor '
        'Protocolo Kura+ y sigue la evolución de cada herida con fotos y '
        'mediciones.',
  ),
  _Persona(
    title: 'Administrador de centro',
    email: 'admin@curamas.mx',
    icon: Icons.admin_panel_settings_outlined,
    centerType: CenterType.clinicaHeridas,
    description:
        'Gestiona su clínica: personal, sitios, catálogo de notas, módulos '
        'premium y precios de insumos. También puede capturar clínicamente.',
  ),
  _Persona(
    title: 'Enfermería (hospital)',
    email: 'enfermeria@hospital.mx',
    icon: Icons.local_hospital_outlined,
    centerType: CenterType.hospital,
    description:
        'Personal de enfermería hospitalaria. Prevención de LPP: escala de '
        'Braden, panel de riesgo, rondas y agenda de cuidados. Observa y '
        'ejecuta; no diagnostica ni cambia el protocolo.',
  ),
  _Persona(
    title: 'Cuidador',
    email: '5512345678@cuidador.kuramas.com',
    icon: Icons.volunteer_activism_outlined,
    centerType: CenterType.cuidadores,
    description:
        'Cuidador de un paciente en domicilio. Acceso reducido: solo sus '
        'pacientes asignados, las instrucciones del centro y su agenda de '
        'tareas.',
  ),
  // El perfil Master (plataforma) NO se expone en la demo: es de acceso interno
  // y solo se entra por el login real de producción con credenciales.
];

class _DemoPersonaScreenState extends ConsumerState<DemoPersonaScreen> {
  String? _loadingEmail; // email de la persona en la que se está entrando
  String? _error;

  Future<void> _enter(_Persona p) async {
    setState(() {
      _loadingEmail = p.email;
      _error = null;
    });
    // En demo la contraseña es decorativa (cualquier valor); el usuario se
    // resuelve por correo desde el seed local.
    final ok = await ref.read(sessionProvider.notifier).login(p.email, 'demo');
    if (!mounted) return;
    if (ok) {
      // El redirect del router enruta cada rol a su área (/, /platform,
      // /caregiver…).
      context.go('/');
    } else {
      setState(() {
        _loadingEmail = null;
        _error = 'No se pudo entrar como ${p.title}. Recarga la página e '
            'inténtalo de nuevo.';
      });
    }
  }

  /// Reinicia la demo a su estado sembrado: restaura los datos de ejemplo y
  /// limpia los filtros/vista persistidos (resetAndReseed ya llama a
  /// PatientsViewPreferencesStore.clear). Pensado para el stand: dejar el demo
  /// limpio entre un prospecto y el siguiente, sin arrastrar sus cambios ni sus
  /// filtros (que dejarían la pantalla de Pacientes en blanco al siguiente).
  Future<void> _resetDemo() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Reiniciar demo'),
        content: const Text(
            'Se borrarán los cambios de esta sesión de demostración y se '
            'restaurarán los datos de ejemplo.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(d, false),
              child: const Text('Cancelar')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: KuraColors.primary),
            onPressed: () => Navigator.pop(d, true),
            child: const Text('Reiniciar'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final repo = await DataRepository.instance();
    await repo.resetDemoData();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Demo reiniciada · datos de ejemplo restaurados.')));
  }

  @override
  Widget build(BuildContext context) {
    final busy = _loadingEmail != null;
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
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
                    Text(
                      'KuraTracker',
                      style: Theme.of(context)
                          .textTheme
                          .headlineSmall
                          ?.copyWith(
                              fontWeight: FontWeight.w800,
                              color: KuraColors.darkText),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  'Bienvenido a la demo · elige tu perfil',
                  textAlign: TextAlign.center,
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 6),
                Text(
                  'Cada perfil entra con un usuario de demostración distinto, '
                  'para que veas la app tal como la usa ese tipo de usuario.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 13,
                      color: KuraColors.darkText.withOpacity(0.7)),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: KuraColors.danger)),
                ],
                const SizedBox(height: 20),
                for (final p in _personas) ...[
                  _PersonaCard(
                    persona: p,
                    loading: _loadingEmail == p.email,
                    enabled: !busy,
                    onTap: () => _enter(p),
                  ),
                  const SizedBox(height: 12),
                ],
                const SizedBox(height: 4),
                TextButton.icon(
                  onPressed: busy ? null : () => context.go('/login'),
                  icon: const Icon(Icons.login, size: 18),
                  label: const Text('Prefiero iniciar sesión manualmente'),
                ),
                // Reiniciar la demo entre un prospecto y el siguiente: restaura
                // los datos y limpia los filtros, para que nadie herede la
                // sesión anterior (p. ej. un filtro que deja Pacientes vacío).
                TextButton.icon(
                  onPressed: busy ? null : _resetDemo,
                  icon: const Icon(Icons.refresh, size: 18),
                  style: TextButton.styleFrom(
                      foregroundColor: KuraColors.darkText.withOpacity(0.6)),
                  label: const Text('Reiniciar demo'),
                ),
                const SizedBox(height: 8),
                Text(
                  'Modo demostración · datos de ejemplo locales, sin conexión a '
                  'servidores. Herramienta de apoyo a la decisión clínica; no '
                  'sustituye el juicio del profesional de salud.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 11,
                      color: KuraColors.darkText.withOpacity(0.5)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PersonaCard extends StatelessWidget {
  final _Persona persona;
  final bool loading;
  final bool enabled;
  final VoidCallback onTap;
  const _PersonaCard({
    required this.persona,
    required this.loading,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = persona.color;
    return Opacity(
      opacity: enabled || loading ? 1 : 0.5,
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: enabled ? onTap : null,
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: color.withOpacity(0.3)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  radius: 22,
                  backgroundColor: color.withOpacity(0.12),
                  child: Icon(persona.icon, color: color),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(persona.title,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w700, fontSize: 15)),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: color.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(persona.contextLabel,
                                style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: color)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(persona.description,
                          style: TextStyle(
                              fontSize: 12.5,
                              height: 1.35,
                              color: KuraColors.darkText.withOpacity(0.8))),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          if (loading)
                            const SizedBox(
                                height: 16,
                                width: 16,
                                child: CircularProgressIndicator(strokeWidth: 2))
                          else
                            Icon(Icons.arrow_forward, size: 16, color: color),
                          const SizedBox(width: 6),
                          // Flexible + ellipsis: títulos largos (p. ej.
                          // "Profesional independiente") no desbordan la fila.
                          Flexible(
                            child: Text(
                                loading
                                    ? 'Entrando…'
                                    : 'Entrar como ${persona.title}',
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: color)),
                          ),
                        ],
                      ),
                    ],
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

/// True si la app corre en modo demo (sin Supabase). Expuesto para el router.
bool get isDemoMode => !AppConfig.isSupabaseConfigured;
