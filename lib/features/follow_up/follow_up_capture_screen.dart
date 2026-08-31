import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../../core/providers/session_provider.dart';
import '../../core/theme/kura_theme.dart';
import '../../core/utils/image_pick_error.dart';
import '../../core/utils/wound_volume.dart';
import '../../services/image_transcode.dart';
import '../../engine/kura_protocol_engine.dart';
import '../../engine/kura_sheehan_checkpoint.dart';
import '../../engine/models/kura_engine_enums.dart';
import '../../engine/models/kura_engine_input.dart';
import '../../engine/models/kura_engine_output.dart';
import '../../models/app_user.dart';
import '../../models/wound.dart';
import '../../models/consultation.dart';
import '../../models/note_option_catalog.dart';
import '../../models/site.dart';
import '../../models/treatment_plan.dart';
import '../../services/data_repository.dart';
import '../../services/photo_upload_service.dart';
import '../../core/widgets/signature_pad.dart';
import '../../models/consent.dart';
import '../consents/consents_screen.dart';
import '../wound_capture/widgets/bed_composition_sliders.dart';
import '../wound_capture/widgets/undermining_tunneling_editor.dart';

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
// kKuraMethodToTag se movió a note_option_catalog.dart (compartido con la
// resolución protocolo→producto). Se usa aquí vía ese import.

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
  /// Si se abre para RETOMAR un borrador, su id. Al finalizar se reemplaza.
  final String? draftConsultationId;
  const FollowUpCaptureScreen({
    super.key,
    required this.patientId,
    required this.woundId,
    this.draftConsultationId,
  });

  @override
  ConsumerState<FollowUpCaptureScreen> createState() => _FollowUpCaptureScreenState();
}

class _FollowUpCaptureScreenState extends ConsumerState<FollowUpCaptureScreen> {
  DateTime _visitDate = DateTime.now();
  bool _draftLoaded = false;
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
  final _specialistNotesCtrl = TextEditingController(); // notas del especialista (0069)
  final _visitSummaryCtrl = TextEditingController(); // resumen de la consulta
  bool _tunneling = false;
  bool _undermining = false;
  // Dirección estructurada (0093): puntos de tunelización y arcos de socavamiento.
  List<TunnelingSite> _tunnelingSites = [];
  List<UnderminingSite> _underminingSites = [];

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
  ExudadoTipo _exudadoTipo = ExudadoTipo.serohematico;
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
  // Fotos ya guardadas al reabrir un borrador (storage_path por etapa). Se
  // muestran y, al re-guardar, se re-persisten con su MISMO path si el clínico
  // no las vuelve a tomar (así el borrador conserva las fotografías).
  String? _savedPhotoAfterCleaningPath;
  String? _savedPhotoWithMeasurementPath;
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
  bool _kuraProtocolLoading = false;

  // ---- Fase 0: perfil heredado (overrides editables que ALIMENTAN el motor) ----
  // Se premarcan desde la herida la primera vez; el especialista puede
  // ajustar el subtipo vascular / no-revascularizable en la tarjeta de perfil
  // (drivers de terapia seca) sin cambiar la herida persistida.
  bool _profileInit = false;
  SubtipoVascular? _subtipoOverride;
  bool _noRevascOverride = false;

  // ---- Fase 3: régimen del motor (paso VISIBLE, ya no enterrado en un toggle) ----
  KuraEngineOutput? _engineOutput;
  bool _regimenAccepted = false;

  // Firma/cedula: solo lectura, resueltas desde el staff de la sesion (no
  // se piden como campos editables en cada nota).
  String? _signedByReadOnly;
  String? _signedLicenseReadOnly;
  String? _signedSpecialtyReadOnly;
  // Firma digital trazada por el profesional (además del nombre + cédula de
  // solo lectura). Obligatoria para firmar la nota.
  final SignatureController _signatureController = SignatureController();
  bool _hasSignature = false;

  bool _saving = false;

  double get _lengthCm => double.tryParse(_lengthCtrl.text.replaceAll(',', '.')) ?? 0;
  double get _widthCm => double.tryParse(_widthCtrl.text.replaceAll(',', '.')) ?? 0;
  double get _depthCm => double.tryParse(_depthCtrl.text.replaceAll(',', '.')) ?? 0;
  // Área 2D por la elipse (L×A×0.785), validada por María 2026-07. Ver
  // core/utils/wound_volume.dart.
  double get _areaCm2 => WoundVolumeCalculator.ellipseArea(_lengthCm, _widthCm);
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

