import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/design/tokens.dart';
import '../../core/providers/session_provider.dart';
import '../../core/router/app_shell.dart' show kFloatingNavBarHeight;
import '../../core/widgets/kura_glass_card.dart';
import '../../core/widgets/kura_primary_fab.dart';
import '../../engine/sheehan_decision_style.dart';
import '../../models/app_user.dart';
import '../../models/patient.dart';
import '../../services/data_repository.dart';
import '../patients/patient_list_tile.dart';
import '../patients/patient_progress_status.dart';
import '../patients/patient_wound_summary.dart';
import '../patients/patients_view_preferences.dart';
import '../patients/wound_picker_sheet.dart';

/// Pantalla de inicio como TABLERO DE TRIAGE: en vez de un resumen plano,
/// prioriza lo que necesita atencion (semaforo de trayectoria de Sheehan)
/// y ofrece las mismas acciones rapidas (Valoracion/Seguimiento) que la
/// lista de pacientes, para actuar sin dar rodeos.
///
/// No inventa datos: todo lo "pendiente" se deriva del semaforo de avance
/// ([PatientProgressStatus], checkpoint de Sheehan), NO de una cadencia o
/// calendario (que el modelo no tiene). Reutiliza los mismos componentes
/// que [PatientsListScreen] (tile, estatus, resumen, selector de herida,
/// preferencias de filtro) para no duplicar logica ni estilo.
class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  // Cuantos pacientes "recientes" (no urgentes) se muestran antes de
  // ofrecer "Ver todos": el tablero debe leerse en segundos, no ser la
  // lista completa (esa vive en /patients).
  static const int _recentLimit = 6;

  // Accion rapida "Valoracion": misma ruta y query que PatientsListScreen.
  void _goToValoracion(String patientId) {
    context.go('/patients/$patientId/consultation/new?visitType=valoracion');
  }

  // Accion rapida "Seguimiento": misma resolucion que PatientsListScreen
  // (directo si hay 1 herida activa, selector si hay varias, nada si no
  // hay heridas activas).
  Future<void> _goToSeguimiento(DataRepository repo, String patientId) async {
    final summary = PatientWoundSummary.compute(repo, patientId);
    if (!summary.hasActiveWounds) return;
    if (summary.activeCount == 1) {
      context.go('/patients/$patientId/wound/${summary.activeWounds.first.id}/follow-up');
      return;
    }
    final chosen = await showWoundPickerSheet(context, summary.activeWounds);
    if (chosen != null && mounted) {
      context.go('/patients/$patientId/wound/${chosen.id}/follow-up');
    }
  }

  // Abre la lista de pacientes ya filtrada por un estatus del semaforo,
  // reutilizando las preferencias persistidas que consume
  // PatientsListScreen (conserva la vista y el filtro de sitio del usuario;
  // solo cambia el filtro de trayectoria). `null` limpia ese filtro.
  Future<void> _openPatients({ProgressStatus? status}) async {
    final current = await PatientsViewPreferencesStore.load();
    await PatientsViewPreferencesStore.save(
      current.copyWith(progressStatuses: status == null ? const {} : {status}),
    );
    if (mounted) context.go('/patients');
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider);
    final repoAsync = ref.watch(dataRepositoryProvider);
    final user = session.user;
    final tokens = BrandTokens.of(context);

    return Scaffold(
      backgroundColor: tokens.background,
      // Fondo con color (degradado + blobs) para que el vidrio de las
      // tarjetas tenga algo que refractar detras.
      body: Stack(
        children: [
          const Positioned.fill(child: _DashboardBackground()),
          Positioned.fill(
            child: repoAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, st) => Center(child: Text('Error: $e')),
              data: (repo) {
          // Aislamiento por rol (igual que PatientsListScreen): clinico ve
          // sus pacientes; admin los del centro. El master no llega aqui
          // (va a /platform).
          final patients = user?.role == AppRole.admin
              ? repo.listAllPatients()
              : (user?.staffId != null
                  ? repo.listPatientsForStaff(user!.staffId!)
                  : <Patient>[]);

          // Un solo computo del semaforo por paciente, reutilizado por las
          // metricas y por ambas secciones.
          final triage = patients.map((p) {
            final summary = PatientWoundSummary.compute(repo, p.id);
            final progress = PatientProgressStatus.compute(repo, summary.activeWounds);
            return _Triage(patient: p, summary: summary, progress: progress);
          }).toList();

          final attention = triage
              .where((t) => t.worst == ProgressStatus.danger || t.worst == ProgressStatus.warning)
              .toList()
            ..sort((a, b) => _severityRank(a.worst).compareTo(_severityRank(b.worst)));
          final rest = triage
              .where((t) => t.worst == ProgressStatus.good || t.worst == ProgressStatus.noData)
              .toList();

          final activePatients = patients.where((p) => p.isActive).length;
          final activeWounds = triage.fold<int>(0, (n, t) => n + t.summary.activeCount);
          final dangerCount = triage.where((t) => t.worst == ProgressStatus.danger).length;

          return ListView(
            // Espacio inferior para que el ultimo elemento no quede tapado por
            // la barra de navegacion flotante (bar + margen + inset del sistema).
            padding: EdgeInsets.fromLTRB(
              16,
              20,
              16,
              MediaQuery.of(context).viewPadding.bottom + kFloatingNavBarHeight + 32,
            ),
            children: [
              Text(
                'Hola, ${user?.fullName.split(' ').first ?? ''} 👋',
                style: Theme.of(context)
                    .textTheme
                    .headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 4),
              Text(
                'Tu tablero de hoy · lo que necesita atención va primero',
                style: TextStyle(color: tokens.textSecondary),
              ),
              const SizedBox(height: 20),

              // Hero: resumen del día en banner oscuro (estilo mockup). El CTA
              // es una acción clínica real ("Requieren atención") — no una
              // "agenda del día" (el modelo no tiene cadencia/calendario).
              _HeroCard(
                activePatients: activePatients,
                activeWounds: activeWounds,
                dangerCount: dangerCount,
                onTapAttention: () => _openPatients(status: ProgressStatus.danger),
              ),
              const SizedBox(height: 28),

              if (patients.isEmpty)
                _EmptyDashboard(isAdmin: user?.role == AppRole.admin)
              else ...[
                // Seccion 1: requieren atencion (rojo + amarillo, peor primero).
                _SectionHeader(
                  icon: Icons.priority_high_rounded,
                  title: 'Requieren atención',
                  count: attention.length,
                  color: dangerCount > 0 ? tokens.statusDanger : tokens.statusWarning,
                ),
                const SizedBox(height: 12),
                if (attention.isEmpty)
                  const _AttentionEmpty()
                else
                  ...attention.map((t) => _tile(repo, t)),

                const SizedBox(height: 28),

                // Seccion 2: recientes (el resto: en meta o sin datos aun).
                _SectionHeader(
                  icon: Icons.people_alt_outlined,
                  title: 'Recientes',
                  count: rest.length,
                  // Sección neutra/informativa: NO usa el acento de marca
                  // (reservado a acciones).
                  color: tokens.info,
                ),
                const SizedBox(height: 12),
                if (rest.isEmpty)
                  Text(
                    'Nada más por ahora.',
                    style: TextStyle(color: tokens.textSecondary),
                  )
                else ...[
                  ...rest.take(_recentLimit).map((t) => _tile(repo, t)),
                  if (rest.length > _recentLimit)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: () => _openPatients(),
                        icon: const Icon(Icons.arrow_forward, size: 18),
                        label: Text('Ver todos los pacientes (${rest.length})'),
                      ),
                    ),
                ],
              ],
            ],
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: KuraPrimaryFab(
        onPressed: () => context.go('/patients/new'),
        icon: Icons.person_add,
        label: 'Nuevo paciente',
      ),
    );
  }

  // Tile reutilizado (mismo componente y acciones que PatientsListScreen),
  // con superficie "glass-lite": KuraGlassCard SIN BackdropFilter, para que
  // el scroll de la lista no cargue un blur real por fila (fluidez).
  Widget _tile(DataRepository repo, _Triage t) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: PatientListTile(
        patient: t.patient,
        summary: t.summary,
        progressStatus: t.progress,
        onTap: () => context.go('/patients/${t.patient.id}'),
        onValoracion: () => _goToValoracion(t.patient.id),
        onSeguimiento: () => _goToSeguimiento(repo, t.patient.id),
        surfaceBuilder: (child) => KuraGlassCard(
          blur: false,
          borderRadius: 18,
          padding: EdgeInsets.zero,
          child: child,
        ),
      ),
    );
  }

  // Prioridad "peor primero": rojo > amarillo (dentro de la seccion de
  // atencion).
  static int _severityRank(ProgressStatus s) {
    switch (s) {
      case ProgressStatus.danger:
        return 0;
      case ProgressStatus.warning:
        return 1;
      case ProgressStatus.good:
        return 2;
      case ProgressStatus.noData:
        return 3;
    }
  }
}

