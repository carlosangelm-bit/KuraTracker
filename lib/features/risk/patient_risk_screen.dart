import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/theme/kura_theme.dart';
import '../../core/providers/session_provider.dart';
import '../../engine/risk/prevention_risk_engine.dart';
import '../../models/app_user.dart';
import '../../models/patient_admission.dart';
import '../../services/data_repository.dart';
import 'risk_theme.dart';

/// Ficha de riesgo de un paciente (módulo de Prevención). Muestra el nivel de
/// riesgo, las alertas preventivas (LPP / complicación) con su recomendación,
/// la última valoración de Braden y el internamiento. Permite valorar riesgo
/// e ingresar/egresar. Capa DOCUMENTAL: no cambia el motor de tratamiento.
class PatientRiskScreen extends ConsumerStatefulWidget {
  final String patientId;
  const PatientRiskScreen({super.key, required this.patientId});

  @override
  ConsumerState<PatientRiskScreen> createState() => _PatientRiskScreenState();
}

class _PatientRiskScreenState extends ConsumerState<PatientRiskScreen> {
  final _dateFmt = DateFormat('dd/MM/yyyy HH:mm');

  Future<String?> _staffId(DataRepository repo) async {
    final session = ref.read(sessionProvider);
    var id = session.user?.staffId;
    if (id == null && session.user?.role == AppRole.admin) {
      id = await repo.ensureAdminStaffId(session.user!);
    }
    return id;
  }

