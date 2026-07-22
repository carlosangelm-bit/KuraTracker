import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/theme/kura_theme.dart';
import '../../core/providers/session_provider.dart';
import '../../models/app_user.dart';
import '../../models/consultation.dart';

/// Encabezado rapido de consulta (fecha, sitio, tipo de visita) — luego
/// entra directo al flujo unificado de captura de herida (foto-primero).
/// Reduce friccion: 1 pantalla en lugar de encabezado + 3 pasos separados.
class ConsultationHubScreen extends ConsumerStatefulWidget {
  final String patientId;
  // Preseleccion del tipo de visita (rediseno de PatientsListScreen: el
  // boton rapido "Valoración" de la tarjeta/lista navega aqui). El default
  // ya es VisitType.valoracion, pero se acepta explicito via query param
  // para no depender solo del default si este cambia en el futuro.
  final VisitType initialVisitType;
  // Cita de la agenda que originó esta consulta (0035), formato
  // "acuity:<id>" | "manual:<uuid>". Se pasa cuando se entra desde la agenda
  // con "Iniciar consulta"; la consulta creada queda ligada a esa cita.
  final String? scheduledAppointmentRef;
  const ConsultationHubScreen({
    super.key,
    required this.patientId,
    this.initialVisitType = VisitType.valoracion,
    this.scheduledAppointmentRef,
  });

  @override
  ConsumerState<ConsultationHubScreen> createState() => _ConsultationHubScreenState();
}

class _ConsultationHubScreenState extends ConsumerState<ConsultationHubScreen> {
  DateTime _visitDate = DateTime.now();
  late VisitType _visitType = widget.initialVisitType;
  String? _siteId;
  bool _creating = false;

  @override
  Widget build(BuildContext context) {
    final repoAsync = ref.watch(dataRepositoryProvider);
    final session = ref.watch(sessionProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Nueva consulta')),
      body: repoAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, st) => Center(child: Text('Error: $e')),
        data: (repo) {
          final patient = repo.getPatient(widget.patientId);
          final sites = repo.listSites();
          _siteId ??= patient?.primarySiteId ?? (sites.isNotEmpty ? sites.first.id : null);

          if (patient == null) {
            return const Center(child: Text('Paciente no encontrado.'));
          }

          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Card(
                      color: KuraColors.chipBg,
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Row(
                          children: [
                            const Icon(Icons.person, color: KuraColors.primary),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(patient.fullName,
                                      style: const TextStyle(fontWeight: FontWeight.w700)),
                                  Text(patient.folio, style: const TextStyle(fontSize: 12)),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text('Datos de la consulta',
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.calendar_today, size: 16),
                      label: Text(DateFormat('dd/MM/yyyy').format(_visitDate)),
                      onPressed: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: _visitDate,
                          firstDate: DateTime(2020),
                          lastDate: DateTime.now().add(const Duration(days: 1)),
                        );
                        if (picked != null) setState(() => _visitDate = picked);
                      },
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: _siteId,
                      decoration: const InputDecoration(labelText: 'Sitio *'),
                      items: sites
                          .map((s) => DropdownMenuItem(value: s.id, child: Text(s.name)))
                          .toList(),
                      onChanged: (v) => setState(() => _siteId = v),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<VisitType>(
                      value: _visitType,
                      decoration: const InputDecoration(labelText: 'Tipo de visita *'),
                      items: VisitType.values
                          .map((v) => DropdownMenuItem(value: v, child: Text(v.label)))
                          .toList(),
                      onChanged: (v) => setState(() => _visitType = v ?? VisitType.valoracion),
                    ),
                    const SizedBox(height: 24),
                    FilledButton.icon(
                      icon: _creating
                          ? const SizedBox(
                              height: 16,
                              width: 16,
                              child:
                                  CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Icon(Icons.camera_alt_outlined),
                      label: Text(_creating ? 'Creando...' : 'Continuar: capturar herida'),
                      style: FilledButton.styleFrom(
                        backgroundColor: KuraColors.primary,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      onPressed: _creating || _siteId == null
                          ? null
                          : () async {
                              setState(() => _creating = true);
                              // Fix admin-clinico (ajuste obligatorio #3): el
                              // staffId de un admin ya se resuelve de forma
                              // perezosa en SessionController (login/restore,
                              // ver ensureAdminStaffId), por lo que a esta
                              // altura session.user.staffId deberia estar
                              // resuelto tanto para clinico como para admin.
                              // Si por algun motivo aun no lo esta (p.ej. fallo
                              // de red durante el aprovisionamiento), se
                              // reintenta aqui mismo en vez de bloquear
                              // silenciosamente el flujo.
                              var staffId = session.user?.staffId;
                              if (staffId == null && session.user?.role == AppRole.admin) {
                                staffId = await repo.ensureAdminStaffId(session.user!);
                              }
                              if (staffId == null) {
                                setState(() => _creating = false);
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                        'No se encontró personal sanitario vinculado a tu cuenta.',
                                      ),
                                    ),
                                  );
                                }
                                return;
                              }
                              final consultation = await repo.createConsultation(
                                patientId: widget.patientId,
                                staffId: staffId,
                                siteId: _siteId!,
                                visitType: _visitType,
                                visitDate: _visitDate,
                                isDraft: true,
                                // Liga la consulta a la cita de la agenda si se
                                // entró con "Iniciar consulta" (0035).
                                scheduledAppointmentRef:
                                    widget.scheduledAppointmentRef,
                              );
                              if (mounted) {
                                context.go(
                                  '/patients/${widget.patientId}/wound/new/capture?consultationId=${consultation.id}',
                                );
                              }
                            },
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Podrás guardar como borrador en cualquier momento de la captura.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 12,
                        color: KuraColors.darkText.withOpacity(0.5),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