/// Paciente + su resumen de heridas + el peor estatus de trayectoria,
/// calculado una sola vez y compartido por metricas y secciones.
class _Triage {
  final Patient patient;
  final PatientWoundSummary summary;
  final PatientProgressStatus progress;

  const _Triage({required this.patient, required this.summary, required this.progress});

  ProgressStatus get worst => progress.worst;
}

/// Hero del dashboard: banner oscuro con degradado de marca y el resumen del
/// día (estilo mockup). El CTA es una acción clínica real (ir a "Requieren
/// atención"), no una "agenda del día".
class _HeroCard extends StatelessWidget {
  final int activePatients;
  final int activeWounds;
  final int dangerCount;
  final VoidCallback onTapAttention;

  const _HeroCard({
    required this.activePatients,
    required this.activeWounds,
    required this.dangerCount,
    required this.onTapAttention,
  });

  @override
  Widget build(BuildContext context) {
    final t = BrandTokens.of(context);
    // Tamaño de la ilustración proporcional al ancho del recuadro (≈ ancho de
    // pantalla menos el padding de la lista), para que mantenga la MISMA
    // proporción en móvil y escritorio (no se vea diminuta en pantallas anchas).
    final art =
        ((MediaQuery.of(context).size.width - 32) * 0.34).clamp(180.0, 320.0).toDouble();
    // Stack sin recorte: la ilustración 3D DESBORDA el recuadro morado,
    // sobresaliendo por arriba y un poco a la derecha.
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(AppSpacing.xl),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [t.heroTop, t.heroBottom],
            ),
            borderRadius: AppRadii.lgR,
            boxShadow: [
              BoxShadow(
                color: t.heroTop.withOpacity(0.35),
                blurRadius: 24,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: Padding(
            // Reserva a la derecha (proporcional al arte) para que el texto no
            // quede bajo la ilustración.
            padding: EdgeInsets.only(right: art * 0.72),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Hoy',
                  style: TextStyle(
                    color: t.onBrand.withOpacity(0.70),
                    fontSize: AppType.label,
                    fontWeight: AppType.semibold,
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                Row(
                  children: [
                    Expanded(
                      child: _HeroStat(
                        value: '$activePatients',
                        label: 'pacientes\nactivos',
                        color: t.onBrand,
                      ),
                    ),
                    _HeroDivider(color: t.onBrand.withOpacity(0.20)),
                    Expanded(
                      child: _HeroStat(
                        value: '$activeWounds',
                        label: 'heridas en\ntratamiento',
                        color: t.onBrand,
                      ),
                    ),
                    _HeroDivider(color: t.onBrand.withOpacity(0.20)),
                    Expanded(
                      child: _HeroStat(
                        value: '$dangerCount',
                        label: 'requieren\natención',
                        color: dangerCount > 0 ? const Color(0xFFFF7A90) : t.onBrand,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.lg),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Material(
                    color: t.onBrand,
                    borderRadius: AppRadii.pillR,
                    child: InkWell(
                      onTap: onTapAttention,
                      borderRadius: AppRadii.pillR,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.lg, vertical: AppSpacing.md),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.priority_high_rounded, size: 18, color: t.brandPrimary),
                            const SizedBox(width: AppSpacing.sm),
                            Text('Requieren atención',
                                style: TextStyle(
                                    color: t.brandPrimary, fontWeight: AppType.bold)),
                            const SizedBox(width: AppSpacing.xs),
                            Icon(Icons.chevron_right, size: 18, color: t.brandPrimary),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        Positioned(
          right: -art * 0.06,
          top: -art * 0.16,
          child: SizedBox(
            width: art,
            height: art,
            child: _HeroArt(fallbackColor: t.onBrand),
          ),
        ),
      ],
    );
  }
}

/// Ilustración 3D del hero. Usa el asset si existe; si aún no está, cae al
/// glifo decorativo (para no romper la pantalla).
class _HeroArt extends StatelessWidget {
  final Color fallbackColor;
  const _HeroArt({required this.fallbackColor});

  @override
  Widget build(BuildContext context) {
    // Llena la caja que le da el hero (tamaño proporcional al ancho).
    return Image.asset(
      'assets/images/hero_bandage.png',
      fit: BoxFit.contain,
      errorBuilder: (_, __, ___) => Center(child: _HeroGlyph(color: fallbackColor)),
    );
  }
}

class _HeroStat extends StatelessWidget {
  final String value;
  final String label;
  final Color color;
  const _HeroStat({required this.value, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(value,
            style: TextStyle(
                color: color, fontSize: AppType.display, fontWeight: AppType.extrabold)),
        Text(label,
            style: TextStyle(
                color: color.withOpacity(0.75), fontSize: AppType.caption, height: 1.1)),
      ],
    );
  }
}

class _HeroDivider extends StatelessWidget {
  final Color color;
  const _HeroDivider({required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 40,
      margin: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
      color: color,
    );
  }
}

/// Motivo decorativo del hero (evoca el apósito del mockup) construido con
/// formas translúcidas — sin assets ni paquetes.
class _HeroGlyph extends StatelessWidget {
  final Color color;
  const _HeroGlyph({required this.color});

  Widget _square(double size, double opacity) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: color.withOpacity(opacity),
          borderRadius: AppRadii.mdR,
          border: Border.all(color: color.withOpacity(0.20)),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 84,
      height: 84,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned(right: 10, top: 2, child: _square(52, 0.10)),
          Positioned(right: 0, bottom: 0, child: _square(64, 0.16)),
          Icon(Icons.healing, size: 34, color: color.withOpacity(0.92)),
        ],
      ),
    );
  }
}

