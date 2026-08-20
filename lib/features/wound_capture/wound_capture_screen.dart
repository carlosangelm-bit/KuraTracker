import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import 'package:flutter/foundation.dart' show kIsWeb;

import '../../core/theme/kura_theme.dart';
import '../../core/utils/image_pick_error.dart';
import '../../services/image_transcode.dart';
import '../../core/providers/session_provider.dart';
import '../risk/braden_scale_sheet.dart';
import '../../engine/models/kura_engine_enums.dart';
import '../../models/patient.dart';
import '../../models/consultation.dart';
import '../../models/app_user.dart';
import '../../models/wound.dart' as wmodel;
import '../../models/consent.dart';
import '../../models/treatment_plan.dart';
import '../../services/data_repository.dart';
import '../../services/photo_upload_service.dart';
import '../consents/consents_screen.dart';
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
  // Consulta (borrador) a la que se cuelga la valoración. Puede venir null si se
  // entró por "Nueva valoración" desde el expediente; en ese caso se crea al
  // vuelo en _ensureConsultation antes del primer guardado.
  String? _consultationId;
  Timer? _debounce;
  bool _initialized = false;
  final _picker = ImagePicker();

  // Volumen (feat/volume-kundin-charts): controller propio porque el valor
  // debe re-sincronizarse programaticamente con el auto-calculo de Kundin
  // cada vez que cambia largo/ancho/profundidad, ademas de ser editable a
  // mano por el clinico. _volumeAutoFollowing decide si el campo debe
  // seguir el auto-calculo (true, estado por defecto) o ya fue sobrescrito
  // manualmente (false, hasta que el clinico borre el campo).
  final _volumeCtrl = TextEditingController();
  bool _volumeAutoFollowing = true;

  @override
  void initState() {
    super.initState();
    _draftKey = widget.consultationId ?? 'draft-${widget.patientId}';
    _consultationId = widget.consultationId;
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _volumeCtrl.dispose();
    super.dispose();
  }

  /// Mantiene _volumeCtrl sincronizado con el auto-calculo de Kundin
  /// mientras el clinico no lo haya sobrescrito a mano (_volumeAutoFollowing).
  /// Se llama en cada build tras cualquier cambio de largo/ancho/profundidad.
  void _syncVolumeController(WoundCaptureFormState formState) {
    // Herida vuelta superficial (profundidad 0/null): el volumen 3D no
    // aplica, sin importar si antes se habia editado a mano.
    if (!formState.isDeepWound) {
      _volumeAutoFollowing = true;
      formState.volumeCm3 = null;
      if (_volumeCtrl.text.isNotEmpty) _volumeCtrl.text = '';
      return;
    }
    if (!_volumeAutoFollowing) return;
    final auto = formState.autoVolumeCm3;
    formState.volumeCm3 = auto;
    final text = auto == null ? '' : auto.toStringAsFixed(2);
    if (_volumeCtrl.text != text) {
      _volumeCtrl.text = text;
    }
  }

  void _onVolumeFieldChanged(WoundCaptureFormState formState, String v) {
    if (v.trim().isEmpty) {
      // Campo vaciado por el clinico: vuelve a seguir el auto-calculo.
      _volumeAutoFollowing = true;
      formState.volumeCm3 = formState.autoVolumeCm3;
      return;
    }
    _volumeAutoFollowing = false;
    formState.volumeCm3 = double.tryParse(v.replaceAll(',', '.'));
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
    // Rehidratar un BORRADOR de valoración (0089): si la consulta trae una
    // instantánea, se recarga el formulario (campos + fotos) para continuar
    // editando. Es síncrono, así corre antes del primer _buildForm (los campos
    // leen su initialValue de formState).
    final cid = widget.consultationId;
    if (cid != null) {
      final snap = repo.getConsultation(cid)?.draftFormState;
      final form = snap == null ? null : snap['form'];
      if (form is Map) {
        controller.state.photoPaths.clear();
        controller.state.photoBytesByPath.clear();
        controller.state.applyJson(form.cast<String, dynamic>());
        final photos = snap!['photos'];
        if (photos is List) {
          for (var k = 0; k < photos.length; k++) {
            try {
              final key = 'draft_photo_\$k';
              controller.state.photoPaths.add(key);
              controller.state.photoBytesByPath[key] =
                  base64Decode(photos[k] as String);
            } catch (_) {}
          }
        }
      }
    }
    controller.touch();
  }

  /// Garantiza que exista una consulta (borrador) a la que colgar la valoración.
  /// Algunas entradas —p. ej. "Nueva valoración" desde el expediente— abren la
  /// captura SIN consultationId; aquí se crea al vuelo (is_draft=true) con el
  /// sitio del paciente y el staff de la sesión. Devuelve null solo si falta el
  /// sitio del paciente o el staff (no se puede crear la consulta).
  Future<String?> _ensureConsultation(DataRepository repo) async {
    if (_consultationId != null) return _consultationId;
    final session = ref.read(sessionProvider);
    var staffId = session.user?.staffId;
    if (staffId == null && session.user?.role == AppRole.admin) {
      staffId = await repo.ensureAdminStaffId(session.user!);
    }
    final siteId = repo.getPatient(widget.patientId)?.primarySiteId;
    if (staffId == null || siteId == null) return null;
    final consultation = await repo.createConsultation(
      patientId: widget.patientId,
      staffId: staffId,
      siteId: siteId,
      visitType: VisitType.valoracion,
      visitDate: DateTime.now(),
      isDraft: true,
    );
    _consultationId = consultation.id;
    return _consultationId;
  }

  /// Guarda el BORRADOR de valoración: una instantánea del formulario (campos +
  /// fotos en base64) en consultations.draft_form_state, para reabrirlo editable.
  /// No exige completitud ni consentimientos; guarda lo que haya.
  Future<void> _saveDraft(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final repo = await DataRepository.instance();
      final cid = await _ensureConsultation(repo);
      if (cid == null) {
        messenger.showSnackBar(const SnackBar(
            content: Text('No se pudo crear la consulta del borrador: el '
                'paciente no tiene sitio asignado o tu usuario no está '
                'vinculado a personal.')));
        return;
      }
      final formState = ref.read(woundCaptureControllerProvider(_draftKey));
      final photos = <String>[
        for (final p in formState.photoPaths)
          if (formState.photoBytesByPath[p] != null)
            base64Encode(formState.photoBytesByPath[p]!),
      ];
      await repo.updateConsultationFields(cid, {
        'draft_form_state': {'form': formState.toJson(), 'photos': photos},
      });
      if (!context.mounted) return;
      messenger.showSnackBar(const SnackBar(
          content: Text('Borrador guardado. Puedes continuarlo después.')));
      context.go('/patients/\${widget.patientId}/consultation/\$cid');
    } catch (e) {
      messenger.showSnackBar(
          SnackBar(content: Text('No se pudo guardar el borrador: \$e')));
    }
  }

  /// Ofrece TOMAR la foto con la cámara (en móvil-web abre la cámara del
  /// dispositivo vía el atributo capture) o ELEGIR un archivo/foto existente.
  /// En escritorio-web el capture se ignora y ambas abren el selector de
  /// archivos. Antes solo existía galería, por eso en Android no se podía tomar
  /// la foto desde la app.
  Future<void> _pickPhotoSource() async {
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
    if (source != null) await _pickImage(source);
  }

  Future<void> _pickImage(ImageSource source) async {
    // Gating (Protocolo "Expedientes clínicos"): la toma de fotografía requiere
    // el consentimiento de fotografía registrado.
    final repo = await DataRepository.instance();
    if (!repo.hasConsent(widget.patientId, ConsentType.fotografia)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
              'Registra el consentimiento de fotografía antes de tomar fotos.'),
          action: SnackBarAction(
            label: 'Registrar',
            onPressed: () =>
                context.go('/patients/${widget.patientId}/consents'),
          ),
        ),
      );
      return;
    }
    try {
      // En web NO se piden imageQuality/maxWidth: ese re-escalado del plugin
      // falla con HEIC de iPhone. Se traen los bytes crudos y se convierten a
      // JPEG en el navegador (transcodeImageToJpeg, que además reescala).
      final file = await _picker.pickImage(
        source: source,
        imageQuality: kIsWeb ? null : 85,
        maxWidth: kIsWeb ? null : 1600,
        maxHeight: kIsWeb ? null : 1600,
      );
      if (file != null) {
        // Se leen los bytes AHORA para poder subirlos a Storage al guardar
        // (en web file.path es una blob URL que no se puede leer luego).
        final raw = await file.readAsBytes();
        final jpeg = await transcodeImageToJpeg(raw, name: file.name);
        // En web la conversión es obligatoria (los bytes crudos pueden ser HEIC
        // no mostrable). Si no se pudo decodificar, se avisa y no se agrega.
        if (jpeg == null && kIsWeb) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(imagePickErrorMessage('formato'))));
          return;
        }
        final bytes = jpeg ?? raw;
        final controller = ref.read(woundCaptureControllerProvider(_draftKey).notifier);
        controller.state.photoPaths.add(file.path);
        controller.state.photoBytesByPath[file.path] = bytes;
        controller.touch();
      }
    } catch (e) {
      // Antes se tragaba el error en silencio: el usuario "no podía" cargar la
      // foto sin saber por qué (típicamente HEIC de iPhone). Ahora se avisa.
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(imagePickErrorMessage(e))));
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
            onPressed: () => _saveDraft(context),
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

    // Gating de consentimientos (Protocolos "Expedientes clínicos" /
    // "Desbridamiento"): la valoración y la fotografía requieren privacidad +
    // fotografía; si la captura fue POSTERIOR al desbridamiento, además exige
    // el consentimiento de desbridamiento.
    final requeridos = <ConsentType>[
      ConsentType.privacidad,
      ConsentType.fotografia,
      if (!formState.capturedBeforeDebridement) ConsentType.desbridamiento,
    ];
    final faltantes = repo.missingConsents(widget.patientId, requeridos);
    if (faltantes.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              'Faltan consentimientos: ${faltantes.map((t) => t.label).join(', ')}. '
              'Regístralos antes de guardar la valoración.'),
          action: SnackBarAction(
            label: 'Registrar',
            onPressed: () =>
                context.go('/patients/${widget.patientId}/consents'),
          ),
        ),
      );
      return;
    }

    wmodel.Wound wound;
    String? consultationId;
    try {
      // Crea o reutiliza la herida.
      if (widget.woundId != null && widget.woundId != 'new') {
        wound = repo.getWound(widget.woundId!)!;
        // Actualizar: si en esta re-valoración se fijó el subtipo vascular,
        // persistir el perfil diagnóstico en la herida (el formulario no se
        // precarga, así que solo se toca cuando el clínico lo definió ahora,
        // para no borrar lo ya guardado).
        if (formState.subtipoVascular != null) {
          wound = await repo.updateWound(wound.id, {
            'subtipo_vascular': formState.subtipoVascular!.name,
            'no_revascularizable': formState.noRevascularizable,
          });
        }
      } else {
        wound = await repo.createWound({
          'patient_id': widget.patientId,
          'etiology': formState.etiologia.dbValue,
          'subtype': formState.subtype,
          'subtipo_vascular': formState.subtipoVascular?.name,
          'no_revascularizable': formState.noRevascularizable,
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
          // Clasificaciones/campos por etiología (Prompt 5, migración 0028).
          'upd_subtipo': formState.updSubtipo?.name,
          'texas_grade': formState.texasGrade?.name,
          'texas_stage': formState.texasStage?.name,
          'idsa_iwgdf': formState.idsaIwgdf?.name,
          'sensibilidad_protectora': formState.sensibilidadProtectora?.name,
          'rutherford': formState.rutherford?.name,
          'npuap_estadio': formState.npuapEstadio?.name,
          'clase_contaminacion': formState.claseContaminacion?.name,
          'tipo_cierre': formState.tipoCierre?.name,
          'drenaje_tipo': formState.drenajeTipo?.name,
          'sutura_tipo': formState.suturaTipo?.name,
          'drenaje_num': formState.drenajeNum,
          'sutura_num': formState.suturaNum,
        });
      }

      consultationId = await _ensureConsultation(repo);
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
          'clinical_notes': (formState.clinicalNotes?.trim().isEmpty ?? true)
              ? null
              : formState.clinicalNotes!.trim(),
          'itb_texto': _trimOrNull(formState.itbTexto),
          'pruebas_sensibilidad': _trimOrNull(formState.pruebasSensibilidad),
          'llenado_capilar': _trimOrNull(formState.llenadoCapilar),
        });

        // Braden es del PACIENTE (riesgo de LPP), no de la visita: si se
        // capturó en esta valoración, se registra también en su PERFIL
        // (risk_assessments) para que viva ahí, lo use el motor en el
        // seguimiento y sea re-evaluable desde el módulo de prevención.
        if (formState.bradenScore != null) {
          final session = ref.read(sessionProvider);
          await repo.addRiskAssessment(
            patientId: widget.patientId,
            organizationId: session.user?.organizationId,
            bradenScore: formState.bradenScore,
            bradenSubscores: formState.bradenSubscores,
            staffId: session.user?.staffId,
          );
        }

        final measurement = await repo.createMeasurement({
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
          'volume_cm3': formState.volumeCm3,
          'volume_manual': formState.isVolumeManuallyOverridden,
        });

        await repo.upsertPerfusion({
          'consultation_id': consultationId,
          'wound_id': wound.id,
          'abi_right': formState.abiRight,
          'abi_left': formState.abiLeft,
          'is_lower_extremity': formState.esExtremidadInferior,
          'albumin_g_dl': formState.albuminaGdl,
        });

        // Fotos de la valoración: subir a Storage + registrar en wound_photos.
        // ANTES no se persistían (solo se guardaba la ruta local y la foto se
        // perdía), por eso "Foto basal" salía vacía. La primera queda marcada
        // como basal (is_baseline). En un try aparte: si una foto falla, la
        // valoración clínica YA se guardó y solo se avisa.
        final photoPaths = List<String>.from(formState.photoPaths);
        for (var i = 0; i < photoPaths.length; i++) {
          final bytes = formState.photoBytesByPath[photoPaths[i]];
          if (bytes == null) continue;
          final fileName = 'valoracion_${i + 1}.jpg';
          final meta = <String, dynamic>{
            'wound_id': wound.id,
            'consultation_id': consultationId,
            'measurement_id': measurement.id,
            'taken_at': DateTime.now().toIso8601String(),
            'is_baseline': i == 0,
            'photo_stage': PhotoStage.conMedicion.dbValue,
          };
          try {
            final storagePath = await PhotoUploadService.uploadWoundPhoto(
              woundId: wound.id,
              consultationId: consultationId,
              bytes: bytes,
              fileName: fileName,
            );
            await repo.createPhoto({...meta, 'storage_path': storagePath});
          } catch (e) {
            // Offline-first Fase 2: si falla por RED, la foto se guarda
            // localmente (IndexedDB) y se sube al reconectar, en vez de perderse.
            final queued = await repo.enqueuePhotoIfOffline(
                bytes: bytes, fileName: fileName, meta: meta, error: e);
            debugPrint('Foto de valoración ${queued ? "encolada" : "no guardada"}: $e');
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                    content: Text(queued
                        ? 'Sin conexión: la foto quedó guardada en este '
                            'dispositivo y se subirá al reconectar.'
                        : 'La valoración se guardó, pero una foto no se pudo subir.')),
              );
            }
          }
        }
        // Finaliza el borrador: la valoración ya quedó completa, así que la
        // consulta deja de ser draft (si no, reaparecería como pendiente y
        // volvería a abrir la valoración).
        await repo.updateConsultationFields(
            consultationId, {'is_draft': false, 'draft_form_state': null});
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

    // Mantiene el campo de volumen sincronizado con el auto-calculo de
    // Kundin tras cualquier cambio de largo/ancho/profundidad (ver
    // _syncVolumeController), a menos que el clinico lo haya sobrescrito
    // a mano en este borrador.
    _syncVolumeController(formState);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Gating (Protocolo "Expedientes clínicos"): la valoración y la
        // fotografía requieren consentimiento de privacidad + fotografía.
        ConsentGateBanner(
          patientId: widget.patientId,
          repo: repo,
          required: const [ConsentType.privacidad, ConsentType.fotografia],
          actionLabel: 'la valoración y la toma de fotografía',
        ),
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
                              onTap: () => update(() {
                                formState.photoPaths.remove(p);
                                formState.photoBytesByPath.remove(p);
                              }),
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
                    onTap: _pickPhotoSource,
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
              const SizedBox(height: 8),
              // KT-9/KT-14: zona específica en texto abierto para precisar
              // dentro del área seleccionada (p. ej. qué dedo del pie).
              TextFormField(
                initialValue: formState.bodyLocationSecondary,
                decoration: const InputDecoration(
                  labelText: 'Zona específica (dentro del área)',
                  hintText: 'p. ej. 2º dedo del pie derecho, maléolo externo, coxis…',
                  isDense: true,
                ),
                onChanged: (v) => formState.bodyLocationSecondary =
                    v.trim().isEmpty ? null : v.trim(),
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
        if (formState.showLowerLimbExam) ...[
          const SizedBox(height: 12),
          _buildLowerLimbExamSection(formState, update),
        ],
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
                          .map((e) => DropdownMenuItem(value: e, child: Text(e.label)))
                          .toList(),
                      onChanged: (v) =>
                          update(() => formState.exudadoTipo = v ?? ExudadoTipo.serohematico),
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
                    label: Text(c.label, style: const TextStyle(fontSize: 12)),
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
                      // Olor binario (María): presente / no presente. El guard
                      // normaliza registros legacy (leve/moderado/fuerte).
                      value: formState.odor == 'ninguno' ? 'ninguno' : 'presente',
                      decoration: const InputDecoration(labelText: 'Olor *'),
                      items: const [
                        DropdownMenuItem(
                            value: 'ninguno', child: Text('No presente')),
                        DropdownMenuItem(
                            value: 'presente', child: Text('Presente')),
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
              const SizedBox(height: 12),
              TextFormField(
                initialValue: formState.clinicalNotes,
                maxLines: 4,
                minLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Notas clínicas / Observaciones (opcional)',
                  hintText: 'Observaciones adicionales de la visita…',
                  alignLabelWithHint: true,
                ),
                onChanged: (v) => update(() => formState.clinicalNotes = v),
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
              if (formState.isDeepWound) ...[
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
                        onChanged: (v) => update(() => _onVolumeFieldChanged(formState, v)),
                      ),
                      if (formState.isVolumeManuallyOverridden) ...[
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
              // Gating (Protocolo "Desbridamiento"): registrar composición tras
              // desbridamiento requiere el consentimiento de desbridamiento.
              ConsentGateBanner(
                patientId: widget.patientId,
                repo: repo,
                required: const [ConsentType.desbridamiento],
                actionLabel: 'el desbridamiento',
              ),
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

  /// Fila etiquetada de ChoiceChips para un enum (Prompt 5): reduce el
  /// boilerplate de las clasificaciones por etiología. Mismo patrón visual que
  /// los selectores existentes (Wrap + ChoiceChip).
  Widget _enumChips<T>({
    required String title,
    required List<T> values,
    required T? selected,
    required String Function(T) label,
    required ValueChanged<T> onSelected,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: values.map((v) {
            return ChoiceChip(
              label: Text(label(v)),
              selected: selected == v,
              selectedColor: KuraColors.primary.withOpacity(0.18),
              onSelected: (_) => onSelected(v),
            );
          }).toList(),
        ),
      ],
    );
  }

  static String? _trimOrNull(String? s) {
    final t = s?.trim() ?? '';
    return t.isEmpty ? null : t;
  }

  /// Exploración de miembros inferiores (úlcera vascular / pie diabético):
  /// ITB, pruebas de sensibilidad y llenado capilar como TEXTO LIBRE por visita
  /// (petición de María). Distinto del ITB numérico que alimenta el motor.
  Widget _buildLowerLimbExamSection(
      WoundCaptureFormState formState, void Function(VoidCallback) update) {
    return _SectionCard(
      icon: Icons.medical_services_outlined,
      title: 'Exploración de miembros inferiores',
      subtitle: 'ITB, sensibilidad y llenado capilar (texto libre)',
      initiallyExpanded: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextFormField(
            initialValue: formState.itbTexto,
            decoration: const InputDecoration(
              labelText: 'ITB (índice tobillo-brazo)',
              hintText: 'p. ej. Der. 0.9 / Izq. 0.85; sin claudicación…',
            ),
            onChanged: (v) => update(() => formState.itbTexto = v),
          ),
          const SizedBox(height: 12),
          TextFormField(
            initialValue: formState.pruebasSensibilidad,
            maxLines: 3,
            minLines: 2,
            decoration: const InputDecoration(
              labelText: 'Pruebas de sensibilidad',
              hintText: 'Monofilamento 10 g, diapasón, sensibilidad protectora…',
              alignLabelWithHint: true,
            ),
            onChanged: (v) => update(() => formState.pruebasSensibilidad = v),
          ),
          const SizedBox(height: 12),
          TextFormField(
            initialValue: formState.llenadoCapilar,
            decoration: const InputDecoration(
              labelText: 'Llenado capilar',
              hintText: 'p. ej. < 2 s / > 3 s en primer ortejo…',
            ),
            onChanged: (v) => update(() => formState.llenadoCapilar = v),
          ),
        ],
      ),
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
              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 8),
              _enumChips<UpdSubtipo>(
                title: 'Subtipo clínico',
                values: UpdSubtipo.values,
                selected: formState.updSubtipo,
                label: (v) => v.label,
                onSelected: (v) => update(() => formState.updSubtipo = v),
              ),
              const SizedBox(height: 12),
              _enumChips<TexasGrade>(
                title: 'Universidad de Texas — grado (profundidad)',
                values: TexasGrade.values,
                selected: formState.texasGrade,
                label: (v) => v.label,
                onSelected: (v) => update(() => formState.texasGrade = v),
              ),
              const SizedBox(height: 12),
              _enumChips<TexasStage>(
                title: 'Universidad de Texas — estadio',
                values: TexasStage.values,
                selected: formState.texasStage,
                label: (v) => v.label,
                onSelected: (v) => update(() => formState.texasStage = v),
              ),
              const SizedBox(height: 12),
              _enumChips<IdsaIwgdf>(
                title: 'Infección IDSA/IWGDF',
                values: IdsaIwgdf.values,
                selected: formState.idsaIwgdf,
                label: (v) => v.label,
                onSelected: (v) => update(() => formState.idsaIwgdf = v),
              ),
              const SizedBox(height: 12),
              _enumChips<SensibilidadProtectora>(
                title: 'Monofilamento 10 g / sensibilidad protectora',
                values: SensibilidadProtectora.values,
                selected: formState.sensibilidadProtectora,
                label: (v) => v.label,
                onSelected: (v) =>
                    update(() => formState.sensibilidadProtectora = v),
              ),
            ],
          ),
        );
      case Etiologia.vascular:
        return _SectionCard(
          icon: Icons.water_drop_outlined,
          title: 'Úlcera vascular — Subtipo y clasificación',
          subtitle:
              'El subtipo separa el manejo venoso (compresión) del arterial (terapia seca)',
          initiallyExpanded: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Subtipo vascular'),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: SubtipoVascular.values.map((s) {
                  final selected = formState.subtipoVascular == s;
                  return ChoiceChip(
                    label: Text(s.label),
                    selected: selected,
                    selectedColor: KuraColors.primary.withOpacity(0.18),
                    onSelected: (_) =>
                        update(() => formState.subtipoVascular = s),
                  );
                }).toList(),
              ),
              if (formState.subtipoVascular == SubtipoVascular.arterial ||
                  formState.subtipoVascular == SubtipoVascular.mixta)
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('No revascularizable (Doppler/angiólogo)'),
                  subtitle: const Text(
                      'Activa terapia seca aunque el ITB no sea crítico'),
                  value: formState.noRevascularizable,
                  onChanged: (v) =>
                      update(() => formState.noRevascularizable = v),
                ),
              // Rutherford: aplica al subtipo ARTERIAL/mixto (isquemia).
              if (formState.subtipoVascular == SubtipoVascular.arterial ||
                  formState.subtipoVascular == SubtipoVascular.mixta) ...[
                const SizedBox(height: 12),
                _enumChips<Rutherford>(
                  title: 'Categoría de Rutherford (isquemia arterial)',
                  values: Rutherford.values,
                  selected: formState.rutherford,
                  label: (v) => v.label,
                  onSelected: (v) => update(() => formState.rutherford = v),
                ),
              ],
              const SizedBox(height: 12),
              const Text('Clasificación CEAP'),
              const SizedBox(height: 8),
              Wrap(
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
            ],
          ),
        );
      case Etiologia.quirurgica:
        return _SectionCard(
          icon: Icons.medical_services_outlined,
          title: 'Herida quirúrgica — WUWHS + clasificación',
          subtitle: 'G4 activa interconsulta urgente automática',
          initiallyExpanded: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _enumChips<WuwhsGrade>(
                title: 'Grado WUWHS',
                values: WuwhsGrade.values,
                selected: formState.wuwhsGrade,
                label: (v) => v.name.toUpperCase(),
                onSelected: (v) => update(() => formState.wuwhsGrade = v),
              ),
              const SizedBox(height: 12),
              _enumChips<ClaseContaminacion>(
                title: 'Clase de contaminación (CDC)',
                values: ClaseContaminacion.values,
                selected: formState.claseContaminacion,
                label: (v) => v.label,
                onSelected: (v) =>
                    update(() => formState.claseContaminacion = v),
              ),
              const SizedBox(height: 12),
              _enumChips<TipoCierre>(
                title: 'Tipo de cierre',
                values: TipoCierre.values,
                selected: formState.tipoCierre,
                label: (v) => v.label,
                onSelected: (v) => update(() => formState.tipoCierre = v),
              ),
              const SizedBox(height: 12),
              _enumChips<DrenajeTipo>(
                title: 'Drenaje',
                values: DrenajeTipo.values,
                selected: formState.drenajeTipo,
                label: (v) => v.label,
                onSelected: (v) => update(() => formState.drenajeTipo = v),
              ),
              if (formState.drenajeTipo != null &&
                  formState.drenajeTipo != DrenajeTipo.ninguno) ...[
                const SizedBox(height: 8),
                TextFormField(
                  decoration:
                      const InputDecoration(labelText: 'Nº de drenajes'),
                  keyboardType: TextInputType.number,
                  onChanged: (v) =>
                      update(() => formState.drenajeNum = int.tryParse(v)),
                ),
              ],
              const SizedBox(height: 12),
              _enumChips<SuturaTipo>(
                title: 'Sutura / afrontamiento',
                values: SuturaTipo.values,
                selected: formState.suturaTipo,
                label: (v) => v.label,
                onSelected: (v) => update(() => formState.suturaTipo = v),
              ),
              if (formState.suturaTipo != null &&
                  formState.suturaTipo != SuturaTipo.ninguna) ...[
                const SizedBox(height: 8),
                TextFormField(
                  decoration: const InputDecoration(
                      labelText: 'Nº de puntos / grapas'),
                  keyboardType: TextInputType.number,
                  onChanged: (v) =>
                      update(() => formState.suturaNum = int.tryParse(v)),
                ),
              ],
            ],
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
        {
          final bradenScale = ref.watch(bradenScaleProvider).valueOrNull;
          final band = (bradenScale != null && formState.bradenScore != null)
              ? bradenScale.riskLabelFor(formState.bradenScore!)
              : null;
          return _SectionCard(
            icon: Icons.airline_seat_flat_outlined,
            title: 'Lesión por presión — Escala de Braden *',
            subtitle:
                'Riesgo de LPP: a menor puntaje, mayor riesgo (obligatorio)',
            initiallyExpanded: true,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _enumChips<NpuapEstadio>(
                  title: 'Estadio NPUAP/EPUAP',
                  values: NpuapEstadio.values,
                  selected: formState.npuapEstadio,
                  label: (v) => v.label,
                  onSelected: (v) => update(() => formState.npuapEstadio = v),
                ),
                const SizedBox(height: 16),
                const Divider(),
                const SizedBox(height: 8),
                // Escala COMPLETA (6 subescalas) — vía principal, la misma que
                // el módulo de prevención/hospital: calcula el total y guarda
                // las subescalas en el perfil del paciente.
                Align(
                  alignment: Alignment.centerLeft,
                  child: FilledButton.tonalIcon(
                    icon: const Icon(Icons.checklist_rtl),
                    label: Text(formState.bradenSubscores == null
                        ? 'Valorar Braden (escala completa)'
                        : 'Re-valorar Braden (escala completa)'),
                    onPressed: bradenScale == null
                        ? null
                        : () async {
                            final res = await showBradenScaleSheet(
                                context, bradenScale);
                            if (res == null) return;
                            update(() {
                              formState.bradenScore = res.total;
                              formState.bradenSubscores = res.subscores;
                            });
                          },
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'Puntaje total: ${formState.bradenScore ?? '—'} / 23'
                  '${band != null ? ' · $band' : ''}'
                  '${formState.bradenSubscores == null && formState.bradenScore != null ? ' (manual)' : ''}',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Text(
                  'Recomendado: usa la escala completa. El slider es un ajuste '
                  'manual del total (6-23) si necesitas sobrescribirlo.',
                  style: TextStyle(
                      fontSize: 12,
                      color: KuraColors.darkText.withOpacity(0.6)),
                ),
                const SizedBox(height: 8),
                Slider(
                  value: (formState.bradenScore ?? 23).toDouble(),
                  min: 6,
                  max: 23,
                  divisions: 17,
                  activeColor: KuraColors.primary,
                  label: '${formState.bradenScore ?? 23}',
                  onChanged: (v) => update(() {
                    formState.bradenScore = v.round();
                    // Override manual: las subescalas ya no corresponden al total.
                    formState.bradenSubscores = null;
                  }),
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
        }
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
