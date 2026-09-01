import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/config/app_config.dart';
import '../../core/design/tokens.dart';
import '../../core/providers/session_provider.dart';
import '../../core/router/app_router.dart';
import '../../core/router/app_shell.dart' show kFloatingNavBarHeight;
import '../../core/theme/kura_theme.dart';
import '../../models/app_user.dart';
import '../support/support_chat_panel.dart';
import '../support/support_launcher.dart';
import 'tour_controller.dart';
import 'tour_steps.dart';

/// Envoltura de la app (via MaterialApp.builder) que renderiza el recorrido
/// guiado SOLO en la demo: navega por los flujos y muestra una tarjeta que
/// explica cada pantalla, con Anterior/Siguiente/Saltar. También ofrece un
/// botón “?” para (re)lanzarlo.
class TourScope extends ConsumerStatefulWidget {
  final Widget child;
  const TourScope({super.key, required this.child});

  @override
  ConsumerState<TourScope> createState() => _TourScopeState();
}

class _TourScopeState extends ConsumerState<TourScope> {
  bool get _isDemo => !AppConfig.isSupabaseConfigured;
  bool _autoStarted = false;

  Future<void> _maybeAutoStart() async {
    if (_autoStarted || !_isDemo) return;
    final session = ref.read(sessionProvider);
    if (!session.isAuthenticated) return; // esperar al login
    _autoStarted = true;
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool('demo_tour_seen_v1') == true) return; // ya lo vio
    await prefs.setBool('demo_tour_seen_v1', true);
    _startForRole();
  }

  void _startForRole() {
    final session = ref.read(sessionProvider);
    final user = session.user;
    final role = user?.role;
    if (user == null || role == null) return;
    String? pid;
    String? wid;
    String? cid;
    final repo = ref.read(dataRepositoryProvider).valueOrNull;
    // Capacidad positiva: el recorrido clínico se muestra a quien TIENE rol
    // clínico o admin (los roles suman; un {admin,clinico} entra) (punto 6 §2 A).
    if (repo != null && (user.hasRole(AppRole.clinico) || user.hasRole(AppRole.admin))) {
      final patients = repo.listAllPatients();
      for (final p in patients) {
        final wounds =
            repo.listWoundsForPatient(p.id).where((w) => w.isActive).toList();
        if (wounds.isNotEmpty) {
          pid = p.id;
          wid = wounds.first.id;
          break;
        }
      }
      if (pid == null && patients.isNotEmpty) pid = patients.first.id;
      // Consulta más reciente del paciente demo, para el paso "hasta el cobro".
      if (pid != null) {
        final consults = repo.listConsultationsForPatient(pid);
        if (consults.isNotEmpty) {
          consults.sort((a, b) => b.visitDate.compareTo(a.visitDate));
          cid = consults.first.id;
        }
      }
    }
    ref.read(tourProvider.notifier).start(
        tourStepsFor(role, patientId: pid, woundId: wid, consultationId: cid));
  }

  @override
  Widget build(BuildContext context) {
    final tour = ref.watch(tourProvider);

    // Navega a la ruta del paso actual cuando cambia.
    ref.listen<TourState>(tourProvider, (prev, next) {
      final route = next.current?.route;
      if (next.running && route != null && route != prev?.current?.route) {
        ref.read(routerProvider).go(route);
      }
    });

    // Auto-inicio (una vez) tras el login en la demo.
    if (_isDemo && !_autoStarted) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _maybeAutoStart());
    }

    final showLauncher = _isDemo &&
        !tour.running &&
        ref.watch(sessionProvider).isAuthenticated;

    // Botón flotante de AYUDA (asistente): solo en producción (el asistente vive
    // detrás de Supabase). Nunca coincide con el lanzador del Tour, que es de la
    // demo. Mismo anclaje bottom-left, elevado sobre la barra flotante. Se oculta
    // cuando el panel de chat está abierto.
    final chat = ref.watch(supportChatProvider);
    final showHelp = !_isDemo &&
        !tour.running &&
        !chat.open &&
        ref.watch(sessionProvider).isAuthenticated;

    return Stack(
      children: [
        widget.child,
        if (tour.running && tour.current != null)
          _TourOverlay(
            step: tour.current!,
            index: tour.index,
            total: tour.total,
            isFirst: tour.isFirst,
            isLast: tour.isLast,
            onPrev: () => ref.read(tourProvider.notifier).prev(),
            onNext: () => ref.read(tourProvider.notifier).next(),
            onSkip: () => ref.read(tourProvider.notifier).stop(),
          ),
        if (showLauncher)
          Positioned(
            // Bottom-LEFT y elevado sobre la barra flotante, para no empalmarse
            // con el FAB "Nuevo paciente" (bottom-right). En escritorio se
            // desplaza para librar el NavigationRail.
            left: MediaQuery.of(context).size.width >= 900 ? 88 : 16,
            bottom: MediaQuery.of(context).viewPadding.bottom +
                kFloatingNavBarHeight +
                12,
            child: _TourLauncher(onTap: _startForRole),
          ),
        if (showHelp)
          Positioned(
            left: MediaQuery.of(context).size.width >= 900 ? 88 : 16,
            bottom: MediaQuery.of(context).viewPadding.bottom +
                kFloatingNavBarHeight +
                12,
            child: _HelpLauncher(onTap: () => openSupportAssistant(ref)),
          ),
        // Panel de chat del asistente (overlay flotante, no ruta). Se mantiene
        // MONTADO mientras esté activo (Offstage al minimizar) para conservar la
        // conversación; al cerrar se desmonta y se descarta.
        if (!_isDemo && chat.active) _chatPanel(context, chat.open),
      ],
    );
  }

  /// Posiciona el panel de chat: en escritorio (≥900) un pop-up acotado abajo a
  /// la derecha; en móvil casi a pantalla completa con márgenes. Offstage cuando
  /// está minimizado (conserva el estado de la conversación).
  Widget _chatPanel(BuildContext context, bool open) {
    final mq = MediaQuery.of(context);
    final wide = mq.size.width >= 900;
    if (wide) {
      final h = (mq.size.height - 120).clamp(420.0, 640.0);
      return Positioned(
        right: 20,
        bottom: 20,
        width: 384,
        height: h,
        child: Offstage(offstage: !open, child: const _ChatOverlayHost()),
      );
    }
    return Positioned(
      left: 8,
      right: 8,
      top: mq.viewPadding.top + 8,
      bottom: mq.viewPadding.bottom + 8,
      child: Offstage(offstage: !open, child: const SupportChatPanel()),
    );
  }
}

