import 'package:flutter/material.dart';

import '../../core/design/tokens.dart';
import '../../engine/models/kura_engine_enums.dart';
import '../../models/patient.dart';
import 'patient_progress_status.dart';
import 'patient_wound_summary.dart';
import 'progress_status_indicator.dart';

/// Tile de paciente para la vista Lista de [PatientsListScreen] --
/// reutilizado tambien por [DashboardScreen] ("Pacientes recientes") para
/// mantener consistencia visual entre ambas pantallas (mismos chips de
/// etiologia y de conteo de heridas activas).
///
/// Las acciones rapidas ("Valoracion"/"Seguimiento") son OPCIONALES
/// (`onValoracion`/`onSeguimiento` nulos = se ocultan): Dashboard las omite
/// a proposito porque es solo una vista previa resumida, mientras que
/// PatientsListScreen si las pasa.
class PatientListTile extends StatelessWidget {
  final Patient patient;
  final PatientWoundSummary summary;
  // Semaforo de avance (peor trayectoria entre las heridas activas del
  // paciente, checkpoint de Sheehan). Requerido, igual que `summary`, para
  // que la señal siempre este presente y consistente entre Dashboard y
  // PatientsListScreen.
  final PatientProgressStatus progressStatus;
  final VoidCallback onTap;
  final VoidCallback? onValoracion;
  final VoidCallback? onSeguimiento;

  /// Superficie externa opcional. Por defecto (null) el tile usa un [Card],
  /// como en [PatientsListScreen]. El [DashboardScreen] pasa aqui un
  /// KuraGlassCard(blur: false) para el acabado "glass-lite" sin duplicar el
  /// contenido del tile. Recibe el contenido interno (InkWell) y devuelve la
  /// superficie que lo envuelve.
  final Widget Function(Widget child)? surfaceBuilder;

  const PatientListTile({
    super.key,
    required this.patient,
    required this.summary,
    required this.progressStatus,
    required this.onTap,
    this.onValoracion,
    this.onSeguimiento,
    this.surfaceBuilder,
  });

  @override
  Widget build(BuildContext context) {
    final activeWounds = summary.activeCount;
    final t = BrandTokens.of(context);
    final inner = InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              // Avatar en tono informativo (neutro), no en el acento de marca:
              // la identidad del paciente no es una acción.
              CircleAvatar(
                backgroundColor: t.info.withOpacity(0.12),
                child: Text(
                  patient.fullName.isNotEmpty ? patient.fullName[0] : '?',
                  style: TextStyle(color: t.info, fontWeight: FontWeight.w800),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(patient.fullName, style: const TextStyle(fontWeight: FontWeight.w600)),
                    Text(
                      '${patient.folio} · ${patient.age ?? '?'} años · ${patient.sex ?? '-'}',
                      style: TextStyle(fontSize: 12, color: t.textSecondary),
                    ),
                    const SizedBox(height: 6),
                    _EtiologyChipsRow(summary: summary),
                    const SizedBox(height: 6),
                    ProgressStatusIndicator(status: progressStatus),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Wrap(
                    spacing: 6,
                    children: [
                      if (patient.fragilePatient)
                        Tooltip(
                          message: 'Paciente frágil',
                          child: Icon(Icons.priority_high, color: t.statusWarning, size: 18),
                        ),
                      Chip(
                        label:
                            Text('$activeWounds herida${activeWounds == 1 ? '' : 's'}'),
                        backgroundColor: activeWounds > 0
                            ? t.info.withOpacity(0.10)
                            : t.border.withOpacity(0.35),
                      ),
                    ],
                  ),
                  if (onValoracion != null || onSeguimiento != null) ...[
                    const SizedBox(height: 4),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Acciones secundarias en tono informativo (no el
                        // acento de marca, reservado al CTA principal).
                        if (onValoracion != null)
                          IconButton(
                            tooltip: 'Valoración',
                            icon: const Icon(Icons.assignment_outlined, size: 20),
                            color: t.info,
                            onPressed: onValoracion,
                          ),
                        if (onSeguimiento != null)
                          IconButton(
                            tooltip: summary.hasActiveWounds
                                ? 'Seguimiento'
                                : 'Sin heridas activas para dar seguimiento',
                            icon: const Icon(Icons.show_chart, size: 20),
                            color: summary.hasActiveWounds
                                ? t.info
                                : t.textDisabled,
                            onPressed: summary.hasActiveWounds ? onSeguimiento : null,
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
    );
    return surfaceBuilder != null ? surfaceBuilder!(inner) : Card(child: inner);
  }
}

/// Chips de etiologia de las heridas ACTIVAS del paciente (punto 2 del
/// rediseno): "Pie diabético", "Vascular", etc. Si no hay heridas
/// activas, muestra el mensaje "Sin heridas activas" en vez de chips.
class _EtiologyChipsRow extends StatelessWidget {
  final PatientWoundSummary summary;
  const _EtiologyChipsRow({required this.summary});

  @override
  Widget build(BuildContext context) {
    final t = BrandTokens.of(context);
    if (summary.etiologies.isEmpty) {
      return Text(
        'Sin heridas activas',
        style: TextStyle(fontSize: 12, color: t.textDisabled),
      );
    }
    return Wrap(
      spacing: 6,
      runSpacing: 4,
      children: summary.etiologies
          .map((e) => Chip(
                label: Text(e.label, style: const TextStyle(fontSize: 11)),
                padding: EdgeInsets.zero,
                labelPadding: const EdgeInsets.symmetric(horizontal: 8),
                backgroundColor: t.info.withOpacity(0.1),
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ))
          .toList(),
    );
  }
}
