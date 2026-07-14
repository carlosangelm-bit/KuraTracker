import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../../core/providers/session_provider.dart';
import '../../core/theme/kura_theme.dart';
import '../../engine/models/kura_engine_enums.dart';
import '../../models/consultation.dart';
import '../../services/data_repository.dart';
import '../../services/photo_upload_service.dart';
import '../wound_capture/widgets/bed_composition_sliders.dart';

/// Formulario de "Registrar seguimiento" (visita visit_type='seguimiento'
/// ligada a una herida existente). A diferencia de [WoundCaptureScreen]
/// (captura inicial completa, muchos campos condicionales por etiologia),
/// este formulario es deliberadamente mas pequeno: solo lo que una visita
/// de seguimiento necesita re-medir. Persiste, en este orden:
///   1. consultations (visit_type='seguimiento')
///   2. wound_measurements (fecha, largo/ancho->area, profundidad,
///      composicion del lecho)
///   3. wound_assessments (infeccion, exudado, adherencia)
///   4. wound_photos ("foto actual"), tras subir los bytes a Supabase
///      Storage (o codificarlos como data URL en modo demo local).
/// No hace ningun INSERT directo a audit_log: la auditoria de
/// consultations/wound_measurements la genera el trigger de Postgres
/// (audit_trigger_fn, ver 0002_triggers_and_functions.sql); wound_assessments
/// y wound_photos no estan en la lista de tablas auditadas por ese trigger,
/// asi que tampoco aplica ahi.
class FollowUpCaptureScreen extends ConsumerStatefulWidget {
  final String patientId;
  final String woundId;
  const FollowUpCaptureScreen({
    super.key,
    required this.patientId,
    required this.woundId,
  });

  @override
  ConsumerState<FollowUpCaptureScreen> createState() => _FollowUpCaptureScreenState();
}

class _FollowUpCaptureScreenState extends ConsumerState<FollowUpCaptureScreen> {
  DateTime _visitDate = DateTime.now();
  final _lengthCtrl = TextEditingController(text: '0');
  final _widthCtrl = TextEditingController(text: '0');
  final _depthCtrl = TextEditingController(text: '0');
  bool _tunneling = false;
  bool _undermining = false;

  double _granulacion = 100;
  double _esfacelo = 0;
  double _necrosis = 0;
  double _epitelizacion = 0;
  bool _capturedBeforeDebridement = true;

  ExudadoCantidad _exudadoCantidad = ExudadoCantidad.escaso;
  ExudadoTipo _exudadoTipo = ExudadoTipo.seroso;
  final Set<InfeccionCriterioIwii> _infeccionCriterios = {};
  bool _lowAdherence = false;

  XFile? _photo;
  Uint8List? _photoBytes;
  final _picker = ImagePicker();

  bool _saving = false;

  double get _lengthCm => double.tryParse(_lengthCtrl.text.replaceAll(',', '.')) ?? 0;
  double get _widthCm => double.tryParse(_widthCtrl.text.replaceAll(',', '.')) ?? 0;
  double get _depthCm => double.tryParse(_depthCtrl.text.replaceAll(',', '.')) ?? 0;
  double get _areaCm2 => _lengthCm * _widthCm;

  Future<void> _pickPhoto() async {
    try {
      final file = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
      if (file == null) return;
      final bytes = await file.readAsBytes();
      setState(() {
        _photo = file;
        _photoBytes = bytes;
      });
    } catch (_) {
      // Sin soporte de camara/galeria en este dispositivo/navegador.
    }
  }