/// Encabezado de seccion con icono acentuado y contador.
class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String title;
  final int count;
  final Color color;

  const _SectionHeader({
    required this.icon,
    required this.title,
    required this.count,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return KuraGlassCard(
      borderRadius: 18,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
      children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: color.withOpacity(0.16),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: color, size: 20),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            title,
            style: Theme.of(context)
                .textTheme
                .titleLarge
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
          decoration: BoxDecoration(
            color: color.withOpacity(0.12),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            '$count',
            style: TextStyle(fontWeight: FontWeight.w800, color: color),
          ),
        ),
      ],
      ),
    );
  }
}

/// Estado vacio POSITIVO de la seccion de atencion.
class _AttentionEmpty extends StatelessWidget {
  const _AttentionEmpty();

  @override
  Widget build(BuildContext context) {
    final t = BrandTokens.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.xl),
      decoration: BoxDecoration(
        color: t.statusSuccess.withOpacity(0.08),
        borderRadius: AppRadii.mdR,
        border: Border.all(color: t.statusSuccess.withOpacity(0.25)),
      ),
      child: Row(
        children: [
          Icon(Icons.check_circle, color: t.statusSuccess),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(
              'Sin pacientes que requieran atención por ahora ✅',
              style: TextStyle(fontWeight: FontWeight.w600, color: t.textPrimary),
            ),
          ),
        ],
      ),
    );
  }
}

