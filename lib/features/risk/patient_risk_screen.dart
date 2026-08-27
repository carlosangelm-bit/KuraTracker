import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/theme/kura_theme.dart';
import '../../core/layout/responsive.dart';
import '../../core/providers/session_provider.dart';
import '../../models/center_type.dart';
import '../../engine/risk/prevention_risk_engine.dart';
import '../../engine/risk/braden_scale.dart';
import '../../engine/risk/scale_applicability.dart';
import '../../engine/risk/sum_scale.dart';
import 'braden_scale_sheet.dart';
import 'category_sheet.dart';
import 'globiad_sheet.dart';
import 'extravasacion_sheet.dart';
import 'istap_sheet.dart';
import 'marsi_sheet.dart';
import 'quemaduras_sheet.dart';
import 'star_sheet.dart';
import 'sum_scale_sheet.dart';
import 'triage_sheet.dart';
import '../../models/app_user.dart';
import '../../models/patient.dart';
import '../../models/patient_admission.dart';
import '../../models/preventive_task.dart';
import '../../services/data_repository.dart';
import '../prevention/caregiver_plan_builder_sheet.dart';
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

  /// Formulario de Braden por subescalas: el profesional elige una opción por
  /// ítem y la app calcula el total y la banda de riesgo. Guarda el total
  /// (braden_score) y las subescalas (braden_subscores).
  Future<void> _assessBraden(DataRepository repo, BradenScale scale) async {
    final res = await showBradenScaleSheet(context, scale);
    if (res == null || !mounted) return;
    final session = ref.read(sessionProvider);
    await repo.addRiskAssessment(
      patientId: widget.patientId,
      organizationId: session.user?.organizationId,
      bradenScore: res.total,
      bradenSubscores: res.subscores,
      notes: res.notes,
      staffId: await _staffId(repo),
    );
    // Hospital: la valoración detona el plan preventivo esperado por nivel
    // (tareas sin dueño; el profesional puede ajustar). En otros centros no aplica.
    final catalog = ref.read(preventionRulesProvider).valueOrNull;
    if (catalog != null) {
      await repo.autoGeneratePlanIfHospital(
        widget.patientId,
        catalog,
        organizationId: session.user?.organizationId,
        createdBy: session.user?.id,
      );
    }
    if (mounted) setState(() {});
  }

  /// Captura de una escala (guiada o manual), guarda la valoración y aplica su
  /// tratamiento a la bitácora si corresponde. Un dispatcher por scaleId: agregar
  /// una escala nueva = un case aquí + su hoja + su regla de aplicabilidad.
  Future<void> _assessScale(DataRepository repo, String scaleId) async {
    // Escalas tipo SUMA (PUSH/RESVECH/ASEPSIS): definición en asset, total 0..max.
    if (scaleId == 'PUSH' || scaleId == 'RESVECH' || scaleId == 'ASEPSIS') {
      final def = await SumScaleDef.load(scaleId);
      // Valoración PREVIA — se lee ANTES de mostrar la hoja: alimenta la vista
      // previa de tendencia y la interpretación al guardar. Si se leyera después
      // de guardar, la "anterior" sería la que acabamos de registrar.
      final prev = repo.latestScaleAssessment(widget.patientId, scaleId);
      if (!mounted) return;
      final r = await showSumScaleSheet(context, def,
          previousTotal: prev?.totalScore);
      if (r == null || !mounted) return;
      final session = ref.read(sessionProvider);
      final reading = def.interpret(r.total, previousTotal: prev?.totalScore);
      // band_id = CÓDIGO ESTABLE (llave de reglas); category_result = etiqueta
      // visible. delta/previo/severidad quedan en subscores como hecho de
      // auditoría (y para renderizar sin una segunda consulta).
      final subscores = <String, dynamic>{
        ...r.subscores,
        if (prev?.totalScore != null) 'previous_total': prev!.totalScore,
        if (prev != null) 'previous_at': prev.assessedAt.toIso8601String(),
        if (reading.delta != null) 'delta': reading.delta,
        if (reading.severity != null) 'severity': reading.severity,
      };
      await repo.addScaleAssessment(
        patientId: widget.patientId,
        organizationId: session.user?.organizationId,
        scaleId: scaleId,
        scaleVersion: def.draft ? '2.0-draft' : '1.0',
        totalScore: r.total,
        categoryResult: reading.label,
        bandId: reading.bandId,
        subscores: subscores,
        notes: r.notes,
        staffId: await _staffId(repo),
      );
      if (scaleId == 'ASEPSIS') {
        await repo.applyAsepsisTreatment(widget.patientId,
            severity: reading.severity,
            organizationId: session.user?.organizationId,
            createdBy: session.user?.id);
      }
      if (!mounted) return;
      setState(() {});
      final resumen = reading.label == null
          ? 'total ${r.total.toStringAsFixed(0)}'
          : '${r.total.toStringAsFixed(0)} · ${reading.label}';
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$scaleId $resumen registrado')));
      return;
    }
    // Quemaduras: FÓRMULA (índice de Garcés) → banda + índice.
    if (scaleId == 'QUEMADURA') {
      final edad = repo.getPatient(widget.patientId)?.age ?? 0;
      final r = await showQuemadurasSheet(context, edad: edad);
      if (r == null || !mounted) return;
      final session = ref.read(sessionProvider);
      await repo.addScaleAssessment(
        patientId: widget.patientId,
        organizationId: session.user?.organizationId,
        scaleId: scaleId,
        scaleVersion: '1.0',
        categoryResult: r.band,
        bandId: r.band,
        totalScore: r.indice,
        subscores: r.subscores,
        notes: r.notes,
        staffId: await _staffId(repo),
      );
      await repo.applyQuemaduraTreatment(
        widget.patientId,
        band: r.band,
        criterioHospitalizacion: r.criterioHospitalizacion,
        organizationId: session.user?.organizationId,
        createdBy: session.user?.id,
      );
      if (!mounted) return;
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Quemadura · ${r.band} (índice ${r.indice.toStringAsFixed(0)})')));
      return;
    }
    ({String category, Map<String, dynamic> subscores, String? notes})? res;
    switch (scaleId) {
      case 'GLOBIAD':
        res = await showGlobiadSheet(context);
        break;
      case 'ISTAP':
        res = await showIstapSheet(context);
        break;
      case 'STAR':
        res = await showStarSheet(context);
        break;
      case 'MARSI':
        res = await showMarsiSheet(context);
        break;
      case 'EXTRAVASACION':
        res = await showExtravasacionSheet(context);
        break;
      case 'NPIAP':
        res = await showCategorySheet(context,
            title: 'NPIAP/EPUAP · Estadificación de LPP',
            subtitle: 'Estadio de la lesión por presión establecida.',
            options: const [
              ('I', 'Estadio I · Eritema no blanqueable, piel intacta'),
              ('II', 'Estadio II · Pérdida parcial de la dermis'),
              ('III', 'Estadio III · Pérdida total de la piel, grasa visible'),
              ('IV', 'Estadio IV · Hueso / tendón / músculo expuestos'),
              ('NO_CLASIFICABLE',
                  'No clasificable · profundidad oculta por esfacelo/escara'),
              ('SOSPECHA_TEJIDO_PROFUNDO',
                  'Sospecha de lesión tisular profunda'),
            ]);
        break;
      case 'WAGNER':
        res = await showCategorySheet(context,
            title: 'Wagner · Pie diabético',
            options: const [
              ('0', 'Grado 0 · Pie de riesgo, sin úlcera'),
              ('1', 'Grado 1 · Úlcera superficial'),
              ('2', 'Grado 2 · Úlcera profunda (sin hueso), infectada'),
              ('3', 'Grado 3 · Absceso / sospecha de osteomielitis'),
              ('4', 'Grado 4 · Gangrena localizada'),
              ('5', 'Grado 5 · Gangrena extensa'),
            ]);
        break;
      case 'CEAP':
        res = await showCategorySheet(context,
            title: 'CEAP · Enfermedad venosa (clínica)',
            options: const [
              ('C0', 'C0 · Sin signos visibles ni palpables'),
              ('C1', 'C1 · Telangiectasias / venas reticulares'),
              ('C2', 'C2 · Venas varicosas'),
              ('C3', 'C3 · Edema'),
              ('C4', 'C4 · Cambios cutáneos (pigmentación, eccema…)'),
              ('C5', 'C5 · Cambios cutáneos con úlcera cicatrizada'),
              ('C6', 'C6 · Cambios cutáneos con úlcera activa'),
            ],
            footnote:
                'La compresión sugerida depende de la clase C; descartar '
                'arteriopatía antes de comprimir (recomendación, no auto-prescripción).');
        break;
      case 'MDRPI':
        res = await showCategorySheet(context,
            title: 'MDRPI · LPP por dispositivo médico',
            options: const [
              ('MDR_S', 'Piel (MDR-S) · se estadifica con NPIAP'),
              ('MDR_MM',
                  'Mucosa (MDR-MM) · registro descriptivo, sin estadio NPIAP'),
            ],
            footnote:
                'Si es MDR-S (piel), clasifica también con NPIAP.');
        break;
      default:
        // Salvaguarda: si el catálogo habilitara una escala sin hoja de captura,
        // avisar en vez de que el botón no haga nada (hoy las 13 tienen case).
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Esta escala aún no está disponible para captura.')));
        return;
    }
    if (res == null || !mounted) return;
    final session = ref.read(sessionProvider);
    await repo.addScaleAssessment(
      patientId: widget.patientId,
      organizationId: session.user?.organizationId,
      scaleId: scaleId,
      scaleVersion: '1.0',
      categoryResult: res.category,
      bandId: res.category,
      subscores: res.subscores,
      notes: res.notes,
      staffId: await _staffId(repo),
    );
    // Tratamiento a bitácora según la escala.
    final orgId = session.user?.organizationId;
    final by = session.user?.id;
    if (scaleId == 'GLOBIAD') {
      final catalog = ref.read(preventionRulesProvider).valueOrNull;
      if (catalog != null) {
        await repo.applyGlobiadTreatment(widget.patientId, res.category,
            organizationId: orgId, catalog: catalog, createdBy: by);
      }
    } else if (scaleId == 'STAR') {
      await repo.applyStarTreatment(widget.patientId, res.category,
          organizationId: orgId, createdBy: by);
    } else if (scaleId == 'EXTRAVASACION') {
      await repo.applyExtravasacionTreatment(widget.patientId, res.category,
          organizationId: orgId, createdBy: by);
    } else if (const {'NPIAP', 'WAGNER', 'CEAP', 'MDRPI'}.contains(scaleId)) {
      await repo.applyCategoricalScaleTreatment(
          widget.patientId, scaleId, res.category,
          organizationId: orgId, createdBy: by);
    }
    if (!mounted) return;
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$scaleId ${res.category} registrada')),
    );
  }

  /// Triage de valoración: captura las señales y las guarda; la aplicabilidad se
  /// recalcula sola en el build.
  Future<void> _doTriage(DataRepository repo) async {
    final cat = ref.read(scaleApplicabilityProvider).valueOrNull;
    if (cat == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Cargando catálogo de escalas, intenta de nuevo.')));
      return;
    }
    final last = repo.latestTriage(widget.patientId)?.subscores;
    final initial = last == null
        ? null
        : {for (final e in last.entries) e.key: e.value == true};
    final answers = await showTriageSheet(
      context,
      groups: cat.questionnaire,
      factorLabel: cat.factorLabel,
      initial: initial,
    );
    if (answers == null || !mounted) return;
    final session = ref.read(sessionProvider);
    await repo.saveTriage(
      widget.patientId,
      organizationId: session.user?.organizationId,
      answers: answers,
      staffId: await _staffId(repo),
    );
    if (mounted) setState(() {});
  }

  /// Aviso cuando el motor indica escalas OBLIGATORIAS que el centro tiene
  /// desactivadas (`enabledScales`): antes desaparecían del listado sin rastro.
  /// Nombres solo para admin/master; el conteo, para todos.
  Widget _suppressedScalesBanner(
      List<ApplicableScale> suppressed, bool showNames) {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: KuraColors.warning.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: KuraColors.warning.withValues(alpha: 0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.report_gmailerrorred_outlined,
              size: 18, color: KuraColors.warning),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${suppressed.length} escala(s) indicada(s) están desactivadas '
                  'en la configuración del centro.',
                  style: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w700),
                ),
                if (showNames) ...[
                  const SizedBox(height: 2),
                  Text(suppressed.map((s) => s.label).join(' · '),
                      style: TextStyle(
                          fontSize: 11,
                          color: KuraColors.darkText.withValues(alpha: 0.75))),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _scalesToDoCard(DataRepository repo, List<ApplicableScale> applicable,
      bool hasTriage, ScaleApplicabilityCatalog? cat, bool canPropose,
      bool canValidate, String? orgId) {
    final setInfo = repo.applicableSetState(widget.patientId);
    final triageAt = repo.latestTriage(widget.patientId)?.assessedAt;
    final staleValidation = setInfo.validated &&
        triageAt != null &&
        setInfo.validatedAt != null &&
        triageAt.isAfter(setInfo.validatedAt!);
    // Escalas OBLIGATORIAS que el centro tiene desactivadas (se caían sin señal).
    final suppressed = cat == null
        ? const <ApplicableScale>[]
        : repo.suppressedObligatoryScales(widget.patientId, cat);
    final role = ref.read(sessionProvider).user?.role;
    final isAdminOrMaster = role == AppRole.admin || role == AppRole.master;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text('Escalas a realizar',
                      style:
                          TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                ),
                if (canPropose && cat != null)
                  TextButton.icon(
                    onPressed: () => _addScaleDialog(repo, cat, orgId),
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Agregar'),
                  ),
                TextButton.icon(
                  onPressed: () => _doTriage(repo),
                  icon: const Icon(Icons.fact_check_outlined, size: 18),
                  label: Text(hasTriage ? 'Rehacer triage' : 'Triage'),
                ),
              ],
            ),
            if (suppressed.isNotEmpty)
              _suppressedScalesBanner(suppressed, isAdminOrMaster),
            if (!hasTriage)
              Text(
                  'Haz el triage para determinar las escalas del paciente '
                  '(la diabetes, las heridas y el Braden ya se consideran).',
                  style: TextStyle(
                      fontSize: 12,
                      color: KuraColors.darkText.withValues(alpha: 0.6))),
            if (applicable.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text('Sin escalas adicionales por ahora.',
                    style: TextStyle(
                        fontSize: 12,
                        color: KuraColors.darkText.withValues(alpha: 0.6))),
              )
            else
              for (final s in applicable)
                // Quitar de la propuesta = permiso de diagnóstico (canValidate):
                // no cualquiera puede retirar una escala obligatoria.
                _scaleRow(repo, s, cat, canValidate, orgId),
            if (applicable.isNotEmpty) ...[
              const Divider(height: 18),
              Row(
                children: [
                  // El TEXTO de estatus es visible para TODOS (incluida
                  // enfermería): quien no valida igual debe VER si ya se validó
                  // y por quién. Solo la ACCIÓN de validar se gatea.
                  Expanded(
                    child: Text(
                      setInfo.validated && !staleValidation
                          ? _validatedLabel(
                              repo, setInfo.validatedBy, setInfo.validatedAt)
                          : staleValidation
                              ? 'La propuesta cambió tras el triage: re-valida.'
                              : 'Propuesta del sistema, pendiente de validar.',
                      style: TextStyle(
                          fontSize: 11.5,
                          color: setInfo.validated && !staleValidation
                              ? KuraColors.primary
                              : KuraColors.darkText.withValues(alpha: 0.7)),
                    ),
                  ),
                  if (setInfo.validated && !staleValidation)
                    const Icon(Icons.verified,
                        color: KuraColors.primary, size: 20)
                  else if (canValidate)
                    FilledButton.tonalIcon(
                      onPressed: () => _validateScales(repo, orgId),
                      icon: const Icon(Icons.verified_outlined, size: 16),
                      label: const Text('Validar'),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _addScaleDialog(
      DataRepository repo, ScaleApplicabilityCatalog cat, String? orgId) async {
    final options = repo.addableScales(widget.patientId, cat);
    if (options.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('No hay más escalas del protocolo para agregar.')));
      return;
    }
    final picked = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => ListView(
        shrinkWrap: true,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Text('Agregar escala a la propuesta',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
          ),
          for (final o in options)
            ListTile(
              dense: true,
              title: Text(o.label, style: const TextStyle(fontSize: 14)),
              onTap: () => Navigator.pop(ctx, o.scaleId),
            ),
        ],
      ),
    );
    if (picked == null || !mounted) return;
    await repo.setApplicableOverride(widget.patientId,
        organizationId: orgId,
        scaleId: picked,
        status: 'included',
        staffId: await _staffId(repo));
    if (mounted) setState(() {});
  }

  Future<void> _removeScale(
      DataRepository repo, ApplicableScale s, String? orgId) async {
    // Auto -> EXCLUIDA; manual -> se limpia el override (deja de estar añadida).
    await repo.setApplicableOverride(widget.patientId,
        organizationId: orgId,
        scaleId: s.scaleId,
        status: s.source == ScaleSource.manual ? null : 'excluded',
        staffId: await _staffId(repo));
    if (mounted) setState(() {});
  }

  Future<void> _validateScales(DataRepository repo, String? orgId) async {
    await repo.validateApplicableSet(widget.patientId,
        organizationId: orgId, staffId: await _staffId(repo));
    if (!mounted) return;
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Escalas validadas.')));
  }

  /// Etiqueta "Validada por X el DD/MM" (visible para todos). Resuelve el nombre
  /// del validador desde staff/usuarios.
  String _validatedLabel(DataRepository repo, String? by, DateTime? at) {
    final name = _who(repo, by);
    final date = at == null ? '' : DateFormat('dd/MM/yyyy').format(at);
    final porX = name.isEmpty ? '' : ' por $name';
    final elFecha = date.isEmpty ? '' : ' el $date';
    return 'Validada$porX$elFecha';
  }

  String _who(DataRepository repo, String? id) {
    if (id == null) return '';
    final s = repo.getStaff(id);
    if (s != null) return s.fullName;
    for (final u in repo.listUsers()) {
      if (u.id == id) return u.fullName;
    }
    return '';
  }

  Widget _scaleRow(DataRepository repo, ApplicableScale s,
      ScaleApplicabilityCatalog? cat, bool canRemove, String? orgId) {
    final obligatoria = s.priority == ScalePriority.obligatoria;
    final chipColor = obligatoria ? KuraColors.danger : KuraColors.primary;
    final last = repo.latestScaleAssessment(widget.patientId, s.scaleId);
    // Resultado mostrado: "puntaje · banda" cuando hay ambos (escalas de suma con
    // interpretación); si solo hay uno, ese. Así una escala de suma no pierde su
    // lectura clínica ni su número.
    final lastScore = last?.totalScore?.toStringAsFixed(0);
    final lastBand = last?.categoryResult;
    // Escalas de tendencia (PUSH/RESVECH): el delta guardado se muestra como
    // flecha, p. ej. "9 · Cicatrizando (↓3)". Escalas con bandas: "34 ·
    // Infección moderada". Primera valoración de tendencia: solo el puntaje.
    final lastDelta = last?.subscores?['delta'] as num?;
    final trendSuffix = (lastDelta != null && lastDelta != 0)
        ? ' (${lastDelta < 0 ? '↓' : '↑'}${lastDelta.abs().toStringAsFixed(0)})'
        : '';
    final String? doneCat;
    if (lastScore != null) {
      doneCat =
          lastBand != null ? '$lastScore · $lastBand$trendSuffix' : lastScore;
    } else {
      doneCat = lastBand;
    }
    final porque = (cat == null || s.matchedFactors.isEmpty)
        ? null
        : 'Por: ${s.matchedFactors.map(cat.factorLabel).join(' · ')}';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(s.label,
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(
                        color: chipColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(obligatoria ? 'Obligatoria' : 'Sugerida',
                          style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: chipColor)),
                    ),
                    if (s.source == ScaleSource.manual) ...[
                      const SizedBox(width: 6),
                      Text('Añadida',
                          style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color:
                                  KuraColors.darkText.withValues(alpha: 0.5))),
                    ],
                    if (doneCat != null) ...[
                      const SizedBox(width: 6),
                      Text('Resultado: $doneCat',
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: scaleSeverityColor(
                                  last?.subscores?['severity'] as String?))),
                    ],
                  ],
                ),
                if (porque != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(porque,
                        style: TextStyle(
                            fontSize: 10.5,
                            color: KuraColors.darkText.withValues(alpha: 0.6))),
                  ),
              ],
            ),
          ),
          if (s.implemented)
            TextButton(
              onPressed: () => _assessScale(repo, s.scaleId),
              child: Text(doneCat != null ? 'Revalorar' : 'Valorar'),
            )
          else
            Text('Próximamente',
                style: TextStyle(
                    fontSize: 12,
                    color: KuraColors.darkText.withValues(alpha: 0.4))),
          if (canRemove)
            IconButton(
              tooltip: 'Quitar de la propuesta',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.close, size: 18),
              color: KuraColors.darkText.withValues(alpha: 0.5),
              onPressed: () => _removeScale(repo, s, orgId),
            ),
        ],
      ),
    );
  }

  Future<void> _admit(DataRepository repo) async {
    final floorCtrl = TextEditingController();
    final areaCtrl = TextEditingController();
    final bedCtrl = TextEditingController();
    InputDecoration dec(String label, [String? hint]) => InputDecoration(
          labelText: label,
          hintText: hint,
          border: const OutlineInputBorder(),
          isDense: true,
        );
    final ok = await showModalBottomSheet<bool>(
      context: context,
      useRootNavigator: true,
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
            TextField(controller: floorCtrl, decoration: dec('Piso', 'Ej. 3')),
            const SizedBox(height: 8),
            TextField(
                controller: areaCtrl,
                decoration: dec('Área / servicio', 'Ej. Medicina Interna')),
            const SizedBox(height: 8),
            TextField(controller: bedCtrl, decoration: dec('Cama (opcional)')),
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
    String? t(TextEditingController c) =>
        c.text.trim().isEmpty ? null : c.text.trim();
    await repo.admitPatient(
      patientId: widget.patientId,
      organizationId: session.user?.organizationId,
      floor: t(floorCtrl),
      area: t(areaCtrl),
      bed: t(bedCtrl),
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

  Future<void> _editCaregiverInstructions(
      DataRepository repo, String? organizationId) async {
    final ctrl = TextEditingController(
        text: repo.caregiverInstructionsFor(widget.patientId) ?? '');
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Indicaciones para el cuidador'),
        content: SizedBox(
          width: 420,
          child: TextField(
            controller: ctrl,
            autofocus: true,
            maxLines: 5,
            decoration: const InputDecoration(
              hintText:
                  'Ej.: limpiar con solución fisiológica, no mojar el apósito, '
                  'avisar si hay fiebre o aumento de secreción.',
              border: OutlineInputBorder(),
            ),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Guardar')),
        ],
      ),
    );
    if (saved != true || !mounted) return;
    await repo.setCaregiverInstructions(
      patientId: widget.patientId,
      organizationId: organizationId,
      text: ctrl.text,
      updatedBy: ref.read(sessionProvider).user?.id,
    );
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final repoAsync = ref.watch(dataRepositoryProvider);
    final rulesAsync = ref.watch(preventionRulesProvider);
    final scale = ref.watch(bradenScaleProvider).valueOrNull;
    final applicabilityCat = ref.watch(scaleApplicabilityProvider).valueOrNull;
    // Solo clínico/admin pueden DEFINIR el plan de cuidados. Enfermería (y
    // cuidador) solo lo consultan y ejecutan las tareas en las rondas.
    final canDefinePlan = ref.watch(sessionProvider).user?.canDiagnose == true;
    // Escalas de riesgo: se separa PROPONER de VALIDAR. Proponer (agregar una
    // escala a la propuesta de trabajo) también lo puede hacer enfermería;
    // VALIDAR el resultado clínico y QUITAR escalas de la propuesta es del
    // médico (canDiagnose). El TEXTO de estatus es visible para todos.
    final canValidate = canDefinePlan;
    final canPropose =
        canValidate || ref.watch(sessionProvider).user?.isNurse == true;
    // Hospital: manejo preventivo centrado en el paciente (no hay cuidador
    // externo), así que no aplican las indicaciones libres para el cuidador.
    final isHospital =
        ref.watch(sessionProvider).activeCenterType == CenterType.hospital;

    return Scaffold(
      appBar: AppBar(
        // Atrás = volver al PASO ANTERIOR real (dashboard, tablero de riesgo,
        // etc.) usando la pila de navegación; si no hay pila (p. ej. enlace
        // directo), cae al perfil del paciente. El perfil completo tiene su
        // propio botón explícito en las acciones.
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: 'Volver',
          onPressed: () => context.canPop()
              ? context.pop()
              : context.go('/patients/${widget.patientId}'),
        ),
        title: const Text('Prevención y riesgo'),
        actions: [
          IconButton(
            icon: const Icon(Icons.badge_outlined),
            tooltip: 'Perfil del paciente',
            onPressed: () => context.go('/patients/${widget.patientId}'),
          ),
        ],
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

            // Escalas a realizar (routing por triage + expediente). El motor de
            // aplicabilidad decide cuáles aplican; la captura de cada una vive en
            // su escala (por ahora, GLOBIAD implementada).
            final applicable = applicabilityCat == null
                ? <ApplicableScale>[]
                : repo.applicableScales(widget.patientId, applicabilityCat);
            final hasTriage = repo.latestTriage(widget.patientId) != null;

            return ListView(
              padding: const EdgeInsets.all(20),
              children: [
                _RiskLevelBanner(level: result.level),
                const SizedBox(height: 16),
                // Selector DIRECTO de cuidados (el profesional marca las
                // indicaciones con su cadencia; puede omitir cuidados nocturnos).
                // Esto define/actualiza la agenda del cuidador. Solo clínico/
                // admin; enfermería consulta y ejecuta en las rondas.
                if (canDefinePlan)
                  FilledButton.icon(
                    icon: const Icon(Icons.checklist_rtl),
                    label: const Text('Definir plan de cuidados'),
                    onPressed: () async {
                      final agendada = await showCaregiverPlanBuilder(
                        context,
                        patientId: widget.patientId,
                        organizationId: patient.organizationId,
                      );
                      if (!context.mounted) return;
                      if (agendada == true) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: const Text('Plan agendado.'),
                            action: SnackBarAction(
                              label: 'Ver agenda',
                              onPressed: () => context.go('/prevention-agenda'),
                            ),
                          ),
                        );
                      }
                      setState(() {});
                    },
                  )
                else
                  OutlinedButton.icon(
                    icon: const Icon(Icons.checklist_rtl),
                    label: const Text('Ver plan de cuidados (rondas)'),
                    onPressed: () => context.push('/prevention-agenda'),
                  ),
                const SizedBox(height: 16),
                // Escalas a realizar: derivadas del triage + expediente.
                _scalesToDoCard(repo, applicable, hasTriage, applicabilityCat,
                    canPropose, canValidate, patient.organizationId),
                const SizedBox(height: 16),
                // Tarjetas de la ficha: en desktop refluyen a 2-3 columnas para
                // aprovechar el ancho; en móvil quedan apiladas.
                ResponsiveColumns(
                  blocks: [
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
                    _InfoTile(
                      icon: Icons.monitor_heart_outlined,
                      title: 'Valoración de Braden',
                      body: braden?.bradenScore == null
                          ? 'Sin valoración registrada'
                          : 'Braden ${braden!.bradenScore}'
                              '${scale?.riskLabelFor(braden.bradenScore!) != null ? ' · ${scale!.riskLabelFor(braden.bradenScore!)}' : ''}'
                              ' · ${_dateFmt.format(braden.assessedAt)}',
                      action: TextButton(
                        onPressed: scale == null
                            ? null
                            : () => _assessBraden(repo, scale),
                        child: const Text('Valorar'),
                      ),
                    ),
                    // Indicaciones libres del profesional para el cuidador (0044).
                    // No aplican en hospital (sin cuidador externo).
                    if (!isHospital)
                      _InfoTile(
                        icon: Icons.sticky_note_2_outlined,
                        title: 'Indicaciones para el cuidador',
                        body: (repo.caregiverInstructionsFor(widget.patientId) ??
                                    '')
                                .trim()
                                .isEmpty
                            ? 'Sin indicaciones. Deja el set de cuidados para el '
                                'cuidador (según diagnóstico).'
                            : repo.caregiverInstructionsFor(widget.patientId)!,
                        action: TextButton(
                          onPressed: () => _editCaregiverInstructions(
                              repo, patient.organizationId),
                          child: const Text('Editar'),
                        ),
                      ),
                    _CompliancePanel(repo: repo, patient: patient),
                    _PatientAuditLog(repo: repo, patientId: widget.patientId),
                    // Signos a vigilar (solo lectura): qué observar, no tareas.
                    if (result.complicacion.isNotEmpty)
                      _WatchSignsCard(alerts: result.complicacion),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  'Apoyo a la decisión (borrador clínico). No sustituye el juicio '
                  'profesional ni modifica el plan de tratamiento.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: KuraColors.darkText.withValues(alpha: 0.6)),
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
        color: color.withValues(alpha: 0.12),
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


/// Tarjeta compacta de "Signos a vigilar" (solo lectura): mensajes de las
/// alertas de complicación (comorbilidades / infección IWII). NO son tareas de
/// la agenda; son qué observar. Las actividades concretas salen del
/// cuestionario "Evaluación preventiva".
class _WatchSignsCard extends StatelessWidget {
  final List<PreventionAlert> alerts;
  const _WatchSignsCard({required this.alerts});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: const [
                Icon(Icons.visibility_outlined, size: 18),
                SizedBox(width: 8),
                Text('Signos a vigilar',
                    style: TextStyle(fontWeight: FontWeight.w700)),
              ],
            ),
            const SizedBox(height: 8),
            ...alerts.map((a) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.circle,
                          size: 7, color: riskSeverityColor(a.severity)),
                      const SizedBox(width: 8),
                      Expanded(
                          child: Text(a.message,
                              style: const TextStyle(fontSize: 13))),
                    ],
                  ),
                )),
          ],
        ),
      ),
    );
  }
}

