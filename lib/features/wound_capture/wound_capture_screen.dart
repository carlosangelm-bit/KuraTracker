import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../../core/theme/kura_theme.dart';
import '../../core/providers/session_provider.dart';
import '../../engine/models/kura_engine_enums.dart';
import '../../models/patient.dart';
import '../../models/wound.dart' as wmodel;
import '../../services/data_repository.dart';
import 'wound_capture_controller.dart';
import 'wound_capture_form_state.dart';
import 'widgets/bed_composition_sliders.dart';
import 'widgets/body_map_selector.dart';
import 'widgets/live_prognosis_panel.dart';
import '../treatment/treatment_step_screen.dart';

/// Pantalla unica de captura de herida con divulgacion progresiva
/// (secciones colapsables) segun la etiologia elegida (seccion 6.1).
/// Consolida lo que en el flujo original eran los pasos 1 y 2 en una sola
/// vista con scroll, priorizando rapidez de captura y menor carga
/// cognitiva. El pronostico en vivo se muestra permanentemente visible.
class WoundCaptureScreen extends ConsumerStatefulWidget {
  final String patientId;
  final String? woundId; // null = nueva herida
  final String? consultationId;

  const WoundCaptureScreen({
    super.key,
    required this.patientId,
    this.woundId,
    this.consultationId,
  });

  @override
  ConsumerState<WoundCaptureScreen> createState() => _WoundCaptureScreenState();
}

