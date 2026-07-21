import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../../core/providers/session_provider.dart';
import '../../core/theme/kura_theme.dart';
import '../../core/utils/wound_volume.dart';
import '../../engine/kura_protocol_engine.dart';
import '../../engine/models/kura_engine_enums.dart';
import '../../engine/models/kura_engine_input.dart';
import '../../models/app_user.dart';
import '../../models/consultation.dart';
import '../../models/note_option_catalog.dart';
import '../../models/site.dart';
import '../../models/treatment_plan.dart';
import '../../services/data_repository.dart';
import '../../services/photo_upload_service.dart';
import '../wound_capture/widgets/bed_composition_sliders.dart';

/// Formulario de "Registrar seguimiento" (visita visit_type='seguimiento'
/// ligada a una herida existente).
///
/// Alineado con los protocolos clinicos Kura+ (Prioridad 1 de la
/// instruccion "Alinear KuraTracker con los protocolos clinicos Kura+",
/// incluyendo el refinamiento UX/fidelidad clinica posterior):
///   1. Reevaluacion integral (medidas 2D/3D + composicion del lecho +
///      olor + borde + piel perilesional + EVA de dolor + infeccion +
///      adherencia), medicion manual para socavamiento/tunelizacion.
///   2. Las 2 fotografias de seguimiento se solicitan EN el punto clinico
///      correspondiente del flujo (Protocolo de Fotografias y Medicion),
///      no al final: la foto "despues de limpiar (sin medicion)" se pide
///      justo antes/junto a la composicion del lecho (que tambien exige
///      capturarse antes de curar/desbridar), y la foto "con medicion" se
///      pide inmediatamente despues de registrar las medidas 2D/3D.
///   3. Nota de seguimiento obligatoria cuyos conceptos (tipo de atencion,
///      procedimiento, material, evolucion) se seleccionan como chips
///      desde un catalogo administrado por el centro (note_option_catalog,
///      admin-only via Configuracion), con "Otro" como texto libre que
///      solo se persiste al catalogo si quien captura es admin.
///   4. Firma (nombre) y cedula profesional se muestran de solo lectura,
///      tomadas del registro `staff` del profesional en sesion — nunca se
///      piden como campos editables en cada nota.
///
/// Lookup metodo del regimen (RegimenComponente.metodo, tal cual lo emite
/// KuraTreatmentRulesEngine, kura_rules_v2) -> KuraTag del catalogo (Parte
/// D, toggle premium "Utilizar protocolo Kura+"). Solo los metodos con un
/// concepto de catalogo claramente equivalente tienen tag; los metodos de
/// manejo especializado por tipo de herida traumatica/quirurgica/neuropatica
/// (sin equivalente 1:1 generico en el catalogo) mapean a `null` a
/// proposito, para que NUNCA se auto-seleccione nada en esos casos (los
/// conceptos sin etiqueta o personalizados jamas se auto-seleccionan).
const Map<String, KuraTag?> kKuraMethodToTag = {
  'Limpieza de la herida': KuraTag.limpieza,
  'Desbridamiento': KuraTag.desbridamiento,
  'Relleno de cavidad': KuraTag.rellenoCavidad,
  'Apósito': KuraTag.aposito,
  'Protección de la piel': KuraTag.proteccionPiel,
  'Tratamiento para la infección': KuraTag.antimicrobiano,
  'Educación al paciente/cuidador': KuraTag.educacion,
  'Dispositivo de descarga': KuraTag.descarga,
  'Terapia compresiva': KuraTag.compresion,
  'Manejo neuropático': null,
  'Manejo de herida quirúrgica': null,
  'Manejo de herida por mordedura': null,
  'Manejo de herida por arma de fuego': null,
  'Manejo de herida por aplastamiento': null,
  'Manejo de herida punzocortante': null,
  'Manejo de herida traumática': null,
};

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
  // Volumen (feat/volume-kundin-charts): _volumeCtrl ya existia (modo 3D
  // manual); ahora se pre-llena y re-sincroniza con el auto-calculo de
  // Kundin (L x A x P x 0.327) cada vez que cambian largo/ancho/profundidad,
  // mientras el clinico no lo haya sobrescrito a mano. _volumeAutoFollowing
  // decide si el campo debe seguir el auto-calculo (true, por defecto) o ya
  // fue editado manualmente (false, hasta que el clinico borre el campo).
  bool _volumeAutoFollowing = true;
  final _manualMeasurementCtrl = TextEditingController();
  final _clinicalNotesCtrl = TextEditingController();
  bool _tunneling = false;
  bool _undermining = false;

  double _granulacion = 100;
  double _esfacelo = 0;
  double _necrosis = 0;
  double _epitelizacion = 0;
  bool _capturedBeforeDebridement = true;

  // ---- Evaluacion clinica (reevaluacion integral) ----
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

  // ---- Fotografia de seguimiento (Protocolo de Fotografias y Medicion):
  // 2 fotos, cada una solicitada en su momento clinico real dentro del
  // flujo (no al final): 1ra despues de limpiar (sin medicion) junto al
  // paso de composicion del lecho/limpieza; 2da con medicion, justo
  // despues del bloque de medidas 2D/3D.
  XFile? _photoAfterCleaning;
  Uint8List? _photoAfterCleaningBytes;
  XFile? _photoWithMeasurement;
  Uint8List? _photoWithMeasurementBytes;
  final _picker = ImagePicker();

  // ---- Nota de seguimiento obligatoria (conceptos desde catalogo del
  // centro; "Otro" como texto libre por campo) ----
  // "Tipo de atencion" y "Evolucion" siguen single-select (una unica
  // opcion o "Otro"). "Descripcion del procedimiento" y "Material
  // utilizado" son multi-seleccion (Parte A, feat/followup-protocol-suggest):
  // el clinico puede marcar varios conceptos a la vez; se concatenan con
  // "; " al guardar (ver _procedureDescFinal/_materialsUsedFinal). El
  // sentinela kOtherOptionValue puede convivir como UN elemento mas del
  // Set junto a otros conceptos ya elegidos.
  String? _careTypeSelected;
  final _careTypeOtherCtrl = TextEditingController();
  final Set<String> _procedureDescSelected = {};
  final _procedureDescOtherCtrl = TextEditingController();
  final Set<String> _materialsUsedSelected = {};
  final _materialsUsedOtherCtrl = TextEditingController();
  String? _evolutionSelected;
  final _evolutionOtherCtrl = TextEditingController();

  // Marca (Parte D, toggle premium "Utilizar protocolo Kura+"): true si
  // alguno de los conceptos actualmente marcados en procedureDesc/
  // materialsUsed proviene de la pre-seleccion automatica del motor (para
  // mostrar la nota discreta "Sugerido por Protocolo Kura+ · editable").
  // Se limpia tan pronto el clinico toca manualmente un chip (todo sigue
  // siendo editable/quitable, esto es solo informativo).
  bool _kuraProtocolSuggestionActive = false;
  bool _useKuraProtocol = false;
  bool _kuraProtocolLoading = false;

  // Firma/cedula: solo lectura, resueltas desde el staff de la sesion (no
  // se piden como campos editables en cada nota).
  String? _signedByReadOnly;
  String? _signedLicenseReadOnly;

  bool _saving = false;

  double get _lengthCm => double.tryParse(_lengthCtrl.text.replaceAll(',', '.')) ?? 0;
  double get _widthCm => double.tryParse(_widthCtrl.text.replaceAll(',', '.')) ?? 0;
  double get _depthCm => double.tryParse(_depthCtrl.text.replaceAll(',', '.')) ?? 0;
  double get _areaCm2 => _lengthCm * _widthCm;
  double? get _volumeCm3 => double.tryParse(_volumeCtrl.text.replaceAll(',', '.'));
  // Herida profunda (Protocolo de Fotografias/Medicion): a mayor profundidad
  // se activa el modo de medicion 3D (volumen) ademas del 2D.
  bool get _isDeepWound => _depthCm >= 0.5;
  // Volumen auto-calculado por Kundin a partir de las medidas actuales
  // (feat/volume-kundin-charts). null si la herida es superficial
  // (depthCm <= 0): el volumen 3D no aplica.
  double? get _autoVolumeCm3 => WoundVolumeCalculator.kundin(
        lengthCm: _lengthCm,
        widthCm: _widthCm,
        depthCm: _depthCm,
      );
  // true si el valor actualmente en _volumeCtrl difiere del auto-calculo de
  // Kundin para las medidas actuales (el clinico lo sobrescribio a mano).
  bool get _isVolumeManuallyOverridden => WoundVolumeCalculator.isManualOverride(
        storedVolumeCm3: _volumeCm3,
        autoCalculatedCm3: _autoVolumeCm3,
      );

  String get _careTypeFinal =>
      _careTypeSelected == kOtherOptionValue ? _careTypeOtherCtrl.text.trim() : (_careTypeSelected ?? '');

  /// Concatena (separador "; ") los conceptos elegidos en un campo
  /// multi-seleccion (Parte A). Si "Otro" esta activo (presente en el
  /// Set), combina su texto libre junto con el resto de los conceptos
  /// elegidos, en el mismo orden en que aparecen los chips del catalogo
  /// (mas "Otro" al final si esta activo), para que el texto persistido
  /// sea legible y predecible.
  String _joinMultiSelect(Set<String> selected, TextEditingController otherCtrl) {
    final parts = <String>[
      ...selected.where((s) => s != kOtherOptionValue),
      if (selected.contains(kOtherOptionValue) && otherCtrl.text.trim().isNotEmpty)
        otherCtrl.text.trim(),
    ];
    return parts.join('; ');
  }

  String get _procedureDescFinal => _joinMultiSelect(_procedureDescSelected, _procedureDescOtherCtrl);
  String get _materialsUsedFinal => _joinMultiSelect(_materialsUsedSelected, _materialsUsedOtherCtrl);

  String get _evolutionFinal =>
      _evolutionSelected == kOtherOptionValue ? _evolutionOtherCtrl.text.trim() : (_evolutionSelected ?? '');

  /// Validacion por campo multi-seleccion: >=1 concepto marcado, y si
  /// "Otro" es el UNICO elegido, su texto libre no puede estar vacio
  /// (mismo criterio que antes exigia para el single-select).
  bool _multiSelectComplete(Set<String> selected, TextEditingController otherCtrl) {
    if (selected.isEmpty) return false;
    final hasNonOther = selected.any((s) => s != kOtherOptionValue);
    if (hasNonOther) return true;
    // Solo "Otro" esta marcado: exige texto no vacio.
    return otherCtrl.text.trim().isNotEmpty;
  }

  bool get _procedureDescComplete => _multiSelectComplete(_procedureDescSelected, _procedureDescOtherCtrl);
  bool get _materialsUsedComplete => _multiSelectComplete(_materialsUsedSelected, _materialsUsedOtherCtrl);

  bool get _followUpNoteComplete =>
      _careTypeFinal.isNotEmpty &&
      _procedureDescComplete &&
      _materialsUsedComplete &&
      _evolutionFinal.isNotEmpty;

  Future<void> _pickPhoto({required bool withMeasurement}) async {
    try {
      final file = await _picker.pickImage(
          source: ImageSource.gallery, imageQuality: 85, maxWidth: 1600, maxHeight: 1600);
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

  bool _resolvedSignature = false;

  /// Resuelve firma/cedula de solo lectura desde el registro `staff` del
  /// profesional en sesion (nunca se piden como campos editables). Si el
  /// staff no tiene cedula registrada, se deja null: la UI muestra un
  /// aviso para completarla una vez en Administración, en vez de pedirla
  /// aqui.
  void _resolveSignatureIfNeeded(SessionState session, DataRepository? repo) {
    if (_resolvedSignature) return;
    _resolvedSignature = true;
    _signedByReadOnly = session.user?.fullName;
    final staffId = session.user?.staffId;
    if (repo != null && staffId != null) {
      _signedLicenseReadOnly = repo.getStaff(staffId)?.cedulaProfesional;
    }
  }

  @override
  void dispose() {
    _lengthCtrl.dispose();
    _widthCtrl.dispose();
    _depthCtrl.dispose();
    _volumeCtrl.dispose();
    _manualMeasurementCtrl.dispose();
    _clinicalNotesCtrl.dispose();
    _careTypeOtherCtrl.dispose();
    _procedureDescOtherCtrl.dispose();
    _materialsUsedOtherCtrl.dispose();
    _evolutionOtherCtrl.dispose();
    super.dispose();
  }

  /// Mantiene _volumeCtrl sincronizado con el auto-calculo de Kundin
  /// mientras el clinico no lo haya sobrescrito a mano (_volumeAutoFollowing).
  /// Se llama tras cualquier cambio de largo/ancho/profundidad
  /// (feat/volume-kundin-charts).
  void _syncVolumeField() {
    // Herida vuelta superficial (profundidad 0/null): el volumen 3D no
    // aplica, sin importar si antes se habia editado a mano.
    if (!_isDeepWound) {
      _volumeAutoFollowing = true;
      if (_volumeCtrl.text.isNotEmpty) _volumeCtrl.text = '';
      return;
    }
    if (!_volumeAutoFollowing) return;
    final auto = _autoVolumeCm3;
    final text = auto == null ? '' : auto.toStringAsFixed(2);
    if (_volumeCtrl.text != text) {
      _volumeCtrl.text = text;
    }
  }

  void _onVolumeFieldChanged(String v) {
    if (v.trim().isEmpty) {
      // Campo vaciado por el clinico: vuelve a seguir el auto-calculo.
      setState(() => _volumeAutoFollowing = true);
      return;
    }
    setState(() => _volumeAutoFollowing = false);
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider);
    final repoAsync = ref.watch(dataRepositoryProvider);
    final repo = repoAsync.asData?.value;
    _resolveSignatureIfNeeded(session, repo);

    final canSave = !_saving &&
        _lengthCm > 0 &&
        _widthCm > 0 &&
        _photoAfterCleaningBytes != null &&
        _photoWithMeasurementBytes != null &&
        _followUpNoteComplete &&
        _signedByReadOnly != null &&
        _signedByReadOnly!.isNotEmpty &&
        _signedLicenseReadOnly != null &&
        _signedLicenseReadOnly!.isNotEmpty;

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
                Text('Fecha de la visita', style: _sectionStyle(context)),
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

                // -----------------------------------------------------------------
                // PASO 1: Composicion del lecho + limpieza (se captura ANTES de
                // curar/desbridar) -> justo aqui, INMEDIATAMENTE antes de este
                // paso, se pide la 1a foto de seguimiento (despues de limpiar,
                // sin medicion). El orden refleja la secuencia real del
                // Protocolo de Fotografias y Medicion: limpiar -> fotografiar
                // sin medir -> evaluar el lecho -> medir -> fotografiar con
                // medicion.
                // -----------------------------------------------------------------
                const SizedBox(height: 24),
                Text('Fotografía 1: después de limpiar', style: _sectionStyle(context)),
                const SizedBox(height: 4),
                const Text(
                  'Protocolo de Fotografías §1.2: se toma justo después de limpiar '
                  'la herida, ANTES de evaluar el lecho o medir. Sin medición.',
                  style: TextStyle(fontSize: 12, color: KuraColors.darkText),
                ),
                const SizedBox(height: 12),
                _photoTile(
                  label: '1. Después de limpiar (sin medición) *',
                  bytes: _photoAfterCleaningBytes,
                  hasPhoto: _photoAfterCleaning != null,
                  onPick: () => _pickPhoto(withMeasurement: false),
                ),

                const SizedBox(height: 24),
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

                // -----------------------------------------------------------------
                // PASO 2: Medicion 2D/3D/manual -> inmediatamente despues, se
                // pide la 2a foto (con medicion), tal como indica el protocolo.
                // -----------------------------------------------------------------
                const SizedBox(height: 24),
                Text('Medición', style: _sectionStyle(context)),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _lengthCtrl,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(labelText: 'Largo (cm) *'),
                        onChanged: (_) => setState(_syncVolumeField),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: _widthCtrl,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(labelText: 'Ancho (cm) *'),
                        onChanged: (_) => setState(_syncVolumeField),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: _depthCtrl,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(labelText: 'Profundidad (cm)'),
                        onChanged: (_) => setState(_syncVolumeField),
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
                          'Herida profunda: volumen (fórmula de Kundin)',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _volumeCtrl,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: const InputDecoration(
                            labelText: 'Volumen (cm³)',
                            helperText: 'Auto-calculado: Largo × Ancho × Profundidad × 0.327',
                          ),
                          onChanged: (v) => _onVolumeFieldChanged(v),
                        ),
                        if (_isVolumeManuallyOverridden) ...[
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              Icon(Icons.edit_note, size: 16, color: KuraColors.warning),
                              const SizedBox(width: 4),
                              Text('✎ Volumen ajustado manualmente',
                                  style: TextStyle(
                                      fontSize: 11,
                                      color: KuraColors.warning,
                                      fontWeight: FontWeight.w600)),
                            ],
                          ),
                        ],
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

                const SizedBox(height: 24),
                Text('Fotografía 2: con medición', style: _sectionStyle(context)),
                const SizedBox(height: 4),
                const Text(
                  'Protocolo de Fotografías §1.2: se toma justo después de registrar '
                  'las medidas, con la regla/referencia visible junto a la herida.',
                  style: TextStyle(fontSize: 12, color: KuraColors.darkText),
                ),
                const SizedBox(height: 12),
                _photoTile(
                  label: '2. Con medición *',
                  bytes: _photoWithMeasurementBytes,
                  hasPhoto: _photoWithMeasurement != null,
                  onPick: () => _pickPhoto(withMeasurement: true),
                ),

                const SizedBox(height: 24),
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
                      label: Text(c.label, style: const TextStyle(fontSize: 12)),
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
                const SizedBox(height: 12),
                TextFormField(
                  controller: _clinicalNotesCtrl,
                  maxLines: 4,
                  minLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Notas clínicas / Observaciones (opcional)',
                    hintText: 'Observaciones adicionales de la visita…',
                    alignLabelWithHint: true,
                  ),
                ),

                const SizedBox(height: 24),
                Text('Nota de seguimiento (obligatoria)', style: _sectionStyle(context)),
                const SizedBox(height: 4),
                const Text(
                  'Instructivo de Archivo: sin campos vacíos. Selecciona los conceptos '
                  'configurados por el centro; usa "Otro" solo si ninguno aplica.',
                  style: TextStyle(fontSize: 12, color: KuraColors.darkText),
                ),
                const SizedBox(height: 12),
                if (repo != null) ...[
                  _noteFieldChips(
                    repo: repo,
                    session: session,
                    field: NoteOptionField.careType,
                    selected: _careTypeSelected,
                    otherCtrl: _careTypeOtherCtrl,
                    onSelected: (v) => setState(() => _careTypeSelected = v),
                  ),
                  const SizedBox(height: 16),
                  // Toggle premium "Utilizar protocolo Kura+" (Parte D): solo
                  // visible si session.user?.premiumEnabled == true. Se
                  // muestra justo antes de los 2 campos multi-seleccion que
                  // pre-selecciona (procedimiento/material), para que la
                  // relacion causa->efecto sea obvia en la UI.
                  if (session.user?.premiumEnabled == true) ...[
                    _kuraProtocolToggle(repo: repo, session: session),
                    const SizedBox(height: 16),
                  ],
                  _noteFieldChipsMulti(
                    repo: repo,
                    session: session,
                    field: NoteOptionField.procedureDesc,
                    selected: _procedureDescSelected,
                    otherCtrl: _procedureDescOtherCtrl,
                    onToggle: (label, isSelected) => setState(() {
                      _kuraProtocolSuggestionActive = false;
                      if (isSelected) {
                        _procedureDescSelected.add(label);
                      } else {
                        _procedureDescSelected.remove(label);
                      }
                    }),
                  ),
                  const SizedBox(height: 16),
                  _noteFieldChipsMulti(
                    repo: repo,
                    session: session,
                    field: NoteOptionField.materialsUsed,
                    selected: _materialsUsedSelected,
                    otherCtrl: _materialsUsedOtherCtrl,
                    onToggle: (label, isSelected) => setState(() {
                      _kuraProtocolSuggestionActive = false;
                      if (isSelected) {
                        _materialsUsedSelected.add(label);
                      } else {
                        _materialsUsedSelected.remove(label);
                      }
                    }),
                  ),
                  const SizedBox(height: 16),
                  _noteFieldChips(
                    repo: repo,
                    session: session,
                    field: NoteOptionField.evolution,
                    selected: _evolutionSelected,
                    otherCtrl: _evolutionOtherCtrl,
                    onSelected: (v) => setState(() => _evolutionSelected = v),
                  ),
                ],
                const SizedBox(height: 16),
                _signatureReadOnlyCard(),

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
    if (_photoAfterCleaningBytes == null) {
      return 'Falta la fotografía 1 (después de limpiar, sin medición).';
    }
    if (_photoWithMeasurementBytes == null) {
      return 'Falta la fotografía 2 (con medición).';
    }
    if (!_followUpNoteComplete) {
      return 'Completa todos los conceptos de la nota de seguimiento (sin campos vacíos).';
    }
    if (_signedByReadOnly == null || _signedByReadOnly!.isEmpty) {
      return 'No se encontró el nombre del profesional en sesión.';
    }
    if (_signedLicenseReadOnly == null || _signedLicenseReadOnly!.isEmpty) {
      return 'Completa la cédula profesional en tu registro de personal (Administración) '
          'antes de guardar una nota de seguimiento.';
    }
    return '';
  }

  /// Fila de chips (mismo componente visual que la multiselección de
  /// infección IWII) para un campo de la nota de seguimiento, cargados
  /// desde el catálogo activo del centro (note_option_catalog), más un
  /// chip "Otro". Al elegir "Otro": si quien captura es admin, se ofrece
  /// guardarlo al catálogo (createNoteOption); si es clínico, el texto se
  /// usa únicamente en esta nota y no se persiste como concepto.
  Widget _noteFieldChips({
    required DataRepository repo,
    required SessionState session,
    required NoteOptionField field,
    required String? selected,
    required TextEditingController otherCtrl,
    required ValueChanged<String?> onSelected,
  }) {
    final options = repo.listNoteOptions(field);
    final isAdmin = session.user?.role == AppRole.admin;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('${field.label} *', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ...options.map((o) {
              final isSelected = selected == o.label;
              return FilterChip(
                label: Text(o.label, style: const TextStyle(fontSize: 12)),
                selected: isSelected,
                selectedColor: KuraColors.primary.withOpacity(0.15),
                onSelected: (_) => onSelected(o.label),
              );
            }),
            FilterChip(
              label: const Text('Otro', style: TextStyle(fontSize: 12)),
              selected: selected == kOtherOptionValue,
              selectedColor: KuraColors.warning.withOpacity(0.2),
              onSelected: (_) => onSelected(kOtherOptionValue),
            ),
          ],
        ),
        if (selected == kOtherOptionValue) ...[
          const SizedBox(height: 8),
          TextField(
            controller: otherCtrl,
            decoration: InputDecoration(
              labelText: 'Especifica "${field.label}"',
              hintText: isAdmin
                  ? 'Al guardar se ofrecerá agregarlo al catálogo del centro.'
                  : 'Se usará solo en esta nota (no se agrega al catálogo).',
            ),
            onChanged: (_) => setState(() {}),
          ),
          if (isAdmin) ...[
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                icon: const Icon(Icons.playlist_add, size: 16),
                label: const Text('Guardar este concepto en el catálogo', style: TextStyle(fontSize: 12)),
                onPressed: otherCtrl.text.trim().isEmpty
                    ? null
                    : () async {
                        final label = otherCtrl.text.trim();
                        try {
                          await repo.createNoteOption(
                            field: field,
                            label: label,
                            organizationId: session.user?.organizationId,
                            createdByProfileId: session.user?.id,
                          );
                          if (mounted) {
                            setState(() => onSelected(label));
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('"$label" agregado al catálogo de ${field.label}.')),
                            );
                          }
                        } catch (e) {
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('No se pudo agregar al catálogo: $e')),
                            );
                          }
                        }
                      },
              ),
            ),
          ],
        ],
      ],
    );
  }

  /// Variante multi-seleccion (Parte A, feat/followup-protocol-suggest) de
  /// [_noteFieldChips]: usa FilterChip en modo toggle add/remove sobre un
  /// Set<String> en vez de reemplazar un unico valor seleccionado. Misma
  /// logica de "Otro" (texto libre + alta al catalogo si es admin) que
  /// [_noteFieldChips], salvo que aqui "Otro" es un elemento mas del Set
  /// (puede convivir marcado junto a otros conceptos del catalogo).
  ///
  /// Si [_kuraProtocolSuggestionActive] esta activo, muestra debajo de los
  /// chips la nota discreta "Sugerido por Protocolo Kura+ · editable"
  /// (Parte D): el clinico puede seguir quitando/agregando chips con total
  /// libertad, esta nota es solo informativa.
  Widget _noteFieldChipsMulti({
    required DataRepository repo,
    required SessionState session,
    required NoteOptionField field,
    required Set<String> selected,
    required TextEditingController otherCtrl,
    required void Function(String label, bool isSelected) onToggle,
  }) {
    final options = repo.listNoteOptions(field);
    final isAdmin = session.user?.role == AppRole.admin;
    final otherSelected = selected.contains(kOtherOptionValue);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('${field.label} *', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ...options.map((o) {
              final isSelected = selected.contains(o.label);
              return FilterChip(
                label: Text(o.label, style: const TextStyle(fontSize: 12)),
                selected: isSelected,
                selectedColor: KuraColors.primary.withOpacity(0.15),
                onSelected: (v) => onToggle(o.label, v),
              );
            }),
            FilterChip(
              label: const Text('Otro', style: TextStyle(fontSize: 12)),
              selected: otherSelected,
              selectedColor: KuraColors.warning.withOpacity(0.2),
              onSelected: (v) => onToggle(kOtherOptionValue, v),
            ),
          ],
        ),
        if (_kuraProtocolSuggestionActive && selected.isNotEmpty) ...[
          const SizedBox(height: 6),
          Row(
            children: [
              const Icon(Icons.auto_awesome, size: 14, color: KuraColors.primary),
              const SizedBox(width: 4),
              const Text(
                'Sugerido por Protocolo Kura+ · editable',
                style: TextStyle(fontSize: 11, fontStyle: FontStyle.italic, color: KuraColors.primary),
              ),
            ],
          ),
        ],
        if (otherSelected) ...[
          const SizedBox(height: 8),
          TextField(
            controller: otherCtrl,
            decoration: InputDecoration(
              labelText: 'Especifica "${field.label}"',
              hintText: isAdmin
                  ? 'Al guardar se ofrecerá agregarlo al catálogo del centro.'
                  : 'Se usará solo en esta nota (no se agrega al catálogo).',
            ),
            onChanged: (_) => setState(() {}),
          ),
          if (isAdmin) ...[
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                icon: const Icon(Icons.playlist_add, size: 16),
                label: const Text('Guardar este concepto en el catálogo', style: TextStyle(fontSize: 12)),
                onPressed: otherCtrl.text.trim().isEmpty
                    ? null
                    : () async {
                        final label = otherCtrl.text.trim();
                        try {
                          await repo.createNoteOption(
                            field: field,
                            label: label,
                            organizationId: session.user?.organizationId,
                            createdByProfileId: session.user?.id,
                          );
                          if (mounted) {
                            setState(() {
                              selected.remove(kOtherOptionValue);
                              selected.add(label);
                              otherCtrl.clear();
                            });
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('"$label" agregado al catálogo de ${field.label}.')),
                            );
                          }
                        } catch (e) {
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('No se pudo agregar al catálogo: $e')),
                            );
                          }
                        }
                      },
              ),
            ),
          ],
        ],
      ],
    );
  }

  /// Toggle premium "Utilizar protocolo Kura+" (Parte D). Solo se renderiza
  /// si `session.user?.premiumEnabled == true` (chequeado por el llamador
  /// en build()). Al activarlo:
  ///   1. Construye un KuraEngineInput con la valoracion ACTUAL de este
  ///      seguimiento (mediciones/tejido/exudado/infeccion/piel de esta
  ///      visita) + contexto de la herida (etiologia/Wagner/CEAP/WUWHS/
  ///      agente causal via repo.getWound), comorbilidades del paciente
  ///      (repo.listComorbidities) y perfusion/nutricion mas reciente
  ///      (repo.getPerfusionForWound). `entorno` se deriva del `kind` del
  ///      sitio principal del paciente (domicilio si kind=='domicilio',
  ///      clinica en cualquier otro caso) -- no hay un campo de entorno
  ///      propio en el formulario de seguimiento.
  ///   2. Corre KuraProtocolEngine.load()+.run() (mismo orquestador que
  ///      wound_capture_controller.dart) para obtener el regimen sugerido,
  ///      consistente con el resto de la app.
  ///   3. Mapea cada RegimenComponente.metodo a su KuraTag via
  ///      kKuraMethodToTag y pre-selecciona (sin reemplazar lo ya marcado)
  ///      los conceptos activos del catalogo cuyo kuraTag coincida, en
  ///      procedureDesc/materialsUsed. Metodos sin tag (null) o conceptos
  ///      sin etiqueta NUNCA se auto-seleccionan.
  /// Desactivar el toggle NO quita las pre-selecciones ya hechas (son
  /// editables como cualquier otro chip); solo detiene nuevas corridas.
  Widget _kuraProtocolToggle({required DataRepository repo, required SessionState session}) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: KuraColors.primary.withOpacity(0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: KuraColors.primary.withOpacity(0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.auto_awesome, size: 18, color: KuraColors.primary),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Utilizar protocolo Kura+',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              if (_kuraProtocolLoading)
                const SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                Switch(
                  value: _useKuraProtocol,
                  activeColor: KuraColors.primary,
                  onChanged: (v) => _onKuraProtocolToggleChanged(v, repo, session),
                ),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            'Sugiere procedimiento/material segun el regimen del motor clinico '
            'para la valoracion de esta visita. Todo queda editable.',
            style: TextStyle(fontSize: 11, color: KuraColors.darkText),
          ),
        ],
      ),
    );
  }

  Future<void> _onKuraProtocolToggleChanged(
    bool value,
    DataRepository repo,
    SessionState session,
  ) async {
    setState(() => _useKuraProtocol = value);
    if (!value) return;

    setState(() => _kuraProtocolLoading = true);
    try {
      final wound = repo.getWound(widget.woundId);
      if (wound == null) {
        throw StateError('Herida no encontrada.');
      }
      final comorbMap = <Comorbilidad, ComorbilidadEstado>{
        for (final c in repo.listComorbidities(widget.patientId)) c.code: c.status,
      };
      final perfusion = repo.getPerfusionForWound(widget.woundId);
      final patient = repo.getPatient(widget.patientId);
      final sites = repo.listSites();
      Site? primarySite;
      if (patient?.primarySiteId != null) {
        for (final s in sites) {
          if (s.id == patient!.primarySiteId) {
            primarySite = s;
            break;
          }
        }
      }
      final entorno = primarySite?.kind == 'domicilio' ? Entorno.domicilio : Entorno.clinica;

      final input = KuraEngineInput(
        etiologia: wound.etiology,
        entorno: entorno,
        areaCm2: _areaCm2,
        depthCm: _depthCm,
        necrosisPct: _necrosis,
        esfaceloPct: _esfacelo,
        granulacionPct: _granulacion,
        epitelizacionPct: _epitelizacion,
        comorbilidades: comorbMap,
        abiPieDerecho: perfusion?.abiRight,
        abiPieIzquierdo: perfusion?.abiLeft,
        esExtremidadInferior: perfusion?.isLowerExtremity ?? false,
        albuminaGdl: perfusion?.albuminGdl,
        tunelizacionOSocavamiento: _tunneling || _undermining,
        exudadoCantidad: _exudadoCantidad,
        pielPerilesional: _perilesionalSkin,
        infeccionCriterios: _infeccionCriterios,
        tieneCuidadorIdentificado: patient?.hasIdentifiedCaregiver ?? false,
        pacienteFragil: patient?.fragilePatient ?? false,
        wagnerGrade: wound.wagnerGrade,
        ceapClass: wound.ceapClass,
        wuwhsGrade: wound.wuwhsGrade,
        agenteCausal: wound.agenteCausal,
      );

      final engine = await KuraProtocolEngine.load();
      final output = engine.run(input);

      // Mapea cada metodo del regimen a su KuraTag y pre-selecciona los
      // conceptos activos del catalogo cuyo kuraTag coincida. Metodos sin
      // tag (kKuraMethodToTag[metodo] == null, incluyendo metodos
      // desconocidos ausentes del mapa) nunca aportan pre-seleccion.
      final tagsSugeridos = output.regimen
          .map((r) => kKuraMethodToTag[r.metodo])
          .whereType<KuraTag>()
          .toSet();

      if (tagsSugeridos.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Protocolo Kura+ no encontró conceptos etiquetados para esta valoración; '
                'selecciona manualmente.',
              ),
            ),
          );
        }
        return;
      }

      final procedureOptions = repo.listNoteOptions(NoteOptionField.procedureDesc);
      final materialsOptions = repo.listNoteOptions(NoteOptionField.materialsUsed);

      var addedAny = false;
      setState(() {
        for (final o in procedureOptions) {
          if (o.kuraTag != null && tagsSugeridos.contains(o.kuraTag)) {
            if (_procedureDescSelected.add(o.label)) addedAny = true;
          }
        }
        for (final o in materialsOptions) {
          if (o.kuraTag != null && tagsSugeridos.contains(o.kuraTag)) {
            if (_materialsUsedSelected.add(o.label)) addedAny = true;
          }
        }
        if (addedAny) _kuraProtocolSuggestionActive = true;
      });

      if (mounted && !addedAny) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'El régimen sugerido no tiene conceptos etiquetados en el catálogo del '
              'centro; pídele al administrador que asigne etiquetas kura_tag.',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo calcular el protocolo Kura+: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _kuraProtocolLoading = false);
    }
  }

  Widget _signatureReadOnlyCard() {
    final hasLicense = _signedLicenseReadOnly != null && _signedLicenseReadOnly!.isNotEmpty;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: KuraColors.chipBg,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Firma de quien atiende', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Row(
            children: [
              const Icon(Icons.badge_outlined, size: 16, color: KuraColors.darkText),
              const SizedBox(width: 6),
              Expanded(
                child: Text(_signedByReadOnly ?? 'Sin resolver', style: const TextStyle(fontWeight: FontWeight.w600)),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              const Icon(Icons.badge_outlined, size: 16, color: KuraColors.darkText),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  hasLicense ? 'Cédula profesional: $_signedLicenseReadOnly' : 'Cédula profesional: sin registrar',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: hasLicense ? null : KuraColors.danger,
                  ),
                ),
              ),
            ],
          ),
          if (!hasLicense) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.info_outline, size: 16, color: KuraColors.danger),
                const SizedBox(width: 6),
                const Expanded(
                  child: Text(
                    'Completa tu cédula profesional una sola vez en tu registro de '
                    'personal (Administración → Personal sanitario) para poder '
                    'firmar notas de seguimiento.',
                    style: TextStyle(fontSize: 11, color: KuraColors.danger),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
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
    // Fix admin-clinico (ajuste obligatorio #3): ver comentario equivalente
    // en consultation_hub_screen.dart -- el staffId de un admin ya se
    // resuelve de forma perezosa en SessionController; aqui se reintenta
    // como red de seguridad en vez de bloquear directamente el guardado.
    var staffId = session.user?.staffId;
    if (staffId == null && session.user?.role == AppRole.admin) {
      staffId = await repo.ensureAdminStaffId(session.user!);
    }
    if (staffId == null) {
      setState(() => _saving = false);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No se encontró personal sanitario vinculado a tu cuenta.')),
        );
      }
      return;
    }

    String? photoWarning;
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
        followUpCareType: _careTypeFinal,
        followUpProcedureDesc: _procedureDescFinal,
        followUpMaterialsUsed: _materialsUsedFinal,
        followUpEvolution: _evolutionFinal,
        followUpSignedBy: _signedByReadOnly!,
        followUpSignedLicense: _signedLicenseReadOnly!,
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
        'volume_manual': _isDeepWound ? _isVolumeManuallyOverridden : false,
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
        'clinical_notes': _clinicalNotesCtrl.text.trim().isEmpty
            ? null
            : _clinicalNotesCtrl.text.trim(),
      });

      // 2 fotografias de seguimiento (Protocolo de Fotografias y Medicion):
      // 1ra despues de limpiar (sin medicion), 2da con medicion. Las fotos se
      // guardan en un try aparte: la consulta y la medicion YA se guardaron, asi
      // que si una foto falla (p.ej. en modo demo la cuota de localStorage se
      // llena con base64), el SEGUIMIENTO CLINICO no se pierde -- solo se avisa.
      try {
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
      } catch (e) {
        debugPrint('Fotos de seguimiento no guardadas: $e');
        photoWarning = e.toString().contains('Quota')
            ? 'El seguimiento se registró, pero las fotos no se pudieron guardar '
                '(memoria del modo demo llena). En producción se guardan en la nube.'
            : 'El seguimiento se registró, pero hubo un problema al guardar las fotos.';
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
        SnackBar(
          content: Text(photoWarning ?? 'Seguimiento registrado correctamente.'),
          backgroundColor: photoWarning != null ? KuraColors.warning : null,
        ),
      );
      // Esta pantalla se navega declarativamente via GoRouter (no
      // Navigator.push), por lo que el regreso tambien debe ser un
      // context.go explicito a la pantalla de seguimiento (no
      // Navigator.pop, que no aplica a rutas declarativas de GoRouter).
      context.go('/patients/${widget.patientId}/wound/${widget.woundId}/follow-up');
    }
  }
}

/// Valor centinela para el chip "Otro" en los campos de la nota de
/// seguimiento (no es un id real del catalogo).
const String kOtherOptionValue = '__other__';
