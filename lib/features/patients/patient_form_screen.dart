import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/kura_theme.dart';
import '../../core/providers/session_provider.dart';
import '../../engine/models/kura_engine_enums.dart';
import '../../models/antecedentes.dart';
import '../../models/app_user.dart';
import '../../services/data_repository.dart';
import 'comorbidity_selector.dart';

class PatientFormScreen extends ConsumerStatefulWidget {
  /// null = alta de un paciente nuevo. No-null = editar / completar el
  /// expediente de un paciente existente (típico en los pacientes creados
  /// automáticamente desde Acuity, que llegan solo con el nombre).
  final String? patientId;
  const PatientFormScreen({super.key, this.patientId});

  @override
  ConsumerState<PatientFormScreen> createState() => _PatientFormScreenState();
}

class _PatientFormScreenState extends ConsumerState<PatientFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _caregiverNameCtrl = TextEditingController();
  final _caregiverPhoneCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  // Identificación NOM-004 (Fase 2).
  final _curpCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _occupationCtrl = TextEditingController();
  final _responsibleNameCtrl = TextEditingController();
  final _responsibleRelationshipCtrl = TextEditingController();
  final _responsiblePhoneCtrl = TextEditingController();
  final _weightCtrl = TextEditingController();
  final _heightCtrl = TextEditingController();
  // Antecedentes (Fase 3).
  final Set<AntecedenteHeredoFamiliar> _familyHistory = {};
  final _familyHistoryNotesCtrl = TextEditingController();
  TabaquismoEstado? _smoking;
  ConsumoAlcohol? _alcohol;
  ActividadFisica? _physicalActivity;
  final _apnpNotesCtrl = TextEditingController();

  @override
  void dispose() {
    _nameCtrl.dispose();
    _caregiverNameCtrl.dispose();
    _caregiverPhoneCtrl.dispose();
    _notesCtrl.dispose();
    _curpCtrl.dispose();
    _addressCtrl.dispose();
    _occupationCtrl.dispose();
    _responsibleNameCtrl.dispose();
    _responsibleRelationshipCtrl.dispose();
    _responsiblePhoneCtrl.dispose();
    _weightCtrl.dispose();
    _heightCtrl.dispose();
    _familyHistoryNotesCtrl.dispose();
    _apnpNotesCtrl.dispose();
    super.dispose();
  }

  /// Fila etiquetada de ChoiceChips (selección única) para un enum de APNP.
  Widget _apnpChips<T>({
    required String title,
    required List<T> values,
    required T? selected,
    required String Function(T) label,
    required ValueChanged<T?> onSelected,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          children: values.map((v) {
            final sel = selected == v;
            return ChoiceChip(
              label: Text(label(v)),
              selected: sel,
              selectedColor: KuraColors.primary.withOpacity(0.16),
              onSelected: (_) => onSelected(sel ? null : v),
            );
          }).toList(),
        ),
        const SizedBox(height: 12),
      ],
    );
  }
  DateTime? _birthDate;
  String _sex = 'F';
  String _mobility = 'ambulatorio';
  bool _hasCaregiver = false;
  bool _fragile = false;
  String? _siteId;
  // Comorbilidades (APP) capturadas en la apertura del expediente (NOM-004).
  // Se pueden agregar/actualizar después desde el detalle del paciente.
  final Map<Comorbilidad, ComorbilidadEstado> _comorbidities = {};
  // Snapshot de las comorbilidades al abrir en modo edición, para persistir
  // solo las que cambian (evita re-fechar/re-firmar las que no se tocaron).
  final Map<Comorbilidad, ComorbilidadEstado> _originalComorbidities = {};
  bool _saving = false;
  // En modo edición, se precargan los datos del paciente una sola vez.
  bool _prefilled = false;

  bool get _isEdit => widget.patientId != null;

  /// Precarga los controladores/campos con el paciente existente (modo edición).
  /// Se llama una vez desde build() cuando ya hay repo disponible.
  void _prefill(DataRepository repo) {
    if (_prefilled || widget.patientId == null) return;
    _prefilled = true;
    final p = repo.getPatient(widget.patientId!);
    if (p == null) return;
    _nameCtrl.text = p.fullName;
    _birthDate = p.birthDate;
    _sex = p.sex ?? _sex;
    _siteId = p.primarySiteId;
    _mobility = p.mobility ?? _mobility;
    _hasCaregiver = p.hasIdentifiedCaregiver;
    _caregiverNameCtrl.text = p.caregiverName ?? '';
    _caregiverPhoneCtrl.text = p.caregiverPhone ?? '';
    _fragile = p.fragilePatient;
    _notesCtrl.text = p.backgroundNotes ?? '';
    _curpCtrl.text = p.curp ?? '';
    _addressCtrl.text = p.address ?? '';
    _occupationCtrl.text = p.occupation ?? '';
    _responsibleNameCtrl.text = p.responsibleName ?? '';
    _responsibleRelationshipCtrl.text = p.responsibleRelationship ?? '';
    _responsiblePhoneCtrl.text = p.responsiblePhone ?? '';
    _weightCtrl.text = p.weightKg?.toString() ?? '';
    _heightCtrl.text = p.heightCm?.toString() ?? '';
    _familyHistory
      ..clear()
      ..addAll(p.familyHistory);
    _familyHistoryNotesCtrl.text = p.familyHistoryNotes ?? '';
    _smoking = p.smoking;
    _alcohol = p.alcohol;
    _physicalActivity = p.physicalActivity;
    _apnpNotesCtrl.text = p.apnpNotes ?? '';
    for (final c in repo.listComorbidities(widget.patientId!)) {
      _comorbidities[c.code] = c.status;
      _originalComorbidities[c.code] = c.status;
    }
  }

  @override
  Widget build(BuildContext context) {
    final repoAsync = ref.watch(dataRepositoryProvider);

    return Scaffold(
      appBar: AppBar(
          title: Text(_isEdit ? 'Completar / editar expediente' : 'Nuevo paciente')),
      body: repoAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, st) => Center(child: Text('Error: $e')),
        data: (repo) {
          _prefill(repo);
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
                      TextFormField(
                        controller: _curpCtrl,
                        textCapitalization: TextCapitalization.characters,
                        maxLength: 18,
                        decoration: const InputDecoration(
                          labelText: 'CURP (recomendada)',
                          helperText: '18 caracteres',
                          counterText: '',
                        ),
                        validator: (v) {
                          final s = v?.trim() ?? '';
                          if (s.isEmpty) return null; // recomendada, no obligatoria
                          return s.length == 18 ? null : 'La CURP debe tener 18 caracteres';
                        },
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _addressCtrl,
                        decoration:
                            const InputDecoration(labelText: 'Domicilio (recomendado)'),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _occupationCtrl,
                        decoration: const InputDecoration(labelText: 'Ocupación'),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _weightCtrl,
                              keyboardType: const TextInputType.numberWithOptions(
                                  decimal: true),
                              decoration:
                                  const InputDecoration(labelText: 'Peso (kg)'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextFormField(
                              controller: _heightCtrl,
                              keyboardType: const TextInputType.numberWithOptions(
                                  decimal: true),
                              decoration:
                                  const InputDecoration(labelText: 'Talla (cm)'),
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
                      const SizedBox(height: 20),
                      Text('Responsable / tutor (menores o urgencias)',
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _responsibleNameCtrl,
                        decoration:
                            const InputDecoration(labelText: 'Nombre del responsable'),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _responsibleRelationshipCtrl,
                              decoration:
                                  const InputDecoration(labelText: 'Parentesco'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextFormField(
                              controller: _responsiblePhoneCtrl,
                              keyboardType: TextInputType.phone,
                              decoration:
                                  const InputDecoration(labelText: 'Teléfono'),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _notesCtrl,
                        maxLines: 3,
                        decoration: const InputDecoration(labelText: 'Antecedentes'),
                      ),
                      const SizedBox(height: 20),
                      Text('Comorbilidades (antecedentes personales patológicos)',
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 4),
                      Text(
                        'Opcional al abrir el expediente; se pueden agregar o '
                        'actualizar después. Solo las "Presente" influyen en el '
                        'arquetipo del paciente.',
                        style: TextStyle(
                            fontSize: 12,
                            color: KuraColors.darkText.withOpacity(0.6)),
                      ),
                      const SizedBox(height: 12),
                      ComorbidityStatusSelector(
                        values: _comorbidities,
                        onChanged: (code, estado) =>
                            setState(() => _comorbidities[code] = estado),
                      ),
                      const SizedBox(height: 20),
                      Text('Antecedentes heredo-familiares',
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: AntecedenteHeredoFamiliar.values.map((ahf) {
                          final sel = _familyHistory.contains(ahf);
                          return FilterChip(
                            label: Text(ahf.label),
                            selected: sel,
                            selectedColor: KuraColors.primary.withOpacity(0.16),
                            onSelected: (v) => setState(() {
                              if (v) {
                                _familyHistory.add(ahf);
                              } else {
                                _familyHistory.remove(ahf);
                              }
                            }),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _familyHistoryNotesCtrl,
                        maxLines: 2,
                        decoration: const InputDecoration(
                            labelText: 'Detalle heredo-familiares'),
                      ),
                      const SizedBox(height: 20),
                      Text('Antecedentes personales no patológicos',
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 8),
                      _apnpChips<TabaquismoEstado>(
                        title: 'Tabaquismo',
                        values: TabaquismoEstado.values,
                        selected: _smoking,
                        label: (v) => v.label,
                        onSelected: (v) => setState(() => _smoking = v),
                      ),
                      _apnpChips<ConsumoAlcohol>(
                        title: 'Alcohol',
                        values: ConsumoAlcohol.values,
                        selected: _alcohol,
                        label: (v) => v.label,
                        onSelected: (v) => setState(() => _alcohol = v),
                      ),
                      _apnpChips<ActividadFisica>(
                        title: 'Actividad física',
                        values: ActividadFisica.values,
                        selected: _physicalActivity,
                        label: (v) => v.label,
                        onSelected: (v) => setState(() => _physicalActivity = v),
                      ),
                      TextFormField(
                        controller: _apnpNotesCtrl,
                        maxLines: 2,
                        decoration: const InputDecoration(
                          labelText:
                              'Otros (toxicomanías, alimentación, vivienda, escolaridad)',
                        ),
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
                        label: Text(_saving
                            ? 'Guardando...'
                            : (_isEdit ? 'Guardar cambios' : 'Crear expediente')),
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
                                var staffId = session.user?.staffId;
                                if (staffId == null &&
                                    session.user?.role == AppRole.admin) {
                                  staffId =
                                      await repo.ensureAdminStaffId(session.user!);
                                }
                                try {
                                  // ---- MODO EDICIÓN: completar/editar un
                                  // expediente existente (p.ej. paciente de
                                  // Acuity que solo traía el nombre). ----
                                  if (_isEdit) {
                                    await repo.updatePatient(
                                      patientId: widget.patientId!,
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
                                      curp: _curpCtrl.text.trim().isEmpty
                                          ? null
                                          : _curpCtrl.text.trim().toUpperCase(),
                                      address: _addressCtrl.text.trim().isEmpty
                                          ? null
                                          : _addressCtrl.text.trim(),
                                      occupation: _occupationCtrl.text.trim().isEmpty
                                          ? null
                                          : _occupationCtrl.text.trim(),
                                      responsibleName:
                                          _responsibleNameCtrl.text.trim().isEmpty
                                              ? null
                                              : _responsibleNameCtrl.text.trim(),
                                      responsibleRelationship:
                                          _responsibleRelationshipCtrl.text.trim().isEmpty
                                              ? null
                                              : _responsibleRelationshipCtrl.text.trim(),
                                      responsiblePhone:
                                          _responsiblePhoneCtrl.text.trim().isEmpty
                                              ? null
                                              : _responsiblePhoneCtrl.text.trim(),
                                      weightKg: double.tryParse(
                                          _weightCtrl.text.trim().replaceAll(',', '.')),
                                      heightCm: double.tryParse(
                                          _heightCtrl.text.trim().replaceAll(',', '.')),
                                      familyHistory: _familyHistory,
                                      familyHistoryNotes:
                                          _familyHistoryNotesCtrl.text.trim().isEmpty
                                              ? null
                                              : _familyHistoryNotesCtrl.text.trim(),
                                      smoking: _smoking,
                                      alcohol: _alcohol,
                                      physicalActivity: _physicalActivity,
                                      apnpNotes: _apnpNotesCtrl.text.trim().isEmpty
                                          ? null
                                          : _apnpNotesCtrl.text.trim(),
                                    );
                                    // Solo persistir las comorbilidades que
                                    // cambiaron respecto a la carga inicial.
                                    for (final entry in _comorbidities.entries) {
                                      final original =
                                          _originalComorbidities[entry.key] ??
                                              ComorbilidadEstado.noEvaluado;
                                      if (entry.value == original) continue;
                                      await repo.setComorbidity(
                                        patientId: widget.patientId!,
                                        code: entry.key,
                                        status: entry.value,
                                        staffId: staffId,
                                      );
                                    }
                                    if (mounted) {
                                      context.go('/patients/${widget.patientId}');
                                    }
                                    return;
                                  }
                                  // ---- MODO ALTA: paciente nuevo. ----
                                  final patient = await repo.createPatient(
                                    fullName: _nameCtrl.text.trim(),
                                    organizationId: session.user?.organizationId,
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
                                    curp: _curpCtrl.text.trim().isEmpty
                                        ? null
                                        : _curpCtrl.text.trim().toUpperCase(),
                                    address: _addressCtrl.text.trim().isEmpty
                                        ? null
                                        : _addressCtrl.text.trim(),
                                    occupation: _occupationCtrl.text.trim().isEmpty
                                        ? null
                                        : _occupationCtrl.text.trim(),
                                    responsibleName:
                                        _responsibleNameCtrl.text.trim().isEmpty
                                            ? null
                                            : _responsibleNameCtrl.text.trim(),
                                    responsibleRelationship:
                                        _responsibleRelationshipCtrl.text.trim().isEmpty
                                            ? null
                                            : _responsibleRelationshipCtrl.text.trim(),
                                    responsiblePhone:
                                        _responsiblePhoneCtrl.text.trim().isEmpty
                                            ? null
                                            : _responsiblePhoneCtrl.text.trim(),
                                    weightKg: double.tryParse(
                                        _weightCtrl.text.trim().replaceAll(',', '.')),
                                    heightCm: double.tryParse(
                                        _heightCtrl.text.trim().replaceAll(',', '.')),
                                    familyHistory: _familyHistory,
                                    familyHistoryNotes:
                                        _familyHistoryNotesCtrl.text.trim().isEmpty
                                            ? null
                                            : _familyHistoryNotesCtrl.text.trim(),
                                    smoking: _smoking,
                                    alcohol: _alcohol,
                                    physicalActivity: _physicalActivity,
                                    apnpNotes: _apnpNotesCtrl.text.trim().isEmpty
                                        ? null
                                        : _apnpNotesCtrl.text.trim(),
                                  );
                                  if (staffId != null) {
                                    await repo.assignPatientToStaff(
                                        patient.id, staffId);
                                  }
                                  // Comorbilidades (APP) capturadas al abrir:
                                  // se persisten fechadas + atribuidas + auditadas.
                                  // Solo las evaluadas (presente/negado), no las
                                  // "no evaluado" (estado por defecto).
                                  for (final entry in _comorbidities.entries) {
                                    if (entry.value ==
                                        ComorbilidadEstado.noEvaluado) {
                                      continue;
                                    }
                                    await repo.setComorbidity(
                                      patientId: patient.id,
                                      code: entry.key,
                                      status: entry.value,
                                      staffId: staffId,
                                    );
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
