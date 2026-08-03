import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/config/app_config.dart';
import '../../core/providers/session_provider.dart';
import '../../core/router/app_router.dart';
import '../../core/router/app_shell.dart' show kFloatingNavBarHeight;
import '../../core/theme/kura_theme.dart';
import '../../models/app_user.dart';
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
    final role = session.user?.role;
    if (role == null) return;
    String? pid;
    String? wid;
    final repo = ref.read(dataRepositoryProvider).valueOrNull;
    if (repo != null && (role == AppRole.clinico || role == AppRole.admin)) {
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
    }
    ref
        .read(tourProvider.notifier)
        .start(tourStepsFor(role, patientId: pid, woundId: wid));
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
      ],
    );
  }
}

class _TourLauncher extends StatelessWidget {
  final VoidCallback onTap;
  const _TourLauncher({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: KuraColors.primary,
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
              Icon(Icons.play_circle_outline, color: Colors.white, size: 18),
              SizedBox(width: 6),
              Text('Tour',
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
            child: Container(color: Colors.black.withOpacity(0.45)),
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
