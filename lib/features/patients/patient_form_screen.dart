import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/kura_theme.dart';
import '../../core/providers/session_provider.dart';

class PatientFormScreen extends ConsumerStatefulWidget {
  const PatientFormScreen({super.key});

  @override
  ConsumerState<PatientFormScreen> createState() => _PatientFormScreenState();
}

class _PatientFormScreenState extends ConsumerState<PatientFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _caregiverNameCtrl = TextEditingController();
  final _caregiverPhoneCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  DateTime? _birthDate;
  String _sex = 'F';
  String _mobility = 'ambulatorio';
  bool _hasCaregiver = false;
  bool _fragile = false;
  String? _siteId;
  bool _saving = false;

  @override
  Widget build(BuildContext context) {
    final repoAsync = ref.watch(dataRepositoryProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Nuevo paciente')),
      body: repoAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, st) => Center(child: Text('Error: $e')),
        data: (repo) {
          final sites = repo.listSites();
          _siteId ??= sites.isNotEmpty ? sites.first.id : null;

          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 600),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text('Datos generales',
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _nameCtrl,
                        decoration: const InputDecoration(labelText: 'Nombre completo *'),
                        validator: (v) =>
                            (v == null || v.trim().isEmpty) ? 'Requerido' : null,
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              icon: const Icon(Icons.calendar_today, size: 16),
                              label: Text(_birthDate == null
                                  ? 'Fecha de nacimiento'
                                  : '${_birthDate!.day}/${_birthDate!.month}/${_birthDate!.year}'),
                              onPressed: () async {
                                final picked = await showDatePicker(
                                  context: context,
                                  initialDate: DateTime(1970, 1, 1),
                                  firstDate: DateTime(1900),
                                  lastDate: DateTime.now(),
                                );
                                if (picked != null) setState(() => _birthDate = picked);
                              },
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              value: _sex,
                              decoration: const InputDecoration(labelText: 'Sexo'),
                              items: const [
                                DropdownMenuItem(value: 'F', child: Text('Femenino')),
                                DropdownMenuItem(value: 'M', child: Text('Masculino')),
                                DropdownMenuItem(value: 'otro', child: Text('Otro')),
                              ],
                              onChanged: (v) => setState(() => _sex = v ?? 'F'),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        value: _siteId,
                        decoration: const InputDecoration(labelText: 'Sitio principal'),
                        items: sites
                            .map((s) => DropdownMenuItem(value: s.id, child: Text(s.name)))
                            .toList(),
                        onChanged: (v) => setState(() => _siteId = v),
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        value: _mobility,
                        decoration: const InputDecoration(labelText: 'Movilidad'),
                        items: const [
                          DropdownMenuItem(value: 'ambulatorio', child: Text('Ambulatorio')),
                          DropdownMenuItem(
                              value: 'silla_ruedas', child: Text('Silla de ruedas')),
                          DropdownMenuItem(value: 'encamado', child: Text('Encamado')),
                          DropdownMenuItem(value: 'otro', child: Text('Otro')),
                        ],
                        onChanged: (v) => setState(() => _mobility = v ?? 'ambulatorio'),
                      ),
                      const SizedBox(height: 20),
                      Text('Cuidador y fragilidad',
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700)),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Cuidador identificado'),
                        value: _hasCaregiver,
                        activeColor: KuraColors.primary,
                        onChanged: (v) => setState(() => _hasCaregiver = v),
                      ),
                      if (_hasCaregiver) ...[
                        TextFormField(
                          controller: _caregiverNameCtrl,
                          decoration: const InputDecoration(labelText: 'Nombre del cuidador'),
                        ),
                        const SizedBox(height: 8),
                        TextFormField(
                          controller: _caregiverPhoneCtrl,
                          decoration: const InputDecoration(labelText: 'Teléfono del cuidador'),
                        ),
                      ],
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Paciente frágil'),
                        subtitle: const Text('Activa interconsulta a geriatría en el motor Kura+'),
                        value: _fragile,
                        activeColor: KuraColors.primary,
                        onChanged: (v) => setState(() => _fragile = v),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _notesCtrl,
                        maxLines: 3,
                        decoration: const InputDecoration(labelText: 'Antecedentes'),
                      ),
                      const SizedBox(height: 24),
                      FilledButton.icon(
                        icon: _saving
                            ? const SizedBox(
                                height: 16,
                                width: 16,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white),
                              )
                            : const Icon(Icons.save),
                        label: Text(_saving ? 'Guardando...' : 'Crear expediente'),
                        style: FilledButton.styleFrom(
                          backgroundColor: KuraColors.primary,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        onPressed: _saving
                            ? null
                            : () async {
                                if (!_formKey.currentState!.validate()) return;
                                setState(() => _saving = true);
                                final session = ref.read(sessionProvider);
                                try {
                                  final patient = await repo.createPatient(
                                    fullName: _nameCtrl.text.trim(),
                                    birthDate: _birthDate,
                                    sex: _sex,
                                    primarySiteId: _siteId,
                                    mobility: _mobility,
                                    hasIdentifiedCaregiver: _hasCaregiver,
                                    caregiverName: _hasCaregiver
                                        ? _caregiverNameCtrl.text.trim()
                                        : null,
                                    caregiverPhone: _hasCaregiver
                                        ? _caregiverPhoneCtrl.text.trim()
                                        : null,
                                    fragilePatient: _fragile,
                                    backgroundNotes: _notesCtrl.text.trim(),
                                  );
                                  if (session.user?.staffId != null) {
                                    await repo.assignPatientToStaff(
                                        patient.id, session.user!.staffId!);
                                  }
                                  // La bitacora de auditoria la genera el
                                  // trigger AFTER INSERT de Postgres
                                  // (audit_trigger_fn), no una llamada manual
                                  // desde el cliente: asi se garantiza que
                                  // nadie pueda falsificarla (no hay politica
                                  // de INSERT en audit_log).
                                  if (mounted) {
                                    context.go('/patients/${patient.id}');
                                  }
                                } catch (e, st) {
                                  debugPrint('Error al crear paciente: $e\n$st');
                                  if (mounted) {
                                    setState(() => _saving = false);
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content:
                                            Text('No se pudo crear el paciente: $e'),
                                      ),
                                    );
                                  }
                                }
                              },
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
