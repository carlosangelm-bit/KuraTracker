import 'package:flutter/material.dart';

import '../../core/theme/kura_theme.dart';
import '../../engine/models/kura_engine_enums.dart';
import '../../models/patient.dart';
import 'patient_wound_summary.dart';

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
  final VoidCallback onTap;
  final VoidCallback? onValoracion;
  final VoidCallback? onSeguimiento;

  const PatientListTile({
    super.key,
    required this.patient,
    required this.summary,
    required this.onTap,
    this.onValoracion,
    this.onSeguimiento,
  });

  @override
  Widget build(BuildContext context) {
    final activeWounds = summary.activeCount;
    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: KuraColors.primary.withOpacity(0.12),
                child: Text(
                  patient.fullName.isNotEmpty ? patient.fullName[0] : '?',
                  style:
                      const TextStyle(color: KuraColors.primary, fontWeight: FontWeight.w800),
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
                      style: TextStyle(fontSize: 12, color: KuraColors.darkText.withOpacity(0.6)),
                    ),
                    const SizedBox(height: 6),
                    _EtiologyChipsRow(summary: summary),
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
                        const Tooltip(
                          message: 'Paciente frágil',
                          child: Icon(Icons.priority_high, color: KuraColors.warning, size: 18),
                        ),
                      Chip(
                        label:
                            Text('$activeWounds herida${activeWounds == 1 ? '' : 's'}'),
                        backgroundColor: activeWounds > 0
                            ? KuraColors.primary.withOpacity(0.1)
                            : KuraColors.chipBg,
                      ),
                    ],
                  ),
                  if (onValoracion != null || onSeguimiento != null) ...[
                    const SizedBox(height: 4),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (onValoracion != null)
                          IconButton(
                            tooltip: 'Valoración',
                            icon: const Icon(Icons.assignment_outlined, size: 20),
                            color: KuraColors.primary,
                            onPressed: onValoracion,
                          ),
                        if (onSeguimiento != null)
                          IconButton(
                            tooltip: summary.hasActiveWounds
                                ? 'Seguimiento'
                                : 'Sin heridas activas para dar seguimiento',
                            icon: const Icon(Icons.show_chart, size: 20),
                            color: summary.hasActiveWounds
                                ? KuraColors.primary
                                : KuraColors.darkText.withOpacity(0.3),
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
      ),
    );
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
    if (summary.etiologies.isEmpty) {
      return Text(
        'Sin heridas activas',
        style: TextStyle(fontSize: 12, color: KuraColors.darkText.withOpacity(0.45)),
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
                backgroundColor: KuraColors.infoBlue.withOpacity(0.1),
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ))
          .toList(),
    );
  }
}