/// Cumplimiento preventivo del paciente en la ventana (turno/24 h): global +
/// por tipo de actividad. Solo se muestra si hay plan (actividades esperadas).
class _CompliancePanel extends StatelessWidget {
  final DataRepository repo;
  final Patient patient;
  const _CompliancePanel({required this.repo, required this.patient});

  @override
  Widget build(BuildContext context) {
    final c = repo.preventiveCompliance(patient.id,
        organizationId: patient.organizationId);
    if (!c.hasExpected) return const SizedBox.shrink();
    Color pctColor(int p) => p >= 85
        ? KuraColors.success
        : p >= 60
            ? KuraColors.warning
            : KuraColors.danger;
    final types = [...c.byType]..sort((a, b) => a.title.compareTo(b.title));
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text('Cumplimiento preventivo',
                      style: TextStyle(fontWeight: FontWeight.w700)),
                ),
                Text('${c.globalPct}%',
                    style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 18,
                        color: pctColor(c.globalPct))),
              ],
            ),
            Text('${c.doneTotal}/${c.expectedTotal} actividades realizadas (ventana actual)',
                style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 10),
            ...types.map((tt) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                              child: Text(tt.title,
                                  style: const TextStyle(fontSize: 13))),
                          Text('${tt.done}/${tt.expected} · ${tt.pct}%',
                              style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: pctColor(tt.pct))),
                        ],
                      ),
                      const SizedBox(height: 4),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: tt.expected == 0 ? 0 : tt.done / tt.expected,
                          minHeight: 5,
                          backgroundColor: KuraColors.chipBg,
                          color: pctColor(tt.pct),
                        ),
                      ),
                    ],
                  ),
                )),
          ],
        ),
      ),
    );
  }
}