/// El panel de chat vive en el `MaterialApp.builder` (por encima del Navigator),
/// donde NO hay un `Overlay` — y `TextField`/`Tooltip` lo necesitan. Se le da su
/// propio `Overlay` local. El Element persiste entre reconstrucciones (mismo tipo
/// en la misma posición), así que la conversación se conserva al minimizar.
class _ChatOverlayHost extends StatelessWidget {
  const _ChatOverlayHost();

  @override
  Widget build(BuildContext context) {
    return Overlay(
      initialEntries: [
        OverlayEntry(builder: (_) => const SupportChatPanel()),
      ],
    );
  }
}

/// Botón flotante que abre el asistente de ayuda (solo producción). Estilo pill,
/// color de marca del centro activo, para diferenciarlo del lanzador del Tour.
class _HelpLauncher extends StatelessWidget {
  final VoidCallback onTap;
  const _HelpLauncher({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final color = BrandTokens.of(context).brandPrimary;
    return Material(
      color: color,
      borderRadius: BorderRadius.circular(24),
      elevation: 4,
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: onTap,
        child: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.support_agent_outlined, color: Colors.white, size: 18),
              SizedBox(width: 6),
              Text('Ayuda',
                  style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 13)),
            ],
          ),
        ),
      ),
    );
  }
}

class _TourLauncher extends StatelessWidget {
  final VoidCallback onTap;
  const _TourLauncher({required this.onTap});

  @override
  Widget build(BuildContext context) {
    // Ícono circular compacto (antes pill "▶ Tour"): footprint mínimo para no
    // tapar el contenido bajo el anclaje bottom-left (celda 07:00 de la rejilla
    // del plan, rótulo "Largo (cm)" de la Fase 1). Opacidad en reposo para
    // dejar leer lo que quede detrás. Punto 3 auditoría 1-sep.
    return Opacity(
      opacity: 0.7,
      child: Material(
        color: KuraColors.primary,
        shape: const CircleBorder(),
        elevation: 4,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: const Padding(
            padding: EdgeInsets.all(11),
            child:
                Icon(Icons.play_circle_outline, color: Colors.white, size: 22),
          ),
        ),
      ),
    );
  }
}

class _TourOverlay extends StatelessWidget {
  final TourStep step;
  final int index;
  final int total;
  final bool isFirst;
  final bool isLast;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  final VoidCallback onSkip;

  const _TourOverlay({
    required this.step,
    required this.index,
    required this.total,
    required this.isFirst,
    required this.isLast,
    required this.onPrev,
    required this.onNext,
    required this.onSkip,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Scrim: atenúa la pantalla guiada y bloquea su interacción durante el
        // recorrido (el usuario avanza con los botones de la tarjeta).
        Positioned.fill(
          child: GestureDetector(
            onTap: () {},
            child: Container(color: Colors.black.withValues(alpha: 0.45)),
          ),
        ),
        Positioned(
          left: 16,
          right: 16,
          bottom: 24,
          child: SafeArea(
            child: Material(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              elevation: 8,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text('Paso ${index + 1} de $total',
                            style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: KuraColors.primary)),
                        const Spacer(),
                        TextButton(
                          onPressed: onSkip,
                          style: TextButton.styleFrom(
                              padding: EdgeInsets.zero,
                              minimumSize: const Size(0, 0),
                              tapTargetSize:
                                  MaterialTapTargetSize.shrinkWrap),
                          child: const Text('Saltar',
                              style: TextStyle(fontSize: 12)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(step.title,
                        style: const TextStyle(
                            fontWeight: FontWeight.w800, fontSize: 16)),
                    const SizedBox(height: 6),
                    Text(step.body,
                        style: const TextStyle(fontSize: 13, height: 1.4)),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        if (!isFirst)
                          OutlinedButton(
                            onPressed: onPrev,
                            child: const Text('Anterior'),
                          ),
                        const Spacer(),
                        FilledButton(
                          onPressed: onNext,
                          style: FilledButton.styleFrom(
                              backgroundColor: KuraColors.primary),
                          child: Text(isLast ? 'Terminar' : 'Siguiente'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
