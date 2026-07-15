import 'package:flutter/material.dart';

import '../../core/theme/kura_theme.dart';
import '../../engine/models/kura_engine_enums.dart';
import '../../models/patient.dart';
import 'patient_wound_summary.dart';

/// Tarjeta de paciente para la vista Tarjeta (GridView) de
/// [PatientsListScreen] (punto 3 del rediseno): nombre, folio, numero de
/// heridas activas, chips de etiologia, y dos acciones rapidas
/// ("Valoración"/"Seguimiento"). Tocar el resto de la tarjeta navega al
/// detalle del paciente.
class PatientGridCard extends StatelessWidget {
  final Patient patient;
  final PatientWoundSummary summary;
  final VoidCallback onTap;
  final VoidCallback onValoracion;
  final VoidCallback onSeguimiento;

  const PatientGridCard({
    super.key,
    required this.patient,
    required this.summary,
    required this.onTap,
    required this.onValoracion,
    required this.onSeguimiento,
  });

  @override
  Widget build(BuildContext context) {
    final activeWounds = summary.activeCount;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 20,
                    backgroundColor: KuraColors.primary.withOpacity(0.12),
                    child: Text(
                      patient.fullName.isNotEmpty ? patient.fullName[0] : '?',
                      style: const TextStyle(
                          color: KuraColors.primary, fontWeight: FontWeight.w800),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          patient.fullName,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          patient.folio,
                          style: TextStyle(
                              fontSize: 12, color: KuraColors.darkText.withOpacity(0.6)),
                        ),
                      ],
                    ),
                  ),
                  if (patient.fragilePatient)
                    const Tooltip(
                      message: 'Paciente frágil',
                      child: Icon(Icons.priority_high, color: KuraColors.warning, size: 18),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              Chip(
                label: Text('$activeWounds herida${activeWounds == 1 ? '' : 's'} activa${activeWounds == 1 ? '' : 's'}'),
                backgroundColor:
                    activeWounds > 0 ? KuraColors.primary.withOpacity(0.1) : KuraColors.chipBg,
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              const SizedBox(height: 8),
              Expanded(
                child: summary.etiologies.isEmpty
                    ? Text(
                        'Sin heridas activas',
                        style:
                            TextStyle(fontSize: 12, color: KuraColors.darkText.withOpacity(0.45)),
                      )
                    : Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: summary.etiologies
                            .map((e) => Chip(
                                  label: Text(e.label, style: const TextStyle(fontSize: 11)),
                                  backgroundColor: KuraColors.infoBlue.withOpacity(0.1),
                                  visualDensity: VisualDensity.compact,
                                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                  padding: EdgeInsets.zero,
                                  labelPadding: const EdgeInsets.symmetric(horizontal: 8),
                                ))
                            .toList(),
                      ),
              ),
              const Divider(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.assignment_outlined, size: 16),
                      label: const Text('Valoración'),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        textStyle: const TextStyle(fontSize: 12),
                      ),
                      onPressed: onValoracion,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Tooltip(
                      message: summary.hasActiveWounds
                          ? 'Registrar seguimiento'
                          : 'Sin heridas activas para dar seguimiento',
                      child: FilledButton.icon(
                        icon: const Icon(Icons.show_chart, size: 16),
                        label: const Text('Seguimiento'),
                        style: FilledButton.styleFrom(
                          backgroundColor: KuraColors.primary,
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          textStyle: const TextStyle(fontSize: 12),
                        ),
                        onPressed: summary.hasActiveWounds ? onSeguimiento : null,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
