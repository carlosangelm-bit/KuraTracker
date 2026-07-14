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
import '../../models/treatment_plan.dart';
import '../../services/data_repository.dart';
import '../../services/photo_upload_service.dart';
import '../wound_capture/widgets/bed_composition_sliders.dart';

/// Formulario de "Registrar seguimiento" (visita visit_type='seguimiento'
/// ligada a una herida existente).
///
/// Alineado con los protocolos clinicos Kura+ (Prioridad 1 de la
/// instruccion "Alinear KuraTracker con los protocolos clinicos Kura+"):
/// reevaluacion integral (medidas 2D/3D + composicion del lecho + olor +
/// borde + piel perilesional + EVA de dolor + infeccion + adherencia),
/// medicion manual para socavamiento/tunelizacion/circunferencial/
/// irregular, 2 fotografias de seguimiento (despues de limpiar sin
/// medicion + con medicion) y nota de seguimiento obligatoria (tipo de
/// atencion, procedimiento, material, evolucion, firma + cedula).
///
/// Persiste, en este orden:
///   1. consultations (visit_type='seguimiento' + nota de seguimiento)
///   2. wound_measurements (2D/3D, composicion del lecho, nota manual)
///   3. wound_assessments (evaluacion clinica completa + adherencia)
///   4. wound_photos x2 ("despues_limpiar" + "con_medicion"), tras subir
///      los bytes a Supabase Storage (o codificarlos como data URL en modo
///      demo local).
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
  final _volumeCtrl = TextEditingController();
  final _manualMeasurementCtrl = TextEditingController();
  bool _tunneling = false;
  bool _undermining = false;

  double _granulacion = 100;
  double _esfacelo = 0;
  double _necrosis = 0;
  double _epitelizacion = 0;
  bool _capturedBeforeDebridement = true;

  // ---- Evaluacion clinica (reevaluacion integral, PROTOC~3 UPD) ----
  String _edema = 'ninguno';
  bool _pain = false;
  String _painType = 'nociceptivo';
  String _painDuration = 'agudo';
  int _painVas = 0;
  ExudadoCantidad _exudadoCantidad = ExudadoCantidad.escaso;
  ExudadoTipo _exudadoTipo = ExudadoTipo.seroso;
  final Set<InfeccionCriterioIwii> _infeccionCriterios = {};
  String _odor = 'ninguno';
  String _woundEdge = 'definido';
  final Set<PielPerilesionalEstado> _perilesionalSkin = {};
  bool _lowAdherence = false;

  // ---- Fotografia de seguimiento (Protocolo de Fotografias SS1.2): 2 fotos
  // ----   1ra despues de limpiar (sin medicion), 2da con medicion.
  XFile? _photoAfterCleaning;
  Uint8List? _photoAfterCleaningBytes;
  XFile? _photoWithMeasurement;
  Uint8List? _photoWithMeasurementBytes;
  final _picker = ImagePicker();

  // ---- Nota de seguimiento obligatoria (Instructivo de Archivo) ----
  final _careTypeCtrl = TextEditingController();
  final _procedureDescCtrl = TextEditingController();
  final _materialsUsedCtrl = TextEditingController();
  final _evolutionCtrl = TextEditingController();
  final _signedByCtrl = TextEditingController();
  final _signedLicenseCtrl = TextEditingController();
  bool _prefilledSignature = false;

  bool _saving = false;

  double get _lengthCm => double.tryParse(_lengthCtrl.text.replaceAll(',', '.')) ?? 0;
  double get _widthCm => double.tryParse(_widthCtrl.text.replaceAll(',', '.')) ?? 0;
  double get _depthCm => double.tryParse(_depthCtrl.text.replaceAll(',', '.')) ?? 0;
  double get _areaCm2 => _lengthCm * _widthCm;
  double? get _volumeCm3 => double.tryParse(_volumeCtrl.text.replaceAll(',', '.'));
  // Herida profunda (Protocolo de Fotografias/Medicion): a mayor profundidad
  // se activa el modo de medicion 3D (volumen) ademas del 2D.
  bool get _isDeepWound => _depthCm >= 0.5;

  bool get _followUpNoteComplete =>
      _careTypeCtrl.text.trim().isNotEmpty &&
      _procedureDescCtrl.text.trim().isNotEmpty &&
      _materialsUsedCtrl.text.trim().isNotEmpty &&
      _evolutionCtrl.text.trim().isNotEmpty &&
      _signedByCtrl.text.trim().isNotEmpty &&
      _signedLicenseCtrl.text.trim().isNotEmpty;

  Future<void> _pickPhoto({required bool withMeasurement}) async {
    try {
      final file = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
      if (file == null) return;
      final bytes = await file.readAsBytes();
      setState(() {
        if (withMeasurement) {
          _photoWithMeasurement = file;
          _photoWithMeasurementBytes = bytes;
        } else {
          _photoAfterCleaning = file;
          _photoAfterCleaningBytes = bytes;
        }
      });
    } catch (_) {
      // Sin soporte de camara/galeria en este dispositivo/navegador.
    }
  }

  void _prefillSignatureIfNeeded(SessionState session, DataRepository? repo) {
    if (_prefilledSignature) return;
    _prefilledSignature = true;
    final name = session.user?.fullName;
    if (name != null && name.isNotEmpty) {
      _signedByCtrl.text = name;
    }
    final staffId = session.user?.staffId;
    if (repo != null && staffId != null) {
      final cedula = repo.getStaff(staffId)?.cedulaProfesional;
      if (cedula != null && cedula.isNotEmpty) {
        _signedLicenseCtrl.text = cedula;
      }
    }
  }

  @override
  void dispose() {
    _lengthCtrl.dispose();
    _widthCtrl.dispose();
    _depthCtrl.dispose();
    _volumeCtrl.dispose();
    _manualMeasurementCtrl.dispose();
    _careTypeCtrl.dispose();
    _procedureDescCtrl.dispose();
    _materialsUsedCtrl.dispose();
    _evolutionCtrl.dispose();
    _signedByCtrl.dispose();
    _signedLicenseCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider);
    final repoAsync = ref.watch(dataRepositoryProvider);
    _prefillSignatureIfNeeded(session, repoAsync.asData?.value);

    final canSave = !_saving &&
        _lengthCm > 0 &&
        _widthCm > 0 &&
        _photoAfterCleaningBytes != null &&
        _photoWithMeasurementBytes != null &&
        _followUpNoteComplete;

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
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text('Área calculada (2D): ${_areaCm2.toStringAsFixed(1)} cm²',
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                if (_isDeepWound) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: KuraColors.chipBg,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Herida profunda: medición 3D (Protocolo de Fotografías/Medición)',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _volumeCtrl,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: const InputDecoration(labelText: 'Volumen (cm³)'),
                        ),
                      ],
                    ),
                  ),
                ],
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
                if (_tunneling || _undermining) ...[
                  const SizedBox(height: 8),
                  TextField(
                    controller: _manualMeasurementCtrl,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'Medición manual (hisopo/regla)',
                      hintText: 'Ej. socavamiento 2cm a las 3-6h, tunelización 4cm a las 9h...',
                    ),
                  ),
                ],
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
                DropdownButtonFormField<String>(
                  value: _edema,
                  decoration: const InputDecoration(labelText: 'Edema'),
                  items: const [
                    DropdownMenuItem(value: 'ninguno', child: Text('Ninguno')),
                    DropdownMenuItem(value: 'leve', child: Text('Leve')),
                    DropdownMenuItem(value: 'moderado', child: Text('Moderado')),
                    DropdownMenuItem(value: 'severo', child: Text('Severo')),
                  ],
                  onChanged: (v) => setState(() => _edema = v ?? 'ninguno'),
                ),
                const SizedBox(height: 12),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Dolor'),
                  value: _pain,
                  activeColor: KuraColors.primary,
                  onChanged: (v) => setState(() => _pain = v),
                ),
                if (_pain) ...[
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          value: _painType,
                          decoration: const InputDecoration(labelText: 'Tipo de dolor'),
                          items: const [
                            DropdownMenuItem(value: 'nociceptivo', child: Text('Nociceptivo')),
                            DropdownMenuItem(value: 'neuropatico', child: Text('Neuropático')),
                            DropdownMenuItem(value: 'isquemico', child: Text('Isquémico')),
                            DropdownMenuItem(value: 'mixto', child: Text('Mixto')),
                          ],
                          onChanged: (v) => setState(() => _painType = v ?? _painType),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          value: _painDuration,
                          decoration: const InputDecoration(labelText: 'Duración'),
                          items: const [
                            DropdownMenuItem(value: 'agudo', child: Text('Agudo')),
                            DropdownMenuItem(value: 'cronico', child: Text('Crónico')),
                            DropdownMenuItem(value: 'intermitente', child: Text('Intermitente')),
                          ],
                          onChanged: (v) => setState(() => _painDuration = v ?? _painDuration),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text('Escala Visual Analógica (EVA): $_painVas/10',
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  Slider(
                    value: _painVas.toDouble(),
                    min: 0,
                    max: 10,
                    divisions: 10,
                    activeColor: KuraColors.primary,
                    label: '$_painVas',
                    onChanged: (v) => setState(() => _painVas = v.round()),
                  ),
                ],
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<ExudadoTipo>(
                        value: _exudadoTipo,
                        decoration: const InputDecoration(labelText: 'Exudado (tipo)'),
                        items: ExudadoTipo.values
                            .map((e) => DropdownMenuItem(value: e, child: Text(e.name)))
                            .toList(),
                        onChanged: (v) => setState(() => _exudadoTipo = v ?? _exudadoTipo),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: DropdownButtonFormField<ExudadoCantidad>(
                        value: _exudadoCantidad,
                        decoration: const InputDecoration(labelText: 'Exudado (cantidad)'),
                        items: ExudadoCantidad.values
                            .map((e) => DropdownMenuItem(value: e, child: Text(e.name)))
                            .toList(),
                        onChanged: (v) =>
                            setState(() => _exudadoCantidad = v ?? _exudadoCantidad),
                      ),
                    ),
                  ],
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
                      selectedColor: KuraColors.danger.withOpacity(0.15),
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
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        value: _odor,
                        decoration: const InputDecoration(labelText: 'Olor'),
                        items: const [
                          DropdownMenuItem(value: 'ninguno', child: Text('Ninguno')),
                          DropdownMenuItem(value: 'leve', child: Text('Leve')),
                          DropdownMenuItem(value: 'moderado', child: Text('Moderado')),
                          DropdownMenuItem(value: 'fuerte', child: Text('Fuerte')),
                        ],
                        onChanged: (v) => setState(() => _odor = v ?? 'ninguno'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        value: _woundEdge,
                        decoration: const InputDecoration(labelText: 'Borde de la herida'),
                        items: const [
                          DropdownMenuItem(value: 'definido', child: Text('Definido')),
                          DropdownMenuItem(value: 'irregular', child: Text('Irregular')),
                          DropdownMenuItem(value: 'dehiscente', child: Text('Dehiscente')),
                          DropdownMenuItem(value: 'macerado', child: Text('Macerado')),
                          DropdownMenuItem(value: 'epibole', child: Text('Epíbole (enrollado)')),
                        ],
                        onChanged: (v) => setState(() => _woundEdge = v ?? 'definido'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                const Text('Piel perilesional', style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: PielPerilesionalEstado.values.map((p) {
                    final selected = _perilesionalSkin.contains(p);
                    return FilterChip(
                      label: Text(p.name, style: const TextStyle(fontSize: 12)),
                      selected: selected,
                      selectedColor: KuraColors.warning.withOpacity(0.2),
                      onSelected: (v) => setState(() {
                        if (v) {
                          _perilesionalSkin.add(p);
                        } else {
                          _perilesionalSkin.remove(p);
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
                Text('Fotografía de seguimiento (2 fotos requeridas)', style: _sectionStyle(context)),
                const SizedBox(height: 4),
                const Text(
                  'Protocolo de Fotografías §1.2: 1ª después de limpiar (sin medición), 2ª con medición.',
                  style: TextStyle(fontSize: 12, color: KuraColors.darkText),
                ),
                const SizedBox(height: 12),
                _photoTile(
                  label: '1. Después de limpiar (sin medición) *',
                  bytes: _photoAfterCleaningBytes,
                  hasPhoto: _photoAfterCleaning != null,
                  onPick: () => _pickPhoto(withMeasurement: false),
                ),
                const SizedBox(height: 12),
                _photoTile(
                  label: '2. Con medición *',
                  bytes: _photoWithMeasurementBytes,
                  hasPhoto: _photoWithMeasurement != null,
                  onPick: () => _pickPhoto(withMeasurement: true),
                ),
                const SizedBox(height: 20),
                Text('Nota de seguimiento (obligatoria)', style: _sectionStyle(context)),
                const SizedBox(height: 4),
                const Text(
                  'Instructivo de Archivo: sin campos vacíos. Requiere firma y cédula profesional de quien atiende.',
                  style: TextStyle(fontSize: 12, color: KuraColors.darkText),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _careTypeCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Tipo de atención *',
                    hintText: 'Ej. curación ambulatoria, visita domiciliaria...',
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _procedureDescCtrl,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Descripción del procedimiento *',
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _materialsUsedCtrl,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Material utilizado *',
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _evolutionCtrl,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Evolución *',
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _signedByCtrl,
                        decoration: const InputDecoration(labelText: 'Firma (nombre) *'),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: _signedLicenseCtrl,
                        decoration: const InputDecoration(labelText: 'Cédula profesional *'),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                  ],
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
                  onPressed: canSave ? () => _save(context, session) : null,
                ),
                if (!canSave && !_saving)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      _saveBlockedReason(),
                      style: const TextStyle(fontSize: 12, color: KuraColors.danger),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _saveBlockedReason() {
    if (_lengthCm <= 0 || _widthCm <= 0) return 'Completa al menos largo y ancho para guardar.';
    if (_photoAfterCleaningBytes == null || _photoWithMeasurementBytes == null) {
      return 'Se requieren las 2 fotografías de seguimiento (después de limpiar + con medición).';
    }
    if (!_followUpNoteComplete) {
      return 'Completa todos los campos de la nota de seguimiento (sin campos vacíos).';
    }
    return '';
  }

  Widget _photoTile({
    required String label,
    required Uint8List? bytes,
    required bool hasPhoto,
    required VoidCallback onPick,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        if (bytes != null)
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.memory(bytes, height: 160, fit: BoxFit.cover),
          )
        else
          Container(
            height: 120,
            decoration: BoxDecoration(
              color: KuraColors.chipBg,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: KuraColors.borderSubtle),
            ),
            child: const Center(
              child: Icon(Icons.image_outlined, size: 28, color: KuraColors.darkText),
            ),
          ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          icon: const Icon(Icons.add_a_photo_outlined, size: 18),
          label: Text(hasPhoto ? 'Cambiar foto' : 'Agregar foto'),
          onPressed: onPick,
        ),
      ],
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
        followUpCareType: _careTypeCtrl.text.trim(),
        followUpProcedureDesc: _procedureDescCtrl.text.trim(),
        followUpMaterialsUsed: _materialsUsedCtrl.text.trim(),
        followUpEvolution: _evolutionCtrl.text.trim(),
        followUpSignedBy: _signedByCtrl.text.trim(),
        followUpSignedLicense: _signedLicenseCtrl.text.trim(),
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
        'volume_cm3': _isDeepWound ? _volumeCm3 : null,
        'manual_measurement_note': _manualMeasurementCtrl.text.trim().isEmpty
            ? null
            : _manualMeasurementCtrl.text.trim(),
      });

      await repo.createAssessment({
        'consultation_id': consultation.id,
        'wound_id': widget.woundId,
        'edema': _edema,
        'pain': _pain,
        'pain_type': _pain ? _painType : null,
        'pain_duration': _pain ? _painDuration : null,
        'pain_vas': _pain ? _painVas : 0,
        'exudate_amount': _exudadoCantidad.name,
        'exudate_type': _exudadoTipo.name,
        'infection_criteria': _infeccionCriterios.map((e) => e.name).toList(),
        'odor': _odor,
        'wound_edge': _woundEdge,
        'perilesional_skin': _perilesionalSkin.map((e) => e.name).toList(),
        'low_adherence': _lowAdherence,
      });

      // 2 fotografias de seguimiento (Protocolo de Fotografias SS1.2):
      // 1ra despues de limpiar (sin medicion), 2da con medicion.
      final afterCleaningPath = await PhotoUploadService.uploadWoundPhoto(
        woundId: widget.woundId,
        consultationId: consultation.id,
        bytes: _photoAfterCleaningBytes!,
        fileName: _photoAfterCleaning?.name ?? 'seguimiento_despues_limpiar.jpg',
      );
      await repo.createPhoto({
        'wound_id': widget.woundId,
        'consultation_id': consultation.id,
        'measurement_id': measurement.id,
        'storage_path': afterCleaningPath,
        'taken_at': _visitDate.toIso8601String(),
        'photo_stage': PhotoStage.despuesLimpiar.dbValue,
      });

      final withMeasurementPath = await PhotoUploadService.uploadWoundPhoto(
        woundId: widget.woundId,
        consultationId: consultation.id,
        bytes: _photoWithMeasurementBytes!,
        fileName: _photoWithMeasurement?.name ?? 'seguimiento_con_medicion.jpg',
      );
      await repo.createPhoto({
        'wound_id': widget.woundId,
        'consultation_id': consultation.id,
        'measurement_id': measurement.id,
        'storage_path': withMeasurementPath,
        'taken_at': _visitDate.toIso8601String(),
        'photo_stage': PhotoStage.conMedicion.dbValue,
      });
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