/// Estado vacio cuando el usuario no tiene ningun paciente todavia.
class _EmptyDashboard extends StatelessWidget {
  final bool isAdmin;
  const _EmptyDashboard({required this.isAdmin});

  @override
  Widget build(BuildContext context) {
    final t = BrandTokens.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.xl),
      decoration: BoxDecoration(
        color: t.surface.withOpacity(0.5),
        borderRadius: AppRadii.mdR,
        border: Border.all(color: t.border),
      ),
      child: Column(
        children: [
          Icon(Icons.people_outline, size: 44, color: t.textDisabled),
          const SizedBox(height: AppSpacing.md),
          Text(
            isAdmin
                ? 'Aún no hay pacientes en el centro.'
                : 'Aún no tienes pacientes asignados.',
            textAlign: TextAlign.center,
            style: TextStyle(color: t.textSecondary),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Usa "Nuevo paciente" para registrar el primero.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: AppType.label, color: t.textDisabled),
          ),
        ],
      ),
    );
  }
}

/// Fondo del dashboard: un degradado crema muy sutil (con un toque del
/// acento Kura) mas 2-3 "blobs" de color difuso detras del contenido. Le da
/// algo que refractar al vidrio de las tarjetas sin saturar la pantalla.
/// Los blobs usan RadialGradient (bordes suaves, sin BackdropFilter) para
/// ser baratos de pintar; el Stack recorta lo que se sale de pantalla.
class _DashboardBackground extends StatelessWidget {
  const _DashboardBackground();

  @override
  Widget build(BuildContext context) {
    final t = BrandTokens.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            t.background,
            // "Un toque del acento Kura muy tenue" como ambiente (no acción).
            Color.alphaBlend(t.brandPrimary.withOpacity(0.05), t.background),
          ],
        ),
      ),
      // Blobs ambientales en tonos de marca/informativo (nunca colores de
      // estado clínico, que no son decorativos).
      child: Stack(
        children: [
          Positioned(top: -80, left: -60, child: _Blob(t.brandPrimary, 260, 0.08)),
          Positioned(top: 160, right: -90, child: _Blob(t.info, 300, 0.07)),
          Positioned(bottom: -70, left: -30, child: _Blob(t.info, 240, 0.05)),
        ],
      ),
    );
  }
}

class _Blob extends StatelessWidget {
  final Color color;
  final double size;
  final double opacity;

  const _Blob(this.color, this.size, this.opacity);

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [color.withOpacity(opacity), color.withOpacity(0)],
          ),
        ),
      ),
    );
  }
}