class _WoundCaptureScreenState extends ConsumerState<WoundCaptureScreen> {
  late String _draftKey;
  Timer? _debounce;
  bool _initialized = false;
  final _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _draftKey = widget.consultationId ?? 'draft-${widget.patientId}';
  }

  void _scheduleRecompute() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      ref.read(woundCaptureControllerProvider(_draftKey).notifier).recomputePrognosis();
    });
  }

  Future<void> _initFromPatient(DataRepository repo) async {
    if (_initialized) return;
    _initialized = true;
    final patient = repo.getPatient(widget.patientId);
    final controller = ref.read(woundCaptureControllerProvider(_draftKey).notifier);
    if (patient != null) {
      controller.state.pacienteFragil = patient.fragilePatient;
      controller.state.tieneCuidadorIdentificado = patient.hasIdentifiedCaregiver;
      final comorbidities = repo.listComorbidities(patient.id);
      for (final c in comorbidities) {
        controller.state.comorbilidades[c.code] = c.status;
      }
    }
    controller.touch();
  }

  Future<void> _pickImage() async {
    try {
      final file = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
      if (file != null) {
        final controller = ref.read(woundCaptureControllerProvider(_draftKey).notifier);
        controller.state.photoPaths.add(file.path);
        controller.touch();
      }
    } catch (_) {
      // En web sin soporte de camara, el picker de galeria/archivo sigue funcionando.
    }
  }

  @override
  Widget build(BuildContext context) {
    final repoAsync = ref.watch(dataRepositoryProvider);
    final formState = ref.watch(woundCaptureControllerProvider(_draftKey));
    final controllerNotifier = ref.read(woundCaptureControllerProvider(_draftKey).notifier);
    final isWide = MediaQuery.of(context).size.width >= 1000;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Registrar herida'),
        actions: [
          TextButton.icon(
            icon: const Icon(Icons.save_outlined, size: 18),
            label: const Text('Guardar borrador'),
            onPressed: () async {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Borrador guardado.')),
              );
            },
          ),
        ],
      ),
      body: repoAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, st) => Center(child: Text('Error: $e')),
        data: (repo) {
          _initFromPatient(repo);
          final patient = repo.getPatient(widget.patientId);
          if (patient == null) return const Center(child: Text('Paciente no encontrado.'));

          final formContent = _buildForm(context, repo, patient, formState, controllerNotifier);
          final prognosisPanel = LivePrognosisPanel(
            output: controllerNotifier.liveOutput,
            isLoading: controllerNotifier.engineLoading,
            hasMinimumData: formState.hasMinimumDataForPrognosis,
          );

          if (isWide) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 3,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(20),
                    child: formContent,
                  ),
                ),
                Container(
                  width: 380,
                  padding: const EdgeInsets.all(20),
                  child: SingleChildScrollView(child: prognosisPanel),
                ),
              ],
            );
          }

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                prognosisPanel,
                const SizedBox(height: 16),
                formContent,
              ],
            ),
          );
        },
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: FilledButton.icon(
            icon: const Icon(Icons.arrow_forward),
            label: const Text('Continuar a tratamiento'),
            style: FilledButton.styleFrom(
              backgroundColor: KuraColors.primary,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            onPressed: () => _continueToTreatment(context, ref),
          ),
        ),
      ),
    );
  }

  Future<void> _continueToTreatment(BuildContext context, WidgetRef ref) async {
    final repo = await DataRepository.instance();
    final controller = ref.read(woundCaptureControllerProvider(_draftKey).notifier);
    final formState = controller.state;

    if (!formState.hasMinimumDataForPrognosis) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Completa al menos largo y ancho de la herida.')),
      );
      return;
    }

    wmodel.Wound wound;
    String? consultationId;
    try {
      // Crea o reutiliza la herida.
      if (widget.woundId != null && widget.woundId != 'new') {
        wound = repo.getWound(widget.woundId!)!;
      } else {
        wound = await repo.createWound({
          'patient_id': widget.patientId,
          'etiology': formState.etiologia.dbValue,
          'subtype': formState.subtype,
          'body_location_primary': formState.bodyLocationPrimary ?? 'no_especificado',
          'body_location_secondary': formState.bodyLocationSecondary,
          'onset_date': formState.onsetDate?.toIso8601String().substring(0, 10),
          'wagner_grade': formState.wagnerGrade?.name,
          'wifi_wound': formState.wifiWound,
          'wifi_ischemia': formState.wifiIschemia,
          'wifi_infection': formState.wifiInfection,
          'ceap_class': formState.ceapClass?.name,
          'wuwhs_grade': formState.wuwhsGrade?.name,
          'agente_causal': formState.agenteCausal?.name,
        });
      }

      consultationId = widget.consultationId;
      if (consultationId != null) {
        await repo.createAssessment({
          'consultation_id': consultationId,
          'wound_id': wound.id,
          'glucose_mg_dl': formState.glucoseMgDl,
          'hba1c_pct': formState.hba1cPct,
          'braden_score': formState.bradenScore,
          'first_assessment_date':
              formState.firstAssessmentDate?.toIso8601String().substring(0, 10),
          'edema': formState.edema,
          'pain': formState.pain,
          'pain_type': formState.painType,
          'pain_duration': formState.painDuration,
          'pain_vas': formState.painVas,
          'exudate_amount': formState.exudadoCantidad.name,
          'infection_criteria': formState.infeccionCriterios.map((e) => e.name).toList(),
          'odor': formState.odor,
          'wound_edge': formState.woundEdge,
          'perilesional_skin': formState.perilesionalSkin.map((e) => e.name).toList(),
        });

        await repo.createMeasurement({
          'wound_id': wound.id,
          'consultation_id': consultationId,
          'measured_at': DateTime.now().toIso8601String().substring(0, 10),
          'length_cm': formState.lengthCm,
          'width_cm': formState.widthCm,
          'area_cm2': formState.areaCm2,
          'depth_cm': formState.depthCm,
          'tunneling': formState.tunneling,
          'undermining': formState.undermining,
          'granulation_pct': formState.granulacionPct,
          'slough_pct': formState.esfaceloPct,
          'necrosis_pct': formState.necrosisPct,
          'epithelialization_pct': formState.epitelizacionPct,
          'captured_before_debridement': formState.capturedBeforeDebridement,
        });

        await repo.upsertPerfusion({
          'consultation_id': consultationId,
          'wound_id': wound.id,
          'abi_right': formState.abiRight,
          'abi_left': formState.abiLeft,
          'is_lower_extremity': formState.esExtremidadInferior,
          'albumin_g_dl': formState.albuminaGdl,
        });
        // La bitacora de auditoria de wound_measurements la genera el
        // trigger AFTER INSERT de Postgres (audit_trigger_fn), no una
        // llamada manual desde el cliente: asi se garantiza que nadie pueda
        // falsificarla (no hay politica de INSERT en audit_log).
      }
    } catch (e, st) {
      debugPrint('Error al guardar captura de herida: $e\n$st');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo guardar la captura: $e')),
        );
      }
      return;
    }

    final resolvedConsultationId = consultationId;
    if (context.mounted && resolvedConsultationId != null) {
      context.go(
        '/patients/${widget.patientId}/wound/${wound.id}/capture?consultationId=$resolvedConsultationId',
      );
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => TreatmentStepScreen(
            patientId: widget.patientId,
            woundId: wound.id,
            consultationId: resolvedConsultationId,
            draftKey: _draftKey,
          ),
        ),
      );
    }
  }

  Widget _buildForm(
    BuildContext context,
    DataRepository repo,
    Patient patient,
    WoundCaptureFormState formState,
    WoundCaptureController controller,
  ) {
    void update(VoidCallback fn) {
      fn();
      controller.touch();
      _scheduleRecompute();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionCard(
          icon: Icons.camera_alt_outlined,
          title: 'Evidencia fotográfica',
          subtitle: 'Captura la foto primero; podrás ajustar los datos después',
          initiallyExpanded: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ...formState.photoPaths.map((p) => Stack(
                        children: [
                          Container(
                            width: 90,
                            height: 90,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: KuraColors.borderSubtle),
                              color: KuraColors.chipBg,
                            ),
                            child: const Icon(Icons.image, color: KuraColors.primary),
                          ),
                          Positioned(
                            top: 2,
                            right: 2,
                            child: InkWell(
                              onTap: () => update(() => formState.photoPaths.remove(p)),
                              child: const CircleAvatar(
                                radius: 10,
                                backgroundColor: KuraColors.danger,
                                child: Icon(Icons.close, size: 12, color: Colors.white),
                              ),
                            ),
                          ),
                        ],
                      )),
                  InkWell(
                    onTap: _pickImage,
                    child: Container(
                      width: 90,
                      height: 90,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: KuraColors.primary, style: BorderStyle.solid),
                      ),
                      child: const Icon(Icons.add_a_photo_outlined, color: KuraColors.primary),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Límite de 17 MB por lote. Formatos JPG/PNG.',
                style: TextStyle(fontSize: 11, color: KuraColors.darkText.withOpacity(0.5)),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _SectionCard(
          icon: Icons.category_outlined,
          title: 'Etiología y localización',
          subtitle: 'Determina qué campos clínicos se mostrarán después',
          initiallyExpanded: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Tipo de herida *', style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: Etiologia.values.map((e) {
                  final selected = formState.etiologia == e;
                  return ChoiceChip(
                    label: Text(e.label),
                    selected: selected,
                    selectedColor: KuraColors.primary.withOpacity(0.18),
                    onSelected: (_) => update(() => formState.etiologia = e),
                  );
                }).toList(),
              ),
              const SizedBox(height: 16),
              TextFormField(
                decoration: const InputDecoration(labelText: 'Subtipo de herida'),
                initialValue: formState.subtype,
                onChanged: (v) => update(() => formState.subtype = v),
              ),
              const SizedBox(height: 16),
              const Text('Ubicación corporal *', style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              BodyMapSelector(
                selectedCode: formState.bodyLocationPrimary,
                onSelected: (code) => update(() {
                  formState.bodyLocationPrimary = code;
                  formState.esExtremidadInferior = formState.isLowerExtremityLocation;
                }),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.calendar_today, size: 16),
                      label: Text(formState.onsetDate == null
                          ? 'Fecha de inicio *'
                          : DateFormat('dd/MM/yyyy').format(formState.onsetDate!)),
                      onPressed: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: DateTime.now(),
                          firstDate: DateTime(2015),
                          lastDate: DateTime.now(),
                        );
                        if (picked != null) update(() => formState.onsetDate = picked);
                      },
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _buildEtiologySpecificSection(formState, update),
        const SizedBox(height: 12),
        _SectionCard(
          icon: Icons.monitor_heart_outlined,
          title: 'Evaluación clínica',
          subtitle: 'Signos, dolor, exudado, infección, piel perilesional',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                decoration: const InputDecoration(labelText: 'Glucosa en sangre (mg/dL) *'),
                keyboardType: TextInputType.number,
                onChanged: (v) => update(() => formState.glucoseMgDl = double.tryParse(v)),
              ),
              if (formState.isDiabeticPatient) ...[
                const SizedBox(height: 12),
                TextFormField(
                  decoration: const InputDecoration(
                    labelText: 'HbA1c (hemoglobina glucosilada, %) *',
                    helperText: 'Distinta de la glucosa capilar; control metabólico de los últimos 2-3 meses.',
                  ),
                  keyboardType: TextInputType.number,
                  onChanged: (v) => update(() => formState.hba1cPct = double.tryParse(v)),
                ),
              ],
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: formState.edema,
                decoration: const InputDecoration(labelText: 'Edema *'),
                items: const [
                  DropdownMenuItem(value: 'ninguno', child: Text('Ninguno')),
                  DropdownMenuItem(value: 'leve', child: Text('Leve')),
                  DropdownMenuItem(value: 'moderado', child: Text('Moderado')),
                  DropdownMenuItem(value: 'severo', child: Text('Severo')),
                ],
                onChanged: (v) => update(() => formState.edema = v ?? 'ninguno'),
              ),
              const SizedBox(height: 12),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Dolor *'),
                value: formState.pain,
                activeColor: KuraColors.primary,
                onChanged: (v) => update(() => formState.pain = v),
              ),
              if (formState.pain) ...[
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        value: formState.painType,
                        decoration: const InputDecoration(labelText: 'Tipo de dolor *'),
                        items: const [
                          DropdownMenuItem(value: 'nociceptivo', child: Text('Nociceptivo')),
                          DropdownMenuItem(value: 'neuropatico', child: Text('Neuropático')),
                          DropdownMenuItem(value: 'isquemico', child: Text('Isquémico')),
                          DropdownMenuItem(value: 'mixto', child: Text('Mixto')),
                        ],
                        onChanged: (v) => update(() => formState.painType = v),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        value: formState.painDuration,
                        decoration: const InputDecoration(labelText: 'Duración *'),
                        items: const [
                          DropdownMenuItem(value: 'agudo', child: Text('Agudo')),
                          DropdownMenuItem(value: 'cronico', child: Text('Crónico')),
                          DropdownMenuItem(value: 'intermitente', child: Text('Intermitente')),
                        ],
                        onChanged: (v) => update(() => formState.painDuration = v),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text('Escala Visual Analógica (EVA): ${formState.painVas}/10',
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                Slider(
                  value: formState.painVas.toDouble(),
                  min: 0,
                  max: 10,
                  divisions: 10,
                  activeColor: KuraColors.primary,
                  label: '${formState.painVas}',
                  onChanged: (v) => update(() => formState.painVas = v.round()),
                ),
              ],
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<ExudadoTipo>(
                      value: formState.exudadoTipo,
                      decoration: const InputDecoration(labelText: 'Exudado (tipo)'),
                      items: ExudadoTipo.values
                          .map((e) => DropdownMenuItem(value: e, child: Text(e.name)))
                          .toList(),
                      onChanged: (v) =>
                          update(() => formState.exudadoTipo = v ?? ExudadoTipo.seroso),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButtonFormField<ExudadoCantidad>(
                      value: formState.exudadoCantidad,
                      decoration: const InputDecoration(labelText: 'Exudado (cantidad)'),
                      items: ExudadoCantidad.values
                          .map((e) => DropdownMenuItem(value: e, child: Text(e.name)))
                          .toList(),
                      onChanged: (v) => update(
                          () => formState.exudadoCantidad = v ?? ExudadoCantidad.escaso),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const Text('Infección (criterios IWII) *', style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: InfeccionCriterioIwii.values.map((c) {
                  final selected = formState.infeccionCriterios.contains(c);
                  return FilterChip(
                    label: Text(c.name, style: const TextStyle(fontSize: 12)),
                    selected: selected,
                    selectedColor: KuraColors.danger.withOpacity(0.15),
                    onSelected: (v) => update(() {
                      if (v) {
                        formState.infeccionCriterios.add(c);
                      } else {
                        formState.infeccionCriterios.remove(c);
                      }
                    }),
                  );
                }).toList(),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value: formState.odor,
                      decoration: const InputDecoration(labelText: 'Olor *'),
                      items: const [
                        DropdownMenuItem(value: 'ninguno', child: Text('Ninguno')),
                        DropdownMenuItem(value: 'leve', child: Text('Leve')),
                        DropdownMenuItem(value: 'moderado', child: Text('Moderado')),
                        DropdownMenuItem(value: 'fuerte', child: Text('Fuerte')),
                      ],
                      onChanged: (v) => update(() => formState.odor = v ?? 'ninguno'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value: formState.woundEdge,
                      decoration: const InputDecoration(labelText: 'Borde de la herida *'),
                      items: const [
                        DropdownMenuItem(value: 'definido', child: Text('Definido')),
                        DropdownMenuItem(value: 'irregular', child: Text('Irregular')),
                        DropdownMenuItem(value: 'dehiscente', child: Text('Dehiscente')),
                        DropdownMenuItem(value: 'macerado', child: Text('Macerado')),
                        DropdownMenuItem(value: 'epibole', child: Text('Epíbole (enrollado)')),
                      ],
                      onChanged: (v) => update(() => formState.woundEdge = v ?? 'definido'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const Text('Piel perilesional *', style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: PielPerilesionalEstado.values.map((p) {
                  final selected = formState.perilesionalSkin.contains(p);
                  return FilterChip(
                    label: Text(p.name, style: const TextStyle(fontSize: 12)),
                    selected: selected,
                    selectedColor: KuraColors.warning.withOpacity(0.2),
                    onSelected: (v) => update(() {
                      if (v) {
                        formState.perilesionalSkin.add(p);
                      } else {
                        formState.perilesionalSkin.remove(p);
                      }
                    }),
                  );
                }).toList(),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _SectionCard(
          icon: Icons.straighten,
          title: 'Zona de la herida (dimensiones)',
          subtitle: 'Área autocalculada · Composición del lecho',
          initiallyExpanded: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      decoration: const InputDecoration(labelText: 'Longitud (cm) *'),
                      keyboardType: TextInputType.number,
                      onChanged: (v) => update(() {
                        formState.lengthCm = double.tryParse(v) ?? 0;
                      }),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      decoration: const InputDecoration(labelText: 'Anchura (cm) *'),
                      keyboardType: TextInputType.number,
                      onChanged: (v) => update(() {
                        formState.widthCm = double.tryParse(v) ?? 0;
                      }),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      decoration: const InputDecoration(labelText: 'Profundidad (cm)'),
                      keyboardType: TextInputType.number,
                      onChanged: (v) => update(() {
                        formState.depthCm = double.tryParse(v) ?? 0;
                      }),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: KuraColors.chipBg,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.calculate_outlined, size: 18, color: KuraColors.primary),
                    const SizedBox(width: 8),
                    Text('Área autocalculada: ${formState.areaCm2.toStringAsFixed(2)} cm²',
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      value: formState.tunneling,
                      title: const Text('Tunelización', style: TextStyle(fontSize: 13)),
                      onChanged: (v) => update(() => formState.tunneling = v ?? false),
                    ),
                  ),
                  Expanded(
                    child: CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      value: formState.undermining,
                      title: const Text('Socavamiento *', style: TextStyle(fontSize: 13)),
                      onChanged: (v) => update(() => formState.undermining = v ?? false),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              const Divider(),
              const SizedBox(height: 8),
              const Text('Composición del lecho *', style: TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              BedCompositionSliders(
                granulacion: formState.granulacionPct,
                esfacelo: formState.esfaceloPct,
                necrosis: formState.necrosisPct,
                epitelizacion: formState.epitelizacionPct,
                onGranulacionChanged: (v) => update(() => formState.granulacionPct = v),
                onEsfaceloChanged: (v) => update(() => formState.esfaceloPct = v),
                onNecrosisChanged: (v) => update(() => formState.necrosisPct = v),
                onEpitelizacionChanged: (v) => update(() => formState.epitelizacionPct = v),
                capturedBeforeDebridement: formState.capturedBeforeDebridement,
                onCapturedBeforeDebridementChanged: (v) =>
                    update(() => formState.capturedBeforeDebridement = v),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _SectionCard(
          icon: Icons.bloodtype_outlined,
          title: 'Perfusión y nutrición',
          subtitle: 'ABI/ITB (extremidad inferior) y albúmina — ajustan el pronóstico',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Herida de extremidad inferior'),
                subtitle: Text(
                  formState.isLowerExtremityLocation
                      ? 'Detectado automáticamente por la ubicación seleccionada. Puedes anularlo si no aplica.'
                      : 'La ubicación seleccionada no es de extremidad inferior. Activa esto solo para anular la detección.',
                ),
                // Gateo primario: isLowerExtremityLocation (derivado de la
                // ubicacion corporal). El switch actua como override manual
                // para casos donde la deteccion automatica no coincide con
                // el criterio clinico (p. ej. ubicacion no capturada aun).
                value: formState.esExtremidadInferior,
                activeColor: KuraColors.primary,
                onChanged: (v) => update(() => formState.esExtremidadInferior = v),
              ),
              if (formState.esExtremidadInferior)
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        decoration: const InputDecoration(labelText: 'ABI/ITB pie derecho'),
                        keyboardType: TextInputType.number,
                        onChanged: (v) => update(() => formState.abiRight = double.tryParse(v)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        decoration: const InputDecoration(labelText: 'ABI/ITB pie izquierdo'),
                        keyboardType: TextInputType.number,
                        onChanged: (v) => update(() => formState.abiLeft = double.tryParse(v)),
                      ),
                    ),
                  ],
                ),
              const SizedBox(height: 12),
              TextFormField(
                decoration: const InputDecoration(labelText: 'Albúmina sérica (g/dL)'),
                keyboardType: TextInputType.number,
                onChanged: (v) => update(() => formState.albuminaGdl = double.tryParse(v)),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildEtiologySpecificSection(
      WoundCaptureFormState formState, void Function(VoidCallback) update) {
    switch (formState.etiologia) {
      case Etiologia.pieDiabetico:
        return _SectionCard(
          icon: Icons.accessibility_new,
          title: 'Pie diabético — Wagner + WIfI',
          subtitle: 'Determina el dispositivo de descarga sugerido',
          initiallyExpanded: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Clasificación Wagner *', style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: WagnerGrade.values.map((g) {
                  final selected = formState.wagnerGrade == g;
                  return ChoiceChip(
                    label: Text(g.name.toUpperCase()),
                    selected: selected,
                    selectedColor: KuraColors.primary.withOpacity(0.18),
                    onSelected: (_) => update(() => formState.wagnerGrade = g),
                  );
                }).toList(),
              ),
              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 8),
              const Text('Clasificación WIfI (Wound / Ischemia / foot Infection) *',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Text(
                'Cada subescala se gradúa por separado, de 0 (mínimo) a 3 (máximo).',
                style: TextStyle(fontSize: 12, color: KuraColors.darkText.withOpacity(0.6)),
              ),
              const SizedBox(height: 8),
              _WifiSubscaleSelector(
                label: 'W — Herida (Wound)',
                value: formState.wifiWound,
                onChanged: (v) => update(() => formState.wifiWound = v),
              ),
              const SizedBox(height: 8),
              _WifiSubscaleSelector(
                label: 'I — Isquemia (Ischemia)',
                value: formState.wifiIschemia,
                onChanged: (v) => update(() => formState.wifiIschemia = v),
              ),
              const SizedBox(height: 8),
              _WifiSubscaleSelector(
                label: 'fI — Infección del pie (foot Infection)',
                value: formState.wifiInfection,
                onChanged: (v) => update(() => formState.wifiInfection = v),
              ),
            ],
          ),
        );
      case Etiologia.vascular:
        return _SectionCard(
          icon: Icons.water_drop_outlined,
          title: 'Úlcera vascular/venosa — Clasificación CEAP',
          subtitle: 'Determina el nivel de compresión sugerido',
          initiallyExpanded: true,
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: CeapClass.values.map((c) {
              final selected = formState.ceapClass == c;
              return ChoiceChip(
                label: Text(c.name.toUpperCase()),
                selected: selected,
                selectedColor: KuraColors.primary.withOpacity(0.18),
                onSelected: (_) => update(() => formState.ceapClass = c),
              );
            }).toList(),
          ),
        );
      case Etiologia.quirurgica:
        return _SectionCard(
          icon: Icons.medical_services_outlined,
          title: 'Herida quirúrgica — Grado WUWHS',
          subtitle: 'G4 activa interconsulta urgente automática',
          initiallyExpanded: true,
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: WuwhsGrade.values.map((g) {
              final selected = formState.wuwhsGrade == g;
              return ChoiceChip(
                label: Text(g.name.toUpperCase()),
                selected: selected,
                selectedColor: KuraColors.primary.withOpacity(0.18),
                onSelected: (_) => update(() => formState.wuwhsGrade = g),
              );
            }).toList(),
          ),
        );
      case Etiologia.traumatica:
        return _SectionCard(
          icon: Icons.emergency_outlined,
          title: 'Herida traumática — Agente causal',
          subtitle: 'Determina el manejo específico e interconsultas',
          initiallyExpanded: true,
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: AgenteCausal.values.map((a) {
              final selected = formState.agenteCausal == a;
              return ChoiceChip(
                label: Text(a.name),
                selected: selected,
                selectedColor: KuraColors.primary.withOpacity(0.18),
                onSelected: (_) => update(() => formState.agenteCausal = a),
              );
            }).toList(),
          ),
        );
      case Etiologia.lpp:
        return _SectionCard(
          icon: Icons.airline_seat_flat_outlined,
          title: 'Lesión por presión — Escala de Braden *',
          subtitle: 'Riesgo de LPP: a menor puntaje, mayor riesgo (obligatorio)',
          initiallyExpanded: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Puntaje total: ${formState.bradenScore ?? '—'} / 23',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              Text(
                'Suma de las 6 subescalas (percepción sensorial, humedad, actividad, '
                'movilidad, nutrición, fricción/cizallamiento), cada una de 1 a 4 '
                '(fricción/cizallamiento de 1 a 3). Rango total: 6-23.',
                style: TextStyle(fontSize: 12, color: KuraColors.darkText.withOpacity(0.6)),
              ),
              const SizedBox(height: 8),
              Slider(
                value: (formState.bradenScore ?? 23).toDouble(),
                min: 6,
                max: 23,
                divisions: 17,
                activeColor: KuraColors.primary,
                label: '${formState.bradenScore ?? 23}',
                onChanged: (v) => update(() => formState.bradenScore = v.round()),
              ),
              Wrap(
                spacing: 8,
                children: const [
                  Text('≤9: Riesgo muy alto', style: TextStyle(fontSize: 11)),
                  Text('10-12: Alto', style: TextStyle(fontSize: 11)),
                  Text('13-14: Moderado', style: TextStyle(fontSize: 11)),
                  Text('15-18: Bajo', style: TextStyle(fontSize: 11)),
                  Text('19-23: Sin riesgo', style: TextStyle(fontSize: 11)),
                ],
              ),
            ],
          ),
        );
      case Etiologia.otra:
        return const SizedBox.shrink();
    }
  }
}