  Future<void> _assessBraden(DataRepository repo) async {
    final ctrl = TextEditingController();
    final notesCtrl = TextEditingController();
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 4,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Valoración de riesgo (Braden)',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            const SizedBox(height: 4),
            Text('Escala 6–23. Menor puntaje = mayor riesgo de lesión por presión.',
                style: Theme.of(ctx).textTheme.bodySmall),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Puntaje de Braden (6–23)',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: notesCtrl,
              decoration: const InputDecoration(
                labelText: 'Notas (opcional)',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              maxLines: 2,
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: const Text('Guardar valoración'),
              ),
            ),
          ],
        ),
      ),
    );
    if (saved != true || !mounted) return;
    final braden = int.tryParse(ctrl.text.trim());
    if (braden == null || braden < 6 || braden > 23) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('El puntaje de Braden debe estar entre 6 y 23.')));
      }
      return;
    }
    final session = ref.read(sessionProvider);
    await repo.addRiskAssessment(
      patientId: widget.patientId,
      organizationId: session.user?.organizationId,
      bradenScore: braden,
      notes: notesCtrl.text.trim().isEmpty ? null : notesCtrl.text.trim(),
      staffId: await _staffId(repo),
    );
    if (mounted) setState(() {});
  }

  Future<void> _admit(DataRepository repo) async {
    final unitCtrl = TextEditingController();
    final bedCtrl = TextEditingController();
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 4,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Registrar internamiento',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            const SizedBox(height: 12),
            TextField(
              controller: unitCtrl,
              decoration: const InputDecoration(
                labelText: 'Unidad / servicio',
                hintText: 'Ej. Medicina Interna',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: bedCtrl,
              decoration: const InputDecoration(
                labelText: 'Cama (opcional)',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: const Text('Ingresar'),
              ),
            ),
          ],
        ),
      ),
    );
    if (ok != true || !mounted) return;
    final session = ref.read(sessionProvider);
    await repo.admitPatient(
      patientId: widget.patientId,
      organizationId: session.user?.organizationId,
      unit: unitCtrl.text.trim().isEmpty ? null : unitCtrl.text.trim(),
      bed: bedCtrl.text.trim().isEmpty ? null : bedCtrl.text.trim(),
    );
    if (mounted) setState(() {});
  }

  Future<void> _discharge(DataRepository repo, PatientAdmission a) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Egresar paciente'),
        content: const Text('¿Registrar el egreso de este internamiento?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Egresar')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await repo.dischargePatient(a.id);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final repoAsync = ref.watch(dataRepositoryProvider);
    final rulesAsync = ref.watch(preventionRulesProvider);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: 'Volver al paciente',
          onPressed: () => context.go('/patients/${widget.patientId}'),
        ),
        title: const Text('Prevención y riesgo'),
      ),
      body: repoAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, st) => Center(child: Text('Error: $e')),
        data: (repo) => rulesAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, st) => Center(child: Text('Error al cargar reglas: $e')),
          data: (catalog) {
            final patient = repo.getPatient(widget.patientId);
            if (patient == null) {
              return const Center(child: Text('Paciente no encontrado.'));
            }
            final result = repo.computeRisk(widget.patientId, catalog);
            final admission = repo.activeAdmission(widget.patientId);
            final braden = repo.latestRiskAssessment(widget.patientId);

            return ListView(
              padding: const EdgeInsets.all(20),
              children: [
                _RiskLevelBanner(level: result.level),
                const SizedBox(height: 16),
                _InfoTile(
                  icon: Icons.local_hotel_outlined,
                  title: 'Internamiento',
                  body: admission == null
                      ? 'No internado'
                      : '${admission.unit ?? 'Sin unidad'}'
                          '${admission.bed != null ? ' · Cama ${admission.bed}' : ''}'
                          '\nIngreso: ${_dateFmt.format(admission.admittedAt)}',
                  action: admission == null
                      ? TextButton(
                          onPressed: () => _admit(repo),
                          child: const Text('Ingresar'))
                      : TextButton(
                          onPressed: () => _discharge(repo, admission),
                          child: const Text('Egresar')),
                ),
                const SizedBox(height: 8),
                _InfoTile(
                  icon: Icons.monitor_heart_outlined,
                  title: 'Valoración de Braden',
                  body: braden?.bradenScore == null
                      ? 'Sin valoración registrada'
                      : 'Braden ${braden!.bradenScore} · ${_dateFmt.format(braden.assessedAt)}',
                  action: TextButton(
                    onPressed: () => _assessBraden(repo),
                    child: const Text('Valorar'),
                  ),
                ),
                const SizedBox(height: 20),
                if (!result.hasAlerts)
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: KuraColors.chipBg,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Text(
                        'Sin alertas preventivas con la información actual. '
                        'Captura la valoración de Braden y las comorbilidades '
                        'para una evaluación más completa.'),
                  )
                else ...[
                  if (result.lpp.isNotEmpty)
                    _AlertGroup(
                        title: 'Riesgo de lesión por presión', alerts: result.lpp),
                  if (result.complicacion.isNotEmpty)
                    _AlertGroup(
                        title: 'Riesgo de complicación',
                        alerts: result.complicacion),
                ],
                const SizedBox(height: 16),
                Text(
                  'Alertas de apoyo a la decisión (borrador clínico). No '
                  'sustituyen el juicio profesional ni modifican el plan de '
                  'tratamiento.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: KuraColors.darkText.withOpacity(0.6)),
                ),
                const SizedBox(height: 40),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _RiskLevelBanner extends StatelessWidget {
  final RiskLevel level;
  const _RiskLevelBanner({required this.level});

  @override
  Widget build(BuildContext context) {
    final color = riskLevelColor(level);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(14),
        border: Border(left: BorderSide(color: color, width: 4)),
      ),
      child: Row(
        children: [
          Icon(Icons.shield_outlined, color: color),
          const SizedBox(width: 12),
          Text(level.label,
              style: TextStyle(
                  fontWeight: FontWeight.w800, fontSize: 16, color: color)),
        ],
      ),
    );
  }
}

class _InfoTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;
  final Widget? action;
  const _InfoTile(
      {required this.icon,
      required this.title,
      required this.body,
      this.action});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: KuraColors.primary, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text(body, style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
            if (action != null) action!,
          ],
        ),
      ),
    );
  }
}

class _AlertGroup extends StatelessWidget {
  final String title;
  final List<PreventionAlert> alerts;
  const _AlertGroup({required this.title, required this.alerts});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 6),
          child: Text(title,
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
        ),
        ...alerts.map((a) {
          final color = riskSeverityColor(a.severity);
          return Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 3, right: 8),
                        child: Icon(Icons.warning_amber_rounded,
                            size: 16, color: color),
                      ),
                      Expanded(
                        child: Text(a.message,
                            style: const TextStyle(fontWeight: FontWeight.w600)),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: color.withOpacity(0.14),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(a.severity.label,
                            style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: color)),
                      ),
                    ],
                  ),
                  if (a.recommendation.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(a.recommendation,
                        style: Theme.of(context).textTheme.bodySmall),
                  ],
                ],
              ),
            ),
          );
        }),
      ],
    );
  }
}