  @override
  void dispose() {
    _lengthCtrl.dispose();
    _widthCtrl.dispose();
    _depthCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Registrar seguimiento')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 700),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Medición', style: _sectionStyle(context)),
                const SizedBox(height: 8),
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
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _lengthCtrl,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(labelText: 'Largo (cm) *'),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: _widthCtrl,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(labelText: 'Ancho (cm) *'),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: _depthCtrl,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(labelText: 'Profundidad (cm)'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text('Área calculada: ${_areaCm2.toStringAsFixed(1)} cm²',
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        controlAffinity: ListTileControlAffinity.leading,
                        value: _tunneling,
                        title: const Text('Tunelización', style: TextStyle(fontSize: 13)),
                        onChanged: (v) => setState(() => _tunneling = v ?? false),
                      ),
                    ),
                    Expanded(
                      child: CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        controlAffinity: ListTileControlAffinity.leading,
                        value: _undermining,
                        title: const Text('Socavamiento', style: TextStyle(fontSize: 13)),
                        onChanged: (v) => setState(() => _undermining = v ?? false),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Text('Composición del lecho', style: _sectionStyle(context)),
                const SizedBox(height: 8),
                BedCompositionSliders(
                  granulacion: _granulacion,
                  esfacelo: _esfacelo,
                  necrosis: _necrosis,
                  epitelizacion: _epitelizacion,
                  onGranulacionChanged: (v) => setState(() => _granulacion = v),
                  onEsfaceloChanged: (v) => setState(() => _esfacelo = v),
                  onNecrosisChanged: (v) => setState(() => _necrosis = v),
                  onEpitelizacionChanged: (v) => setState(() => _epitelizacion = v),
                  capturedBeforeDebridement: _capturedBeforeDebridement,
                  onCapturedBeforeDebridementChanged: (v) =>
                      setState(() => _capturedBeforeDebridement = v),
                ),
                const SizedBox(height: 20),
                Text('Estado clínico', style: _sectionStyle(context)),
                const SizedBox(height: 12),
                DropdownButtonFormField<ExudadoCantidad>(
                  value: _exudadoCantidad,
                  decoration: const InputDecoration(labelText: 'Cantidad de exudado'),
                  items: ExudadoCantidad.values
                      .map((e) => DropdownMenuItem(value: e, child: Text(e.name)))
                      .toList(),
                  onChanged: (v) => setState(() => _exudadoCantidad = v ?? _exudadoCantidad),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<ExudadoTipo>(
                  value: _exudadoTipo,
                  decoration: const InputDecoration(labelText: 'Tipo de exudado'),
                  items: ExudadoTipo.values
                      .map((e) => DropdownMenuItem(value: e, child: Text(e.name)))
                      .toList(),
                  onChanged: (v) => setState(() => _exudadoTipo = v ?? _exudadoTipo),
                ),
                const SizedBox(height: 12),
                Text('Criterios de infección (IWII)',
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: InfeccionCriterioIwii.values.map((c) {
                    final selected = _infeccionCriterios.contains(c);
                    return FilterChip(
                      label: Text(c.name, style: const TextStyle(fontSize: 12)),
                      selected: selected,
                      onSelected: (v) => setState(() {
                        if (v) {
                          _infeccionCriterios.add(c);
                        } else {
                          _infeccionCriterios.remove(c);
                        }
                      }),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 12),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  value: _lowAdherence,
                  activeColor: KuraColors.warning,
                  title: const Text(
                    'Baja adherencia al tratamiento indicado desde la visita anterior',
                    style: TextStyle(fontSize: 13),
                  ),
                  onChanged: (v) => setState(() => _lowAdherence = v ?? false),
                ),
                const SizedBox(height: 20),
                Text('Foto actual', style: _sectionStyle(context)),
                const SizedBox(height: 12),
                if (_photoBytes != null)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.memory(_photoBytes!, height: 200, fit: BoxFit.cover),
                  )
                else
                  Container(
                    height: 140,
                    decoration: BoxDecoration(
                      color: KuraColors.chipBg,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: KuraColors.borderSubtle),
                    ),
                    child: const Center(
                      child: Icon(Icons.image_outlined, size: 32, color: KuraColors.darkText),
                    ),
                  ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  icon: const Icon(Icons.add_a_photo_outlined, size: 18),
                  label: Text(_photo == null ? 'Agregar foto' : 'Cambiar foto'),
                  onPressed: _pickPhoto,
                ),
                const SizedBox(height: 28),
                FilledButton.icon(
                  icon: _saving
                      ? const SizedBox(
                          height: 16,
                          width: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.check_circle_outline),
                  label: Text(_saving ? 'Guardando...' : 'Guardar seguimiento'),
                  style: FilledButton.styleFrom(
                    backgroundColor: KuraColors.primary,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  onPressed: (_saving || _lengthCm <= 0 || _widthCm <= 0)
                      ? null
                      : () => _save(context, session),
                ),
                if (_lengthCm <= 0 || _widthCm <= 0)
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Text(
                      'Completa al menos largo y ancho para guardar.',
                      style: TextStyle(fontSize: 12, color: KuraColors.danger),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  TextStyle? _sectionStyle(BuildContext context) => Theme.of(context)
      .textTheme
      .titleMedium
      ?.copyWith(fontWeight: FontWeight.w700);

  Future<void> _save(BuildContext context, SessionState session) async {
    setState(() => _saving = true);
    final repo = await DataRepository.instance();
    final staffId = session.user?.staffId;
    if (staffId == null) {
      setState(() => _saving = false);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No se encontró personal sanitario vinculado a tu cuenta.')),
        );
      }
      return;
    }

    try {
      final wound = repo.getWound(widget.woundId);
      if (wound == null) {
        throw StateError('Herida no encontrada.');
      }
      // Reutiliza el sitio principal del paciente (o el primero disponible)
      // igual que ConsultationHubScreen, ya que este formulario no repite
      // esa pregunta para una visita de seguimiento breve.
      final patient = repo.getPatient(widget.patientId);
      final sites = repo.listSites();
      final siteId = patient?.primarySiteId ?? (sites.isNotEmpty ? sites.first.id : null);
      if (siteId == null) {
        throw StateError('No hay sitios configurados.');
      }

      final consultation = await repo.createConsultation(
        patientId: widget.patientId,
        staffId: staffId,
        siteId: siteId,
        visitType: VisitType.seguimiento,
        visitDate: _visitDate,
        isDraft: false,
      );

      final measurement = await repo.createMeasurement({
        'wound_id': widget.woundId,
        'consultation_id': consultation.id,
        'measured_at': _visitDate.toIso8601String().substring(0, 10),
        'length_cm': _lengthCm,
        'width_cm': _widthCm,
        'area_cm2': _areaCm2,
        'depth_cm': _depthCm,
        'tunneling': _tunneling,
        'undermining': _undermining,
        'granulation_pct': _granulacion,
        'slough_pct': _esfacelo,
        'necrosis_pct': _necrosis,
        'epithelialization_pct': _epitelizacion,
        'captured_before_debridement': _capturedBeforeDebridement,
      });

      await repo.createAssessment({
        'consultation_id': consultation.id,
        'wound_id': widget.woundId,
        'exudate_amount': _exudadoCantidad.name,
        'exudate_type': _exudadoTipo.name,
        'infection_criteria': _infeccionCriterios.map((e) => e.name).toList(),
        'low_adherence': _lowAdherence,
      });

      if (_photoBytes != null) {
        final storagePath = await PhotoUploadService.uploadWoundPhoto(
          woundId: widget.woundId,
          consultationId: consultation.id,
          bytes: _photoBytes!,
          fileName: _photo?.name ?? 'seguimiento.jpg',
        );
        await repo.createPhoto({
          'wound_id': widget.woundId,
          'consultation_id': consultation.id,
          'measurement_id': measurement.id,
          'storage_path': storagePath,
          'taken_at': _visitDate.toIso8601String(),
        });
      }
      // No se hace ningun INSERT manual a audit_log: la bitacora de
      // consultations/wound_measurements la genera el trigger AFTER INSERT
      // de Postgres (audit_trigger_fn, bug #5 ya corregido en el
      // repositorio); wound_assessments/wound_photos no auditan por diseno.
    } catch (e, st) {
      debugPrint('Error al guardar seguimiento: $e\n$st');
      if (context.mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo guardar el seguimiento: $e')),
        );
      }
      return;
    }

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Seguimiento registrado correctamente.')),
      );
      // Esta pantalla se navega declarativamente via GoRouter (no
      // Navigator.push), por lo que el regreso tambien debe ser un
      // context.go explicito a la pantalla de seguimiento (no
      // Navigator.pop, que no aplica a rutas declarativas de GoRouter).
      context.go('/patients/${widget.patientId}/wound/${widget.woundId}/follow-up');
    }
  }
}