class _SectionCard extends StatefulWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget child;
  final bool initiallyExpanded;

  const _SectionCard({
    required this.icon,
    required this.title,
    this.subtitle,
    required this.child,
    this.initiallyExpanded = false,
  });

  @override
  State<_SectionCard> createState() => _SectionCardState();
}

class _SectionCardState extends State<_SectionCard> {
  late bool _expanded = widget.initiallyExpanded;

  /// Header de la seccion (icono + titulo + chevron). Es el UNICO lugar
  /// donde vive el gesto de expandir/colapsar. Se aisla en su propio
  /// Material para que el InkWell no compita en la gesture arena con los
  /// controles interactivos del contenido (dropdowns, mapa corporal,
  /// selector de fotos): al no ser el contenido un descendiente de este
  /// InkWell, un tap dentro del contenido nunca puede ser interceptado o
  /// "ganado" por el reconocedor de tap del header.
  Widget _buildHeader() {
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: () => setState(() => _expanded = !_expanded),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: KuraColors.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(widget.icon, color: KuraColors.primary, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(widget.title, style: const TextStyle(fontWeight: FontWeight.w700)),
                    if (widget.subtitle != null)
                      Text(widget.subtitle!,
                          style: TextStyle(
                              fontSize: 12, color: KuraColors.darkText.withOpacity(0.55))),
                  ],
                ),
              ),
              Icon(_expanded ? Icons.expand_less : Icons.expand_more),
            ],
          ),
        ),
      ),
    );
  }

  /// Contenido de la seccion (controles interactivos del formulario).
  /// Se construye fuera de cualquier InkWell/GestureDetector ancestro
  /// propio de esta tarjeta: es hermano del header en el Column, nunca
  /// descendiente de su gesto de expandir/colapsar.
  Widget _buildContent() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
      child: widget.child,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildHeader(),
          if (_expanded) _buildContent(),
        ],
      ),
    );
  }
}

/// Selector de una subescala WIfI individual (0-3), como fila de chips
/// numerados con su significado clinico como tooltip/label corto.
class _WifiSubscaleSelector extends StatelessWidget {
  final String label;
  final int? value;
  final ValueChanged<int?> onChanged;

  const _WifiSubscaleSelector({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          flex: 3,
          child: Text(label, style: const TextStyle(fontSize: 13)),
        ),
        Expanded(
          flex: 4,
          child: Wrap(
            spacing: 6,
            children: List.generate(4, (grade) {
              final selected = value == grade;
              return ChoiceChip(
                label: Text('$grade'),
                selected: selected,
                selectedColor: KuraColors.primary.withOpacity(0.18),
                onSelected: (_) => onChanged(grade),
              );
            }),
          ),
        ),
      ],
    );
  }
}