  /// Selector cámara/galería (igual que en la valoración): en móvil-web la
  /// cámara abre la cámara del dispositivo; en escritorio-web se ignora y abre
  /// el selector de archivos.
  Future<void> _pickPhotoSource({required bool withMeasurement}) async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Tomar foto'),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Elegir de la galería'),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source != null) {
      await _pickPhoto(withMeasurement: withMeasurement, source: source);
    }
  }

  Future<void> _pickPhoto(
      {required bool withMeasurement,
      ImageSource source = ImageSource.gallery}) async {
    try {
      // Web: sin resize del plugin (falla con HEIC); bytes crudos + conversión
      // a JPEG en el navegador (transcodeImageToJpeg). Nativo: como antes.
      final file = await _picker.pickImage(
        source: source,
        imageQuality: kIsWeb ? null : 85,
        maxWidth: kIsWeb ? null : 1600,
        maxHeight: kIsWeb ? null : 1600,
      );
      if (file == null) return;
      final raw = await file.readAsBytes();
      final jpeg = await transcodeImageToJpeg(raw, name: file.name);
      if (jpeg == null && kIsWeb) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(imagePickErrorMessage('formato'))));
        return;
      }
      final bytes = jpeg ?? raw;
      setState(() {
        if (withMeasurement) {
          _photoWithMeasurement = file;
          _photoWithMeasurementBytes = bytes;
          _savedPhotoWithMeasurementPath = null;
        } else {
          _photoAfterCleaning = file;
          _photoAfterCleaningBytes = bytes;
          _savedPhotoAfterCleaningPath = null;
        }
      });
    } catch (e) {
      // Antes se ocultaba el error (típicamente HEIC de iPhone): ahora se avisa.
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(imagePickErrorMessage(e))));
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
      final staff = repo.getStaff(staffId);
      _signedLicenseReadOnly = staff?.cedulaProfesional;
      _signedSpecialtyReadOnly = staff?.especialidad;
    }
  }

  @override
  void initState() {
    super.initState();
    // Rehabilita el botón de guardar solo cuando cambia el estado vacío/no
    // vacío de la firma (no en cada punto trazado, para no reconstruir todo el
    // formulario mientras se firma).
    _signatureController.addListener(() {
      final has = _signatureController.isNotEmpty;
      if (has != _hasSignature) setState(() => _hasSignature = has);
    });
  }

  @override
  void dispose() {
    _signatureController.dispose();
    _lengthCtrl.dispose();
    _widthCtrl.dispose();
    _depthCtrl.dispose();
    _volumeCtrl.dispose();
    _manualMeasurementCtrl.dispose();
    _clinicalNotesCtrl.dispose();
    _specialistNotesCtrl.dispose();
    _visitSummaryCtrl.dispose();
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
    if (repo != null) _loadDraftIfNeeded(repo, session);
    // Fase 0: perfil heredado de la herida (premarcado + editable). Solo lectura
    // de datos; no cambia la persistencia.
    final wound = repo?.getWound(widget.woundId);
    if (wound != null) _initProfileIfNeeded(wound);
    final kuraEnabled = ref.watch(kuraProtocolEnabledProvider);

    final canSave = !_saving &&
        _lengthCm > 0 &&
        _widthCm > 0 &&
        (_photoAfterCleaningBytes != null ||
                _savedPhotoAfterCleaningPath != null) &&
        _followUpNoteComplete &&
        _signedByReadOnly != null &&
        _signedByReadOnly!.isNotEmpty &&
        _signedLicenseReadOnly != null &&
        _signedLicenseReadOnly!.isNotEmpty &&
        _hasSignature &&
        // Gating (Protocolo "Expedientes clínicos"): la toma de fotografía del
        // seguimiento requiere el consentimiento de fotografía.
        (repo == null ||
            repo.hasConsent(widget.patientId, ConsentType.fotografia));

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
                if (repo != null)
                  ConsentGateBanner(
                    patientId: widget.patientId,
                    repo: repo,
                    required: const [ConsentType.fotografia],
                    actionLabel: 'la toma de fotografía del seguimiento',
                  ),
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
                const SizedBox(height: 20),
                if (repo != null && wound != null) _phase0Profile(repo, wound),
                _phaseHeader(1, 'Procedimiento físico',
                    'Limpiar → fotografiar la herida → medir'),
                Text('Fotografía de la herida', style: _sectionStyle(context)),
                const SizedBox(height: 4),
                const Text(
                  'Protocolo de Fotografías §1.2: se toma después de limpiar la '
                  'herida, ANTES de evaluar el lecho o medir.',
                  style: TextStyle(fontSize: 12, color: KuraColors.darkText),
                ),
                const SizedBox(height: 12),
                _photoTile(
                  label: 'Fotografía de la herida *',
                  bytes: _photoAfterCleaningBytes,
                  hasPhoto: _photoAfterCleaning != null ||
                      _savedPhotoAfterCleaningPath != null,
                  savedPath: _savedPhotoAfterCleaningPath,
                  onPick: () => _pickPhotoSource(withMeasurement: false),
                ),

                // Medición 2D/3D/manual → inmediatamente después, la 2ª foto
                // (con medición). La composición del lecho se evalúa en la
                // Fase 2 (después de medir), por el protocolo de fotografía.
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
                        onChanged: (v) => setState(() {
                          _tunneling = v ?? false;
                          if (!_tunneling) _tunnelingSites = [];
                        }),
                      ),
                    ),
                    Expanded(
                      child: CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        controlAffinity: ListTileControlAffinity.leading,
                        value: _undermining,
                        title: const Text('Socavamiento', style: TextStyle(fontSize: 13)),
                        onChanged: (v) => setState(() {
                          _undermining = v ?? false;
                          if (!_undermining) _underminingSites = [];
                        }),
                      ),
                    ),
                  ],
                ),
                if (_tunneling || _undermining) ...[
                  UnderminingTunnelingEditor(
                    key: ValueKey('utedit-$_tunneling-$_undermining'),
                    showTunneling: _tunneling,
                    showUndermining: _undermining,
                    tunnelingSites: _tunnelingSites,
                    underminingSites: _underminingSites,
                    onChanged: (tun, und) => setState(() {
                      _tunnelingSites = tun;
                      _underminingSites = und;
                    }),
                  ),
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
                _phaseHeader(2, 'Estado actual',
                    'Composición del lecho, exudado, infección, dolor, borde, piel perilesional'),
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
                            .map((e) => DropdownMenuItem(value: e, child: Text(e.label)))
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
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: KuraColors.danger.withOpacity(0.06),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: KuraColors.danger.withOpacity(0.3)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.coronavirus_outlined,
                              size: 18, color: KuraColors.danger),
                          const SizedBox(width: 6),
                          Text('Criterios de infección (IWII)',
                              style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: KuraColors.danger)),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: InfeccionCriterioIwii.values.map((c) {
                          final selected = _infeccionCriterios.contains(c);
                          return FilterChip(
                            label:
                                Text(c.label, style: const TextStyle(fontSize: 12)),
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
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        // Olor binario (María): presente / no presente.
                        value: _odor == 'ninguno' ? 'ninguno' : 'presente',
                        decoration: const InputDecoration(labelText: 'Olor'),
                        items: const [
                          DropdownMenuItem(
                              value: 'ninguno', child: Text('No presente')),
                          DropdownMenuItem(
                              value: 'presente', child: Text('Presente')),
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
                if (kuraEnabled && repo != null) _phase3Regimen(repo),
                if (repo != null && wound != null) _phase4Sheehan(repo, wound),
                _phaseHeader(5, 'Nota + firma (obligatoria)',
                    'Evolución, materiales, firma y cédula'),
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
                  // El régimen Kura+ y su "aceptar" (que pre-selecciona
                  // procedimiento/material) ahora viven en la Fase 3, visible,
                  // no en un toggle enterrado dentro de la nota.
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
                const SizedBox(height: 20),
                Text('Notas y resumen', style: _sectionStyle(context)),
                const SizedBox(height: 8),
                TextField(
                  controller: _specialistNotesCtrl,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Notas del especialista',
                    hintText: 'Observaciones libres de la consulta.',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _visitSummaryCtrl,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Resumen de la consulta',
                    hintText: 'Se autollenará con Plaud AI; editable.',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                _signatureReadOnlyCard(),

                const SizedBox(height: 28),
                // Guardar BORRADOR: solo requiere la medición (largo/ancho);
                // permite terminar la consulta después. No cobra hasta finalizar.
                OutlinedButton.icon(
                  icon: const Icon(Icons.save_outlined),
                  label: Text(widget.draftConsultationId != null
                      ? 'Guardar cambios del borrador'
                      : 'Guardar como borrador'),
                  style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14)),
                  onPressed: (_lengthCm > 0 && _widthCm > 0 && !_saving)
                      ? () => _saveDraft(context, session)
                      : null,
                ),
                const SizedBox(height: 10),
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
    if (_photoAfterCleaningBytes == null &&
        _savedPhotoAfterCleaningPath == null) {
      return 'Falta la fotografía de la herida.';
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
    if (!_hasSignature) {
      return 'Firma digitalmente la nota (traza tu firma en el recuadro).';
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

    // Nombres comerciales mapeados (Insumos → "Material del centro") de los
    // materiales seleccionados/sugeridos: le dicen al profesional qué producto
    // CONCRETO aplicar, con terminología consistente en todo el flujo.
    final commercialRows = <Widget>[];
    if (field == NoteOptionField.materialsUsed &&
        repo.premiumInsumosFor(session.user?.organizationId)) {
      final orgId = session.user?.organizationId;
      for (final label in selected) {
        if (label == kOtherOptionValue) continue;
        final names = repo.commercialNamesForCenterMaterial(orgId, label);
        if (names.isEmpty) continue;
        commercialRows.add(Padding(
          padding: const EdgeInsets.only(top: 3),
          child: Text('• $label → ${names.join(', ')}',
              style: const TextStyle(fontSize: 12, color: KuraColors.primary)),
        ));
      }
    }

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
        if (commercialRows.isNotEmpty) ...[
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: KuraColors.primary.withOpacity(0.06),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Producto a aplicar (mapeado por el centro):',
                    style: TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w700)),
                ...commercialRows,
              ],
            ),
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
  // ======================= Rediseño en fases (solo UI) =======================

  /// Tarjeta contenedora de una fase, con número y título.
  Widget _phaseCard({
    required int n,
    required String title,
    String? subtitle,
    required Widget child,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: KuraColors.primary.withOpacity(0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 14,
                backgroundColor: KuraColors.primary,
                child: Text('$n',
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 13)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Fase $n · $title',
                        style: const TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 15)),
                    if (subtitle != null)
                      Text(subtitle,
                          style: TextStyle(
                              fontSize: 12,
                              color: KuraColors.darkText.withOpacity(0.7))),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }

  /// Encabezado de fase (número + título) para las fases que agrupan la captura
  /// existente (1/2/5); las fases 0/3/4 usan la tarjeta [_phaseCard].
  Widget _phaseHeader(int n, String title, String? subtitle) => Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 12),
        child: Row(
          children: [
            CircleAvatar(
              radius: 14,
              backgroundColor: KuraColors.primary,
              child: Text('$n',
                  style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 13)),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Fase $n · $title',
                      style: const TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 15)),
                  if (subtitle != null)
                    Text(subtitle,
                        style: TextStyle(
                            fontSize: 12,
                            color: KuraColors.darkText.withOpacity(0.7))),
                ],
              ),
            ),
          ],
        ),
      );

  // -------------------------- Fase 0: perfil heredado --------------------------

  void _initProfileIfNeeded(Wound wound) {
    if (_profileInit) return;
    _profileInit = true;
    _subtipoOverride = wound.subtipoVascular;
    _noRevascOverride = wound.noRevascularizable;
  }

  SubtipoVascular? _effectiveSubtipo(Wound wound) =>
      _profileInit ? _subtipoOverride : wound.subtipoVascular;
  bool _effectiveNoRevasc(Wound wound) =>
      _profileInit ? _noRevascOverride : wound.noRevascularizable;

  Widget _profileRow(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
                width: 130,
                child: Text(label,
                    style: const TextStyle(
                        fontSize: 12,
                        color: KuraColors.darkText,
                        fontWeight: FontWeight.w600))),
            Expanded(child: Text(value, style: const TextStyle(fontSize: 12))),
          ],
        ),
      );

  Widget _phase0Profile(DataRepository repo, Wound wound) {
    final perfusion = repo.getPerfusionForWound(widget.woundId);
    final abis = [perfusion?.abiRight, perfusion?.abiLeft]
        .whereType<double>()
        .toList();
    final abiMin = abis.isEmpty ? null : abis.reduce((a, b) => a < b ? a : b);
    final comorbs = repo
        .listComorbidities(widget.patientId)
        .where((c) => c.status == ComorbilidadEstado.presente)
        .toList();
    final hito = KuraSheehanCheckpoint.hitoParaEtiologia(wound.etiology);
    final semana = _treatmentWeeks(repo);
    final clasificaciones = <String>[
      if (wound.wagnerGrade != null)
        'Wagner ${wound.wagnerGrade!.name.toUpperCase()}',
      if (wound.ceapClass != null) 'CEAP ${wound.ceapClass!.name.toUpperCase()}',
      if (wound.wuwhsGrade != null)
        'WUWHS ${wound.wuwhsGrade!.name.toUpperCase()}',
      if (wound.agenteCausal != null) wound.agenteCausal!.name,
      if (wound.texasGrade != null) 'Texas ${wound.texasGrade!.name}',
      if (wound.rutherford != null) 'Rutherford ${wound.rutherford!.name}',
      if (wound.npuapEstadio != null) 'NPUAP ${wound.npuapEstadio!.name}',
    ];

    return _phaseCard(
      n: 0,
      title: 'Perfil heredado',
      subtitle:
          'Premarcado desde la valoración; ajusta lo que cambió. Alimenta el motor.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
                color: KuraColors.chipBg,
                borderRadius: BorderRadius.circular(10)),
            child: Text(
              hito != null
                  ? 'Semana $semana de tratamiento · meta: ${hito.pctCierre.toStringAsFixed(0)}% de reducción para la semana ${hito.semanaHito} (${wound.etiology.label}).'
                  : 'Semana $semana de tratamiento.',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(height: 12),
          _profileRow('Etiología', wound.etiology.label),
          if (abiMin != null)
            _profileRow('ABI/ITB (mín.)', abiMin.toStringAsFixed(2)),
          if (comorbs.isNotEmpty)
            _profileRow(
                'Comorbilidades', comorbs.map((c) => c.code.name).join(', ')),
          if (clasificaciones.isNotEmpty)
            _profileRow('Clasificaciones', clasificaciones.join(' · ')),
          if (wound.etiology == Etiologia.vascular) ...[
            const SizedBox(height: 12),
            const Text('Subtipo vascular (editable)',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              children: [
                for (final s in SubtipoVascular.values)
                  ChoiceChip(
                    label: Text(s.name, style: const TextStyle(fontSize: 12)),
                    selected: _effectiveSubtipo(wound) == s,
                    onSelected: (_) => setState(() {
                      _subtipoOverride = s;
                      _engineOutput = null;
                      _regimenAccepted = false;
                    }),
                  ),
              ],
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('No revascularizable (Doppler/angiólogo)',
                  style: TextStyle(fontSize: 13)),
              value: _effectiveNoRevasc(wound),
              activeColor: KuraColors.primary,
              onChanged: (v) => setState(() {
                _noRevascOverride = v;
                _engineOutput = null;
                _regimenAccepted = false;
              }),
            ),
          ],
        ],
      ),
    );
  }

  // ------------------- Fase 3: régimen sugerido por Kura+ (visible) ------------

  Widget _regimenBox({
    required IconData icon,
    required Color color,
    required String title,
    required String body,
  }) =>
      Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: color.withOpacity(0.06),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withOpacity(0.25)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: color)),
                  if (body.isNotEmpty)
                    Text(body, style: const TextStyle(fontSize: 12)),
                ],
              ),
            ),
          ],
        ),
      );

  Widget _phase3Regimen(DataRepository repo) {
    final out = _engineOutput;
    return _phaseCard(
      n: 3,
      title: 'Régimen sugerido por Kura+',
      subtitle: 'Corre el motor con el perfil (Fase 0) + el estado (Fase 2).',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                    out == null
                        ? 'Aún no calculado para esta visita.'
                        : 'Régimen calculado.',
                    style: const TextStyle(fontSize: 12)),
              ),
              if (_kuraProtocolLoading)
                const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
              else
                FilledButton.tonalIcon(
                  icon: const Icon(Icons.auto_awesome, size: 18),
                  label: Text(out == null ? 'Calcular régimen' : 'Recalcular'),
                  onPressed: () => _runRegimen(repo),
                ),
            ],
          ),
          if (out != null) ...[
            const SizedBox(height: 12),
            for (final a in out.alertas)
              _regimenBox(
                  icon: Icons.warning_amber_rounded,
                  color: KuraColors.danger,
                  title: 'Alerta de seguridad',
                  body: a),
            for (final c in out.regimen)
              _regimenBox(
                  icon: c.esAlerta
                      ? Icons.warning_amber_rounded
                      : Icons.check_circle_outline,
                  color: c.esAlerta ? KuraColors.danger : KuraColors.primary,
                  title: '${c.metodo} — ${c.producto}',
                  body: c.justificacion),
            for (final ic in out.interconsultas)
              _regimenBox(
                  icon: Icons.medical_services_outlined,
                  color: ic.esUrgente ? KuraColors.danger : KuraColors.infoBlue,
                  title:
                      'Interconsulta: ${ic.especialidad}${ic.esUrgente ? ' (urgente)' : ''}',
                  body: ic.motivo),
            const SizedBox(height: 4),
            FilledButton.icon(
              icon: Icon(
                  _regimenAccepted ? Icons.check : Icons.playlist_add_check),
              label: Text(_regimenAccepted
                  ? 'Aceptado — aplicado a la nota (Fase 5)'
                  : 'Aceptar y aplicar a la nota'),
              style: FilledButton.styleFrom(backgroundColor: KuraColors.primary),
              onPressed:
                  _regimenAccepted ? null : () => _applyRegimenToNote(repo),
            ),
            const SizedBox(height: 4),
            const Text(
                'El procedimiento/material queda editable en la nota (Fase 5).',
                style: TextStyle(fontSize: 11, color: KuraColors.darkText)),
          ],
        ],
      ),
    );
  }

  // ------------------- Fase 4: trayectoria / checkpoint Sheehan ---------------

  int _treatmentWeeks(DataRepository repo) {
    final ms = repo.listMeasurementsForWound(widget.woundId);
    final wound = repo.getWound(widget.woundId);
    final base = ms.isNotEmpty
        ? ms.first.measuredAt
        : (wound?.onsetDate ?? wound?.createdAt ?? _visitDate);
    final days = _visitDate.difference(base).inDays;
    return days < 0 ? 0 : days ~/ 7;
  }

  SheehanCheckpointResult? _sheehanResult(DataRepository repo, Wound wound) {
    final ms = repo.listMeasurementsForWound(widget.woundId);
    if (ms.isEmpty) return null;
    final basal = ms.first.areaCm2;
    if (basal <= 0) return null;
    return KuraSheehanCheckpoint.evaluate(
      semana: _treatmentWeeks(repo),
      areaBasalCm2: basal,
      areaActualCm2: _areaCm2,
      etiologia: wound.etiology,
      infeccionActiva: _infeccionCriterios.isNotEmpty,
      bajaAdherencia: _lowAdherence,
    );
  }

  Widget _phase4Sheehan(DataRepository repo, Wound wound) {
    final res = _sheehanResult(repo, wound);
    final hito = KuraSheehanCheckpoint.hitoParaEtiologia(wound.etiology);
    final semana = _treatmentWeeks(repo);
    final enVentana = hito != null && semana >= hito.semanaHito;
    Widget body;
    if (res == null) {
      body = const Text(
        'Sin medición basal para comparar (primera visita o área basal 0). El '
        'checkpoint se activa cuando hay una valoración previa con área.',
        style: TextStyle(fontSize: 12),
      );
    } else {
      Color color;
      String signal;
      switch (res.decision) {
        case SheehanDecision.confirmarCierre:
          color = KuraColors.success;
          signal = 'En trayectoria: la reducción cumple la meta. Continuar el plan.';
          break;
        case SheehanDecision.extenderObservacion:
          color = KuraColors.warning;
          signal =
              'Avance por debajo de la meta: revalidar plan y vigilar de cerca.';
          break;
        case SheehanDecision.reclasificarC:
          color = KuraColors.danger;
          signal =
              'No avanza: escalar / considerar interconsulta y reclasificar (contención).';
          break;
      }
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
              'Reducción de área: ${res.pctReduccionAjustada.toStringAsFixed(0)}% '
              '(bruta ${res.pctReduccionBruta.toStringAsFixed(0)}%) · meta cierre '
              '${res.umbralCierre.toStringAsFixed(0)}% / alerta '
              '${res.umbralAlerta.toStringAsFixed(0)}%',
              style: const TextStyle(fontSize: 12)),
          const SizedBox(height: 6),
          LinearProgressIndicator(
            value: (res.pctReduccionAjustada / 100).clamp(0.0, 1.0),
            color: color,
            backgroundColor: color.withOpacity(0.15),
            minHeight: 8,
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withOpacity(0.10),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: color.withOpacity(0.4)),
            ),
            child: Row(
              children: [
                Icon(Icons.timeline, size: 18, color: color),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('${res.decision.label}. $signal',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: color)),
                ),
              ],
            ),
          ),
          if (res.penalizacionesAplicadas.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text('Penalizaciones: ${res.penalizacionesAplicadas.join(', ')}.',
                style: TextStyle(
                    fontSize: 11, color: KuraColors.darkText.withOpacity(0.7))),
          ],
        ],
      );
    }
    return _phaseCard(
      n: 4,
      title: 'Trayectoria / checkpoint',
      subtitle: enVentana
          ? 'Visita de la ventana (semana ${hito.semanaHito}): punto de decisión.'
          : 'Medidor de Sheehan (regla de decisión).',
      child: body,
    );
  }

  /// Construye el input del motor desde el perfil heredado (con overrides de
  /// Fase 0) + el estado capturado en esta visita. NO cambia la lógica del
  /// motor; solo consolida de dónde salen sus entradas.
  KuraEngineInput? _buildEngineInput(DataRepository repo) {
    final wound = repo.getWound(widget.woundId);
    if (wound == null) return null;
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
    final entorno =
        primarySite?.kind == 'domicilio' ? Entorno.domicilio : Entorno.clinica;

    return KuraEngineInput(
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
      // Nutrición: prioriza la albúmina de LABORATORIOS del paciente (0070).
      albuminaGdl: repo.latestPatientLab(widget.patientId)?.albuminGdl ??
          perfusion?.albuminGdl,
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
      // Perfil diagnóstico heredado (Fase 0), editable por el especialista.
      subtipoVascular: _effectiveSubtipo(wound),
      noRevascularizable: _effectiveNoRevasc(wound),
      // Braden del PERFIL del paciente (risk_assessments), re-evaluable.
      bradenScore: repo.latestRiskAssessment(widget.patientId)?.bradenScore,
    );
  }

  /// Fase 3: corre el motor y guarda el resultado para MOSTRARLO (visible).
  Future<void> _runRegimen(DataRepository repo) async {
    setState(() => _kuraProtocolLoading = true);
    try {
      final input = _buildEngineInput(repo);
      if (input == null) throw StateError('Herida no encontrada.');
      final engine = await KuraProtocolEngine.load();
      final output = engine.run(input);
      if (!mounted) return;
      setState(() {
        _engineOutput = output;
        _regimenAccepted = false;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo calcular el régimen Kura+: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _kuraProtocolLoading = false);
    }
  }

  /// Fase 3 (aceptar): pre-selecciona en la nota (procedimiento/material) los
  /// conceptos del catálogo cuyo kura_tag coincide con el régimen. Editable.
  void _applyRegimenToNote(DataRepository repo) {
    final output = _engineOutput;
    if (output == null) return;
    final tagsSugeridos = output.regimen
        .map((r) => kKuraMethodToTag[r.metodo])
        .whereType<KuraTag>()
        .toSet();
    if (tagsSugeridos.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'El régimen no tiene conceptos etiquetados; selecciona manualmente '
            'en la nota (Fase 5).',
          ),
        ),
      );
      setState(() => _regimenAccepted = true);
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
      _regimenAccepted = true;
    });
    if (!addedAny) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'El régimen sugerido no tiene conceptos etiquetados en el catálogo '
            'del centro; pídele al administrador que asigne etiquetas kura_tag.',
          ),
        ),
      );
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
          if (_signedSpecialtyReadOnly != null &&
              _signedSpecialtyReadOnly!.isNotEmpty) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                const Icon(Icons.medical_services_outlined,
                    size: 16, color: KuraColors.darkText),
                const SizedBox(width: 6),
                Expanded(
                  child: Text('Especialidad: $_signedSpecialtyReadOnly',
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                ),
              ],
            ),
          ],
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
          const SizedBox(height: 12),
          Row(
            children: [
              const Expanded(
                child: Text('Firma digital *',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
              ),
              TextButton.icon(
                icon: const Icon(Icons.refresh, size: 16),
                label: const Text('Limpiar'),
                onPressed: () => _signatureController.clear(),
              ),
            ],
          ),
          const SizedBox(height: 6),
          SignaturePad(controller: _signatureController),
          const SizedBox(height: 4),
          const Text(
            'Traza tu firma con el dedo, lápiz o ratón. Queda registrada junto a '
            'tu nombre y cédula con fecha y hora.',
            style: TextStyle(fontSize: 11, color: KuraColors.darkText),
          ),
        ],
      ),
    );
  }

  Widget _photoTile({
    required String label,
    required Uint8List? bytes,
    required bool hasPhoto,
    required VoidCallback onPick,
    String? savedPath,
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
        else if (savedPath != null)
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: FutureBuilder<String>(
              future: PhotoUploadService.resolveDisplayUrl(savedPath),
              builder: (ctx, snap) => snap.hasData
                  ? Image.network(snap.data!, height: 160, fit: BoxFit.cover)
                  : Container(
                      height: 160,
                      color: KuraColors.chipBg,
                      child: const Center(
                          child: CircularProgressIndicator(strokeWidth: 2)),
                    ),
            ),
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

  /// Precarga los datos de un borrador al reabrirlo (una sola vez).
  /// Instantánea COMPLETA del formulario para el borrador. Un borrador nunca
  /// debe guardar un subconjunto elegido a mano (eso es pérdida de datos con
  /// otro nombre): se serializa TODO el estado del formulario a
  /// `consultations.draft_form_state` (jsonb, 0089), igual que la valoración
  /// inicial (wound_capture_screen). Las fotos NO van aquí (se conservan en
  /// wound_photos y se re-persisten aparte).
  Map<String, dynamic> _formSnapshot() => {
        'visit_date': _visitDate.toIso8601String(),
        // Medición (los 10 campos que antes se perdían + L/A/P/volumen/nota).
        'length': _lengthCtrl.text,
        'width': _widthCtrl.text,
        'depth': _depthCtrl.text,
        'volume': _volumeCtrl.text,
        'volume_auto_following': _volumeAutoFollowing,
        'manual_measurement': _manualMeasurementCtrl.text,
        'tunneling': _tunneling,
        'undermining': _undermining,
        'tunneling_sites': [for (final s in _tunnelingSites) s.toJson()],
        'undermining_sites': [for (final s in _underminingSites) s.toJson()],
        'granulacion': _granulacion,
        'esfacelo': _esfacelo,
        'necrosis': _necrosis,
        'epitelizacion': _epitelizacion,
        'captured_before_debridement': _capturedBeforeDebridement,
        // Evaluación clínica.
        'edema': _edema,
        'pain': _pain,
        'pain_type': _painType,
        'pain_duration': _painDuration,
        'pain_vas': _painVas,
        'exudado_cantidad': _exudadoCantidad.name,
        'exudado_tipo': _exudadoTipo.name,
        'infeccion_criterios': _infeccionCriterios.map((e) => e.name).toList(),
        'odor': _odor,
        'wound_edge': _woundEdge,
        'perilesional_skin': _perilesionalSkin.map((e) => e.name).toList(),
        'low_adherence': _lowAdherence,
        'clinical_notes': _clinicalNotesCtrl.text,
        // Notas de la consulta.
        'specialist_notes': _specialistNotesCtrl.text,
        'visit_summary': _visitSummaryCtrl.text,
        // Nota de seguimiento (catálogo + "otro").
        'care_type': _careTypeSelected,
        'care_type_other': _careTypeOtherCtrl.text,
        'procedure_desc': _procedureDescSelected.toList(),
        'procedure_desc_other': _procedureDescOtherCtrl.text,
        'materials_used': _materialsUsedSelected.toList(),
        'materials_used_other': _materialsUsedOtherCtrl.text,
        'evolution': _evolutionSelected,
        'evolution_other': _evolutionOtherCtrl.text,
        // Overrides del perfil (drivers del motor) + decisión de régimen.
        'subtipo_override': _subtipoOverride?.name,
        'no_revasc_override': _noRevascOverride,
        'regimen_accepted': _regimenAccepted,
      };

  /// Restaura el formulario desde una instantánea de borrador. FUENTE DE VERDAD
  /// al reabrir: se aplica sobre lo repoblado por fila (que puede venir
  /// incompleto en borradores viejos sin instantánea).
  void _applyFormSnapshot(Map<String, dynamic> s) {
    E? en<E>(List<E> values, Object? name) {
      if (name is! String) return null;
      for (final v in values) {
        if ((v as Enum).name == name) return v;
      }
      return null;
    }

    String txt(Object? v, String fb) => v is String ? v : fb;
    double dbl(Object? v, double fb) => v is num ? v.toDouble() : fb;

    final vd = s['visit_date'];
    if (vd is String) _visitDate = DateTime.tryParse(vd) ?? _visitDate;
    _lengthCtrl.text = txt(s['length'], _lengthCtrl.text);
    _widthCtrl.text = txt(s['width'], _widthCtrl.text);
    _depthCtrl.text = txt(s['depth'], _depthCtrl.text);
    _volumeCtrl.text = txt(s['volume'], _volumeCtrl.text);
    _volumeAutoFollowing = s['volume_auto_following'] as bool? ?? _volumeAutoFollowing;
    _manualMeasurementCtrl.text = txt(s['manual_measurement'], _manualMeasurementCtrl.text);
    _tunneling = s['tunneling'] as bool? ?? _tunneling;
    _undermining = s['undermining'] as bool? ?? _undermining;
    if (s['tunneling_sites'] != null) {
      _tunnelingSites = (s['tunneling_sites'] as List)
          .map((e) => TunnelingSite.fromJson((e as Map).cast<String, dynamic>()))
          .toList();
    }
    if (s['undermining_sites'] != null) {
      _underminingSites = (s['undermining_sites'] as List)
          .map((e) =>
              UnderminingSite.fromJson((e as Map).cast<String, dynamic>()))
          .toList();
    }
    _granulacion = dbl(s['granulacion'], _granulacion);
    _esfacelo = dbl(s['esfacelo'], _esfacelo);
    _necrosis = dbl(s['necrosis'], _necrosis);
    _epitelizacion = dbl(s['epitelizacion'], _epitelizacion);
    _capturedBeforeDebridement = s['captured_before_debridement'] as bool? ?? _capturedBeforeDebridement;
    _edema = txt(s['edema'], _edema);
    _pain = s['pain'] as bool? ?? _pain;
    _painType = txt(s['pain_type'], _painType);
    _painDuration = txt(s['pain_duration'], _painDuration);
    _painVas = (s['pain_vas'] as num?)?.toInt() ?? _painVas;
    _exudadoCantidad = en(ExudadoCantidad.values, s['exudado_cantidad']) ?? _exudadoCantidad;
    _exudadoTipo = en(ExudadoTipo.values, s['exudado_tipo']) ?? _exudadoTipo;
    if (s['infeccion_criterios'] is List) {
      _infeccionCriterios
        ..clear()
        ..addAll((s['infeccion_criterios'] as List)
            .map((e) => en(InfeccionCriterioIwii.values, e))
            .whereType<InfeccionCriterioIwii>());
    }
    _odor = txt(s['odor'], _odor);
    _woundEdge = txt(s['wound_edge'], _woundEdge);
    if (s['perilesional_skin'] is List) {
      _perilesionalSkin
        ..clear()
        ..addAll((s['perilesional_skin'] as List)
            .map((e) => en(PielPerilesionalEstado.values, e))
            .whereType<PielPerilesionalEstado>());
    }
    _lowAdherence = s['low_adherence'] as bool? ?? _lowAdherence;
    _clinicalNotesCtrl.text = txt(s['clinical_notes'], _clinicalNotesCtrl.text);
    _specialistNotesCtrl.text = txt(s['specialist_notes'], _specialistNotesCtrl.text);
    _visitSummaryCtrl.text = txt(s['visit_summary'], _visitSummaryCtrl.text);
    _careTypeSelected = s['care_type'] as String? ?? _careTypeSelected;
    _careTypeOtherCtrl.text = txt(s['care_type_other'], _careTypeOtherCtrl.text);
    if (s['procedure_desc'] is List) {
      _procedureDescSelected
        ..clear()
        ..addAll((s['procedure_desc'] as List).whereType<String>());
    }
    _procedureDescOtherCtrl.text = txt(s['procedure_desc_other'], _procedureDescOtherCtrl.text);
    if (s['materials_used'] is List) {
      _materialsUsedSelected
        ..clear()
        ..addAll((s['materials_used'] as List).whereType<String>());
    }
    _materialsUsedOtherCtrl.text = txt(s['materials_used_other'], _materialsUsedOtherCtrl.text);
    _evolutionSelected = s['evolution'] as String? ?? _evolutionSelected;
    _evolutionOtherCtrl.text = txt(s['evolution_other'], _evolutionOtherCtrl.text);
    _subtipoOverride = en(SubtipoVascular.values, s['subtipo_override']) ?? _subtipoOverride;
    _noRevascOverride = s['no_revasc_override'] as bool? ?? _noRevascOverride;
    _regimenAccepted = s['regimen_accepted'] as bool? ?? _regimenAccepted;
  }

  void _loadDraftIfNeeded(DataRepository repo, SessionState session) {
    if (_draftLoaded) return;
    _draftLoaded = true;
    final id = widget.draftConsultationId;
    if (id == null) return;
    final c = repo.getConsultation(id);
    if (c == null) return;
    // Inmutabilidad (0097): si la consulta YA está finalizada, no se puede
    // reescribir por URL. Se lleva al detalle (lectura + nota de enmienda), en
    // vez de dejar llenar un formulario que la base rechazaría al guardar.
    if (!c.isDraft) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          context.go('/patients/${widget.patientId}/consultation/${c.id}');
        }
      });
      return;
    }
    // Fecha de la visita: se restaura la ORIGINAL del borrador (antes se quedaba
    // en DateTime.now() y al re-guardar sobrescribía la fecha real en silencio).
    _visitDate = c.visitDate;
    final org = session.user?.organizationId;
    _prefillSingle(NoteOptionField.careType, c.followUpCareType, repo, org,
        (v) => _careTypeSelected = v, _careTypeOtherCtrl);
    _prefillSingle(NoteOptionField.evolution, c.followUpEvolution, repo, org,
        (v) => _evolutionSelected = v, _evolutionOtherCtrl);
    _prefillMulti(NoteOptionField.procedureDesc, c.followUpProcedureDesc, repo,
        org, _procedureDescSelected, _procedureDescOtherCtrl);
    _prefillMulti(NoteOptionField.materialsUsed, c.followUpMaterialsUsed, repo,
        org, _materialsUsedSelected, _materialsUsedOtherCtrl);
    _specialistNotesCtrl.text = c.specialistNotes ?? '';
    _visitSummaryCtrl.text = c.visitSummary ?? '';
    // includeDrafts: la medición que buscamos es la del PROPIO borrador que se
    // reabre (is_draft = true); el filtro por defecto la excluiría.
    final ms = repo
        .listMeasurementsForWound(widget.woundId, includeDrafts: true)
        .where((m) => m.consultationId == id)
        .toList();
    if (ms.isNotEmpty) {
      final m = ms.first;
      String f(double v) =>
          v == v.roundToDouble() ? v.toInt().toString() : v.toString();
      _lengthCtrl.text = f(m.lengthCm);
      _widthCtrl.text = f(m.widthCm);
      _depthCtrl.text = f(m.depthCm);
    }
    // Fotos ya guardadas en el borrador: se muestran y se re-persisten al
    // guardar de nuevo (aunque el clínico no las vuelva a tomar).
    for (final p in repo
        .listPhotosForWound(widget.woundId)
        .where((p) => p.consultationId == id)) {
      if (p.photoStage == PhotoStage.conMedicion) {
        _savedPhotoWithMeasurementPath = p.storagePath;
      } else {
        _savedPhotoAfterCleaningPath = p.storagePath;
      }
    }
    // Valoración clínica ya guardada en el borrador: se pre-carga para editar.
    final asmts = repo
        .listAssessmentsForWound(widget.woundId)
        .where((a) => a.consultationId == id)
        .toList();
    if (asmts.isNotEmpty) {
      final a = asmts.first;
      _edema = a.edema ?? _edema;
      _pain = a.pain ?? _pain;
      _painType = a.painType ?? _painType;
      _painDuration = a.painDuration ?? _painDuration;
      _painVas = a.painVas ?? _painVas;
      _exudadoCantidad = a.exudateAmount;
      _exudadoTipo = a.exudateType ?? _exudadoTipo;
      _infeccionCriterios
        ..clear()
        ..addAll(a.infectionCriteria);
      _odor = a.odor ?? _odor;
      _woundEdge = a.woundEdge ?? _woundEdge;
      _perilesionalSkin
        ..clear()
        ..addAll(a.perilesionalSkin);
      _lowAdherence = a.lowAdherence;
      _clinicalNotesCtrl.text = a.clinicalNotes ?? '';
    }
    // FUENTE DE VERDAD: si el borrador trae una instantánea completa del
    // formulario, se aplica AL FINAL (sobre lo repoblado por fila). Recupera los
    // campos de medición que la restauración por fila no traía (composición del
    // lecho, tunelización/socavamiento, volumen y nota de medición manual).
    final snap = c.draftFormState?['form'];
    if (snap is Map) _applyFormSnapshot(snap.cast<String, dynamic>());
  }

  void _prefillSingle(NoteOptionField field, String? saved, DataRepository repo,
      String? org, void Function(String?) setSel, TextEditingController otherCtrl) {
    final v = (saved ?? '').trim();
    if (v.isEmpty) return;
    final labels =
        repo.listNoteOptions(field, organizationId: org).map((o) => o.label).toSet();
    if (labels.contains(v)) {
      setSel(v);
    } else {
      setSel(kOtherOptionValue);
      otherCtrl.text = v;
    }
  }

  void _prefillMulti(NoteOptionField field, String? saved, DataRepository repo,
      String? org, Set<String> selected, TextEditingController otherCtrl) {
    final v = (saved ?? '').trim();
    if (v.isEmpty) return;
    final labels =
        repo.listNoteOptions(field, organizationId: org).map((o) => o.label).toSet();
    final unmatched = <String>[];
    for (final part
        in v.split('; ').map((s) => s.trim()).where((s) => s.isNotEmpty)) {
      if (labels.contains(part)) {
        selected.add(part);
      } else {
        unmatched.add(part);
      }
    }
    if (unmatched.isNotEmpty) {
      selected.add(kOtherOptionValue);
      otherCtrl.text = unmatched.join('; ');
    }
  }

  /// Patch de columnas de la consulta desde el formulario, para actualizar un
  /// borrador en su lugar (conserva id → no huérfana cobros/insumos).
  Map<String, dynamic> _consultationPatch(
      {required bool draft, required bool withSignature}) {
    final patch = <String, dynamic>{
      'is_draft': draft,
      'visit_date': _visitDate.toIso8601String().substring(0, 10),
      'follow_up_care_type': _careTypeFinal,
      'follow_up_procedure_desc': _procedureDescFinal,
      'follow_up_materials_used': _materialsUsedFinal,
      'follow_up_evolution': _evolutionFinal,
      'specialist_notes': _specialistNotesCtrl.text.trim().isEmpty
          ? null
          : _specialistNotesCtrl.text.trim(),
      'visit_summary': _visitSummaryCtrl.text.trim().isEmpty
          ? null
          : _visitSummaryCtrl.text.trim(),
    };
    if (withSignature) {
      patch['follow_up_signed_by'] = _signedByReadOnly;
      patch['follow_up_signed_license'] = _signedLicenseReadOnly;
      patch['follow_up_signed_specialty'] = _signedSpecialtyReadOnly;
      patch['follow_up_signature'] = _signatureController.toJsonString();
      patch['follow_up_signed_at'] = DateTime.now().toIso8601String();
    }
    // Al FINALIZAR se limpia la instantánea del borrador (ya no es un borrador),
    // igual que wound_capture_screen. En el guardado de borrador la instantánea
    // se escribe aparte (ver _saveDraft).
    if (!draft) patch['draft_form_state'] = null;
    return patch;
  }

  /// Persiste una foto de un borrador: sube los bytes nuevos, o RE-INSERTA el
  /// storage_path ya guardado (para que sobreviva al borrado/recreación de
  /// datos al re-guardar). Best-effort: si la subida falla por red, se encola
  /// offline; si no hay foto ni path para esa etapa, no hace nada.
  Future<void> _persistDraftPhoto(
    DataRepository repo,
    String consultationId,
    String measurementId,
    Uint8List? bytes,
    XFile? file,
    String? savedPath,
    PhotoStage stage,
    String defaultName,
  ) async {
    final meta = <String, dynamic>{
      'wound_id': widget.woundId,
      'consultation_id': consultationId,
      'measurement_id': measurementId,
      'taken_at': _visitDate.toIso8601String(),
      'photo_stage': stage.dbValue,
    };
    if (bytes != null) {
      final fileName = jpgFileName(file?.name, defaultName);
      try {
        final path = await PhotoUploadService.uploadWoundPhoto(
          woundId: widget.woundId,
          consultationId: consultationId,
          bytes: bytes,
          fileName: fileName,
        );
        await repo.createPhoto({...meta, 'storage_path': path});
      } catch (e) {
        await repo.enqueuePhotoIfOffline(
            bytes: bytes, fileName: fileName, meta: meta, error: e);
      }
    } else if (savedPath != null) {
      await repo.createPhoto({...meta, 'storage_path': savedPath});
    }
  }

  /// Guarda un BORRADOR ligero (consulta is_draft + medición) para terminar
  /// después. Solo requiere la medición (largo/ancho, que liga la herida); no
  /// exige foto/firma/nota completa. Si ya venía de un borrador, lo reemplaza.
  Future<void> _saveDraft(BuildContext context, SessionState session) async {
    setState(() => _saving = true);
    final repo = await DataRepository.instance();
    var staffId = session.user?.staffId;
    if (staffId == null && session.user?.role == AppRole.admin) {
      staffId = await repo.ensureAdminStaffId(session.user!);
    }
    if (staffId == null) {
      setState(() => _saving = false);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content:
                Text('No se encontró personal sanitario vinculado a tu cuenta.')));
      }
      return;
    }
    try {
      final patient = repo.getPatient(widget.patientId);
      final sites = repo.listSites();
      final siteId =
          patient?.primarySiteId ?? (sites.isNotEmpty ? sites.first.id : null);
      if (siteId == null) throw StateError('No hay sitios configurados.');

      // Si ya venía de un borrador, se ACTUALIZA en su lugar (conserva el id
      // para no huérfanar el cobro/insumos que se hayan hecho sobre él).
      String consultationId;
      if (widget.draftConsultationId != null) {
        consultationId = widget.draftConsultationId!;
        await repo.updateConsultationFields(
            consultationId, _consultationPatch(draft: true, withSignature: false));
        await repo.deleteWoundDataForConsultation(consultationId);
      } else {
        final consultation = await repo.createConsultation(
          patientId: widget.patientId,
          staffId: staffId,
          siteId: siteId,
          visitType: VisitType.seguimiento,
          visitDate: _visitDate,
          isDraft: true,
          followUpCareType: _careTypeFinal,
          followUpProcedureDesc: _procedureDescFinal,
          followUpMaterialsUsed: _materialsUsedFinal,
          followUpEvolution: _evolutionFinal,
          followUpSignedBy: _signedByReadOnly,
          followUpSignedLicense: _signedLicenseReadOnly,
          followUpSignedSpecialty: _signedSpecialtyReadOnly,
          specialistNotes: _specialistNotesCtrl.text.trim().isEmpty
              ? null
              : _specialistNotesCtrl.text.trim(),
          visitSummary: _visitSummaryCtrl.text.trim().isEmpty
              ? null
              : _visitSummaryCtrl.text.trim(),
        );
        consultationId = consultation.id;
      }
      // Instantánea COMPLETA del formulario (fuente de verdad al reabrir): así
      // no se pierde ningún campo, incluida la composición del lecho.
      await repo.updateConsultationFields(
          consultationId, {'draft_form_state': {'form': _formSnapshot()}});
      // Medición: liga la herida (permite reabrir el borrador).
      final draftMeasurement = await repo.createMeasurement({
        'wound_id': widget.woundId,
        'consultation_id': consultationId,
        'measured_at': _visitDate.toIso8601String().substring(0, 10),
        'length_cm': _lengthCm,
        'width_cm': _widthCm,
        'area_cm2': _areaCm2,
        'depth_cm': _depthCm,
      });
      // El borrador CONSERVA las fotos: sube las nuevas y re-persiste las ya
      // guardadas (mismo storage_path) que el clínico no volvió a tomar.
      await _persistDraftPhoto(
          repo,
          consultationId,
          draftMeasurement.id,
          _photoAfterCleaningBytes,
          _photoAfterCleaning,
          _savedPhotoAfterCleaningPath,
          PhotoStage.despuesLimpiar,
          'seguimiento_despues_limpiar.jpg');
      await _persistDraftPhoto(
          repo,
          consultationId,
          draftMeasurement.id,
          _photoWithMeasurementBytes,
          _photoWithMeasurement,
          _savedPhotoWithMeasurementPath,
          PhotoStage.conMedicion,
          'seguimiento_con_medicion.jpg');
      // El borrador CONSERVA la valoración clínica (edema/dolor/exudado/
      // infección/olor/piel/notas), no solo la medición y las fotos.
      await repo.createAssessment({
        'consultation_id': consultationId,
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
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Borrador guardado. Puedes cobrar y completar la '
                'consulta después.')));
        // Avanza al detalle de la consulta: ahí se seleccionan insumos y se cobra.
        context.go('/patients/${widget.patientId}/consultation/$consultationId');
      }
    } catch (e) {
      if (context.mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('No se pudo guardar el borrador: $e')));
      }
    }
  }

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
    String? newConsultationId;
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

      // Si venimos de un BORRADOR, se ACTUALIZA en su lugar (conserva el id, así
      // el cobro/insumos hechos sobre el borrador siguen ligados); si no, se crea.
      final String consultationId;
      if (widget.draftConsultationId != null) {
        consultationId = widget.draftConsultationId!;
        await repo.updateConsultationFields(consultationId,
            _consultationPatch(draft: false, withSignature: true));
        await repo.deleteWoundDataForConsultation(consultationId);
      } else {
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
          followUpSignedSpecialty: _signedSpecialtyReadOnly,
          followUpSignature: _signatureController.toJsonString(),
          followUpSignedAt: DateTime.now(),
          specialistNotes: _specialistNotesCtrl.text.trim().isEmpty
              ? null
              : _specialistNotesCtrl.text.trim(),
          visitSummary: _visitSummaryCtrl.text.trim().isEmpty
              ? null
              : _visitSummaryCtrl.text.trim(),
        );
        consultationId = consultation.id;
      }
      newConsultationId = consultationId;

      final measurement = await repo.createMeasurement({
        'wound_id': widget.woundId,
        'consultation_id': consultationId,
        'measured_at': _visitDate.toIso8601String().substring(0, 10),
        'length_cm': _lengthCm,
        'width_cm': _widthCm,
        'area_cm2': _areaCm2,
        'depth_cm': _depthCm,
        'tunneling': _tunneling,
        'undermining': _undermining,
        'tunneling_sites':
            _tunneling ? [for (final s in _tunnelingSites) s.toJson()] : [],
        'undermining_sites':
            _undermining ? [for (final s in _underminingSites) s.toJson()] : [],
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
        'consultation_id': consultationId,
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
      // Offline-first Fase 2: si la subida falla por RED, la foto se guarda
      // localmente (IndexedDB) y se sube al reconectar, en vez de perderse.
      var anyPhotoQueued = false;
      Future<void> savePhoto(
          Uint8List bytes, String fileName, String stage) async {
        final meta = <String, dynamic>{
          'wound_id': widget.woundId,
          'consultation_id': consultationId,
          'measurement_id': measurement.id,
          'taken_at': _visitDate.toIso8601String(),
          'photo_stage': stage,
        };
        try {
          final path = await PhotoUploadService.uploadWoundPhoto(
            woundId: widget.woundId,
            consultationId: consultationId,
            bytes: bytes,
            fileName: fileName,
          );
          await repo.createPhoto({...meta, 'storage_path': path});
        } catch (e) {
          final queued = await repo.enqueuePhotoIfOffline(
              bytes: bytes, fileName: fileName, meta: meta, error: e);
          if (queued) {
            anyPhotoQueued = true;
          } else {
            debugPrint('Foto de seguimiento no guardada: $e');
            photoWarning = e.toString().contains('Quota')
                ? 'El seguimiento se registró, pero las fotos no se pudieron '
                    'guardar (memoria del modo demo llena). En producción se '
                    'guardan en la nube.'
                : 'El seguimiento se registró, pero hubo un problema al guardar '
                    'las fotos.';
          }
        }
      }

      if (_photoAfterCleaningBytes != null) {
        await savePhoto(
          _photoAfterCleaningBytes!,
          jpgFileName(_photoAfterCleaning?.name, 'seguimiento_despues_limpiar.jpg'),
          PhotoStage.despuesLimpiar.dbValue,
        );
      } else if (_savedPhotoAfterCleaningPath != null) {
        await repo.createPhoto({
          'wound_id': widget.woundId,
          'consultation_id': consultationId,
          'measurement_id': measurement.id,
          'taken_at': _visitDate.toIso8601String(),
          'photo_stage': PhotoStage.despuesLimpiar.dbValue,
          'storage_path': _savedPhotoAfterCleaningPath,
        });
      }
      if (_photoWithMeasurementBytes != null) {
        await savePhoto(
          _photoWithMeasurementBytes!,
          jpgFileName(_photoWithMeasurement?.name, 'seguimiento_con_medicion.jpg'),
          PhotoStage.conMedicion.dbValue,
        );
      } else if (_savedPhotoWithMeasurementPath != null) {
        await repo.createPhoto({
          'wound_id': widget.woundId,
          'consultation_id': consultationId,
          'measurement_id': measurement.id,
          'taken_at': _visitDate.toIso8601String(),
          'photo_stage': PhotoStage.conMedicion.dbValue,
          'storage_path': _savedPhotoWithMeasurementPath,
        });
      }
      if (anyPhotoQueued && photoWarning == null) {
        photoWarning = 'Sin conexión: el seguimiento y la(s) foto(s) quedaron '
            'guardados en este dispositivo y se subirán al reconectar.';
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
      if (photoWarning != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(photoWarning!),
            backgroundColor: KuraColors.warning,
          ),
        );
      }
      // Tras el seguimiento, ofrece continuar al detalle de la consulta, que es
      // donde se registran los INSUMOS utilizados y se genera el COBRO. Si no,
      // regresa a la lista de seguimiento. (GoRouter declarativo: se usa
      // context.go, no Navigator.pop; el diálogo hace pop con su propio ctx.)
      final continuar = await showDialog<bool>(
        context: context,
        builder: (dctx) => AlertDialog(
          title: const Text('Seguimiento registrado'),
          content: const Text(
              '¿Registrar los insumos utilizados y el cobro de esta consulta?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dctx).pop(false),
              child: const Text('Ahora no'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dctx).pop(true),
              child: const Text('Sí, continuar'),
            ),
          ],
        ),
      );
      if (!context.mounted) return;
      if (continuar == true) {
        context.go(
            '/patients/${widget.patientId}/consultation/$newConsultationId');
      } else {
        context.go(
            '/patients/${widget.patientId}/wound/${widget.woundId}/follow-up');
      }
    }
  }
}

/// Valor centinela para el chip "Otro" en los campos de la nota de
/// seguimiento (no es un id real del catalogo).
const String kOtherOptionValue = '__other__';
