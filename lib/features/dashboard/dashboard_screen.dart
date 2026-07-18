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
          final warningCount = triage.where((t) => t.worst == ProgressStatus.warning).length;

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

              // Metricas accionables.
              _MetricsGrid(
                activePatients: activePatients,
                activeWounds: activeWounds,
                dangerCount: dangerCount,
                warningCount: warningCount,
                onTapDanger: () => _openPatients(status: ProgressStatus.danger),
                onTapWarning: () => _openPatients(status: ProgressStatus.warning),
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

/// Fila de metricas accionables, responsiva (1-4 columnas segun el ancho).
class _MetricsGrid extends StatelessWidget {
  final int activePatients;
  final int activeWounds;
  final int dangerCount;
  final int warningCount;
  final VoidCallback onTapDanger;
  final VoidCallback onTapWarning;

  const _MetricsGrid({
    required this.activePatients,
    required this.activeWounds,
    required this.dangerCount,
    required this.warningCount,
    required this.onTapDanger,
    required this.onTapWarning,
  });

  @override
  Widget build(BuildContext context) {
    final t = BrandTokens.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final cols = w < 380
            ? 1
            : w < 640
                ? 2
                : w < 1000
                    ? 3
                    : 4;
        // -1px de margen para que el redondeo nunca fuerce un salto de linea.
        final itemW = (w - (cols - 1) * 12 - 1) / cols;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            // Métricas informativas en tonos calmados (neutro/azul); NO usan el
            // acento de marca. Las de estado clínico (rojo/ámbar) resaltan solas.
            _StatCard(
              width: itemW,
              icon: Icons.people,
              label: 'Pacientes activos',
              value: '$activePatients',
              color: t.textSecondary,
            ),
            _StatCard(
              width: itemW,
              icon: Icons.healing,
              label: 'Heridas en tratamiento',
              value: '$activeWounds',
              color: t.info,
            ),
            _StatCard(
              width: itemW,
              icon: Icons.report_gmailerrorred_rounded,
              label: 'Requieren atención',
              value: '$dangerCount',
              color: t.statusDanger,
              emphasize: dangerCount > 0,
              onTap: onTapDanger,
            ),
            _StatCard(
              width: itemW,
              icon: Icons.error_outline,
              label: 'Con reservas',
              value: '$warningCount',
              color: t.statusWarning,
              emphasize: warningCount > 0,
              onTap: onTapWarning,
            ),
          ],
        );
      },
    );
  }
}

class _StatCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;
  final double width;
  final VoidCallback? onTap;
  // Fondo/borde tintado cuando la metrica urgente tiene casos (>0), para
  // que salte a la vista sin recurrir solo al color.
  final bool emphasize;

  const _StatCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
    required this.width,
    this.onTap,
    this.emphasize = false,
  });

  @override
  Widget build(BuildContext context) {
    final t = BrandTokens.of(context);
    final content = Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(AppSpacing.sm),
            decoration: BoxDecoration(
              color: color.withOpacity(0.16),
              borderRadius: AppRadii.mdR,
            ),
            child: Icon(icon, color: color),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(value,
                    style: const TextStyle(
                        fontSize: AppType.headline, fontWeight: AppType.extrabold)),
                Text(label,
                    style: TextStyle(fontSize: AppType.label, color: t.textSecondary)),
              ],
            ),
          ),
          if (onTap != null)
            Icon(Icons.chevron_right, size: 18, color: t.textDisabled),
        ],
      ),
    );
    return SizedBox(
      width: width,
      child: KuraGlassCard(
        borderRadius: 20,
        padding: EdgeInsets.zero,
        // Tinte del vidrio cuando la metrica urgente tiene casos.
        tint: emphasize ? color : null,
        child: onTap == null
            ? content
            : InkWell(
                onTap: onTap,
                borderRadius: BorderRadius.circular(20),
                child: content,
              ),
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
