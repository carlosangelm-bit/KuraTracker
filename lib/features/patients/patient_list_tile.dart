import 'package:flutter/material.dart';

import '../../core/design/tokens.dart';
import '../../core/name_format.dart';
import '../../engine/models/kura_engine_enums.dart';
import '../../engine/risk/prevention_risk_engine.dart';
import '../../models/patient.dart';
import '../../models/patient_admission.dart';
import '../risk/risk_theme.dart';
import 'patient_progress_status.dart';
import 'patient_wound_summary.dart';
import 'progress_status_indicator.dart';

/// Señales de PREVENCIÓN de un paciente para el tile hospitalario: cuando el
/// paciente no tiene heridas activas, las etiquetas relevantes no son las de la
/// herida sino su nivel de riesgo (Braden), internamiento, comorbilidades y
/// diagnóstico principal.
class PatientHospitalInfo {
  final RiskLevel? riskLevel; // banda de Braden (null = sin valoración)
  final int? bradenScore;
  final PatientAdmission? admission;
  final List<String> comorbidities; // etiquetas de comorbilidades presentes
  final String? primaryDiagnosis; // nombre del diagnóstico principal, si hay
  const PatientHospitalInfo({
    this.riskLevel,
    this.bradenScore,
    this.admission,
    this.comorbidities = const [],
    this.primaryDiagnosis,
  });
}

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

  /// Señales de prevención (hospital). Cuando se proporcionan y el paciente NO
  /// tiene heridas activas, el tile muestra riesgo/internamiento/comorbilidades/
  /// diagnóstico en lugar de las etiquetas de herida (irrelevantes ahí).
  final PatientHospitalInfo? hospitalInfo;

  const PatientListTile({
    super.key,
    required this.patient,
    required this.summary,
    required this.progressStatus,
    required this.onTap,
    this.onValoracion,
    this.onSeguimiento,
    this.surfaceBuilder,
    this.hospitalInfo,
  });

  @override
  Widget build(BuildContext context) {
    final activeWounds = summary.activeCount;
    final t = BrandTokens.of(context);
    // En hospital las señales de PREVENCIÓN (Braden + internamiento/cama) y las
    // de HERIDA no son excluyentes: un paciente con LPP activa es el que más
    // riesgo tiene de una segunda lesión, así que necesita ver AMBAS. Antes era
    // un if/else que apagaba las señales de hospital al ganar herida.
    final isHospital = hospitalInfo != null;
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
                  avatarInitial(patient.fullName),
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
                    if (isHospital) ...[
                      // Prevención: riesgo (Braden) + internamiento/cama.
                      HospitalSignalsRow(info: hospitalInfo!),
                      // Aditivo: si además tiene herida activa, también etiología
                      // y avance (no se pierden al ganar herida).
                      if (summary.hasActiveWounds) ...[
                        const SizedBox(height: 6),
                        _EtiologyChipsRow(summary: summary),
                        const SizedBox(height: 6),
                        ProgressStatusIndicator(status: progressStatus),
                      ],
                    ] else ...[
                      _EtiologyChipsRow(summary: summary),
                      const SizedBox(height: 6),
                      ProgressStatusIndicator(status: progressStatus),
                    ],
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
                      // Braden visible en hospital SIEMPRE (con o sin herida).
                      if (isHospital) BradenBadge(info: hospitalInfo!),
                      // Conteo de heridas: fuera de hospital siempre; en hospital
                      // solo si hay heridas activas (evita "0 heridas" en
                      // pacientes de pura prevención).
                      if (!isHospital || activeWounds > 0)
                        Chip(
                          label: Text(
                              '$activeWounds herida${activeWounds == 1 ? '' : 's'}'),
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

/// Señales de PREVENCIÓN del tile hospitalario (paciente sin heridas activas):
/// nivel de riesgo (banda de Braden), internamiento, comorbilidades y dx.
class HospitalSignalsRow extends StatelessWidget {
  final PatientHospitalInfo info;
  const HospitalSignalsRow({super.key, required this.info});

  @override
  Widget build(BuildContext context) {
    final t = BrandTokens.of(context);
    final riskColor =
        info.riskLevel != null ? riskLevelColor(info.riskLevel!) : t.textDisabled;
    final riskLabel = info.riskLevel?.label ?? 'Sin valoración';
    final chips = <Widget>[
      _MiniInfoChip(label: riskLabel, color: riskColor, filled: true),
      if (info.admission?.locationLabel.isNotEmpty ?? false)
        _MiniInfoChip(
            label: info.admission!.locationLabel,
            color: t.info,
            icon: Icons.local_hotel_outlined),
      for (final c in info.comorbidities.take(2))
        _MiniInfoChip(label: c, color: t.textSecondary),
      if (info.comorbidities.length > 2)
        _MiniInfoChip(
            label: '+${info.comorbidities.length - 2}', color: t.textSecondary),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(spacing: 6, runSpacing: 4, children: chips),
        if (info.primaryDiagnosis != null) ...[
          const SizedBox(height: 4),
          Text('Dx: ${info.primaryDiagnosis}',
              style: TextStyle(fontSize: 11, color: t.textSecondary),
              maxLines: 1,
              overflow: TextOverflow.ellipsis),
        ],
      ],
    );
  }
}

/// Chip compacto reutilizable para las señales de prevención.
class _MiniInfoChip extends StatelessWidget {
  final String label;
  final Color color;
  final IconData? icon;
  final bool filled;
  const _MiniInfoChip({
    required this.label,
    required this.color,
    this.icon,
    this.filled = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(filled ? 0.14 : 0.08),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: color),
            const SizedBox(width: 3),
          ],
          Text(label,
              style: TextStyle(
                  fontSize: 11, fontWeight: FontWeight.w600, color: color)),
        ],
      ),
    );
  }
}

/// Insignia de la última valoración de Braden (score + color por banda).
class BradenBadge extends StatelessWidget {
  final PatientHospitalInfo info;
  const BradenBadge({super.key, required this.info});

  @override
  Widget build(BuildContext context) {
    final t = BrandTokens.of(context);
    if (info.bradenScore == null) {
      return _MiniInfoChip(label: 'Sin Braden', color: t.textDisabled);
    }
    final color = info.riskLevel != null
        ? riskLevelColor(info.riskLevel!)
        : t.textSecondary;
    return _MiniInfoChip(
        label: 'Braden ${info.bradenScore}', color: color, filled: true);
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