/// Bitácora del paciente (auditoría): cronología colapsable de valoraciones,
/// actividades realizadas y eventos adversos — qué, cuándo y quién.
class _PatientAuditLog extends StatelessWidget {
  final DataRepository repo;
  final String patientId;
  const _PatientAuditLog({required this.repo, required this.patientId});

  @override
  Widget build(BuildContext context) {
    // Resolución de "quién" (staff o usuario) por id.
    final staffById = {for (final s in repo.listStaff()) s.id: s.fullName};
    final userById = {for (final u in repo.listUsers()) u.id: u.fullName};
    String who(String? id) =>
        id == null ? '' : (staffById[id] ?? userById[id] ?? '');

    final entries = <(DateTime, IconData, String, String, Color)>[];
    for (final r in repo.listRiskAssessments(patientId)) {
      entries.add((
        r.assessedAt,
        Icons.monitor_heart_outlined,
        'Valoración Braden${r.bradenScore != null ? ' ${r.bradenScore}' : ''}',
        who(r.assessedBy),
        KuraColors.primary,
      ));
    }
    // Tareas preventivas resueltas (hechas o saltadas): incluye manuales (sin
    // regla) y con regla, con quién y cuándo. Cubre lo que el log de acciones
    // por sí solo no captura (saltadas / tareas sin regla).
    for (final task in repo.listPreventiveTasks(patientId: patientId)) {
      if (task.status == PreventiveTaskStatus.done) {
        entries.add((
          task.doneAt ?? task.scheduledAt,
          Icons.check_circle_outline,
          task.actionLabel ?? task.title,
          who(task.doneBy),
          KuraColors.success,
        ));
      } else if (task.status == PreventiveTaskStatus.skipped) {
        entries.add((
          task.doneAt ?? task.scheduledAt,
          Icons.do_not_disturb_on_outlined,
          'Saltada: ${task.title}',
          who(task.doneBy),
          KuraColors.warning,
        ));
      }
    }
    for (final e in repo.listAdverseEventsForPatient(patientId)) {
      entries.add((e.occurredAt, Icons.warning_amber_rounded,
          'Evento adverso: ${e.type}', who(e.staffId), KuraColors.danger));
    }
    // Ingresos y egresos del paciente.
    for (final adm in repo.listAdmissions(patientId)) {
      entries.add((
        adm.admittedAt,
        Icons.login,
        'Ingreso${adm.locationLabel.isNotEmpty ? ' · ${adm.locationLabel}' : ''}',
        '',
        KuraColors.primary,
      ));
      if (adm.dischargedAt != null) {
        entries.add((adm.dischargedAt!, Icons.logout, 'Egreso', '',
            KuraColors.darkText));
      }
    }
    entries.sort((a, b) => b.$1.compareTo(a.$1));

    final fmt = DateFormat('dd/MM/yyyy HH:mm');
    return Card(
      margin: EdgeInsets.zero,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 16),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          leading: const Icon(Icons.history),
          title: const Text('Bitácora del paciente',
              style: TextStyle(fontWeight: FontWeight.w700)),
          subtitle: Text('${entries.length} registros'),
          children: entries.isEmpty
              ? [const Padding(padding: EdgeInsets.all(8), child: Text('Sin registros.'))]
              : entries
                  .map((e) => ListTile(
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        leading: Icon(e.$2, size: 18, color: e.$5),
                        title: Text(e.$3, style: const TextStyle(fontSize: 13)),
                        subtitle: Text(
                          '${fmt.format(e.$1)}${e.$4.isNotEmpty ? ' · ${e.$4}' : ''}',
                          style: const TextStyle(fontSize: 11),
                        ),
                      ))
                  .toList(),
        ),
      ),
    );
  }
}
