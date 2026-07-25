import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

import '../../core/theme/kura_theme.dart';
import '../../core/providers/session_provider.dart';
import '../../engine/kura_protocol_engine.dart';
import '../../engine/models/kura_engine_output.dart';
import '../../engine/models/kura_engine_enums.dart';
import '../../models/treatment_plan.dart';
import '../../services/data_repository.dart';
import '../wound_capture/wound_capture_controller.dart';
import 'treatment_catalog.dart';

/// Paso 3 rediseñado: abordaje de la herida.
///
/// Si el usuario tiene premium activo y activa "Utilizar protocolo Kura+",
/// el motor pre-llena metodos/productos (editable) a partir del pronostico
/// ya calculado en vivo durante la captura (paso previo). Cada componente
/// registra su origen (manual/kura_suggested/kura_edited) y la decision
/// final del clinico se persiste para trazabilidad (seccion 8/9).
class TreatmentStepScreen extends ConsumerStatefulWidget {
  final String patientId;
  final String woundId;
  final String consultationId;
  final String draftKey;

  const TreatmentStepScreen({
    super.key,
    required this.patientId,
    required this.woundId,
    required this.consultationId,
    required this.draftKey,
  });

  @override
  ConsumerState<TreatmentStepScreen> createState() => _TreatmentStepScreenState();
}

class _ComponentRow {
  String method;
  String product;
  ComponentOrigin origin;
  _ComponentRow(this.method, this.product, this.origin);
}

class _TreatmentStepScreenState extends ConsumerState<TreatmentStepScreen> {
  bool _useKuraProtocol = false;
  bool _initializedFromEngine = false;
  final List<_ComponentRow> _components = [];
  final _descriptionCtrl = TextEditingController();
  KuraEngineOutput? _appliedOutput;
  bool _saving = false;

  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _isListening = false;
  bool _speechAvailable = false;

  @override
  void initState() {
    super.initState();
    _initSpeech();
  }

  Future<void> _initSpeech() async {
    try {
      _speechAvailable = await _speech.initialize();
    } catch (_) {
      _speechAvailable = false;
    }
    if (mounted) setState(() {});
  }

  Future<void> _toggleListening() async {
    if (!_speechAvailable) return;
    if (_isListening) {
      await _speech.stop();
      setState(() => _isListening = false);
      return;
    }
    setState(() => _isListening = true);
    await _speech.listen(
      localeId: 'es_MX',
      onResult: (result) {
        setState(() {
          _descriptionCtrl.text =
              _descriptionCtrl.text.isEmpty ? result.recognizedWords : '${_descriptionCtrl.text} ${result.recognizedWords}';
        });
      },
    );
  }

  void _applyKuraSuggestion(KuraEngineOutput output) {
    setState(() {
      _appliedOutput = output;
      _components.clear();
      for (final r in output.regimen) {
        _components.add(_ComponentRow(r.metodo, r.producto, ComponentOrigin.kuraSuggested));
      }
      if (_descriptionCtrl.text.isEmpty) {
        _descriptionCtrl.text = _buildAutoDescription(output);
      }
    });
  }

  String _buildAutoDescription(KuraEngineOutput output) {
    final buffer = StringBuffer();
    buffer.writeln(
      'Plan sugerido por Protocolo Kura+ (escenario ${output.dominantScenario.code} · '
      '${output.dominantScenario.title}):',
    );
    for (final r in output.regimen) {
      buffer.writeln('- ${r.metodo}: ${r.producto}');
    }
    return buffer.toString();
  }

  void _markEdited(int index) {
    final row = _components[index];
    if (row.origin == ComponentOrigin.kuraSuggested) {
      setState(() => row.origin = ComponentOrigin.kuraEdited);
    }
  }

  void _addManualComponent() {
    setState(() {
      _components.add(_ComponentRow(
        TreatmentCatalog.methods.first,
        TreatmentCatalog.methodToProducts[TreatmentCatalog.methods.first]!.first,
        ComponentOrigin.manual,
      ));
    });
  }

  /// Lista de metodos para el dropdown: el catalogo base + el metodo actual
  /// de la fila si el motor Kura+ sugirio uno que no esta en el catalogo
  /// (para que nunca quede en blanco, ver comentario en TreatmentCatalog).
  List<String> _methodItems(String currentMethod) {
    final base = TreatmentCatalog.methods;
    if (base.contains(currentMethod)) return base;
    return [currentMethod, ...base];
  }

  /// Lista de productos para el dropdown de un metodo dado: los productos
  /// base de ese metodo en el catalogo + el producto actual de la fila si
  /// no esta incluido (idem _methodItems).
  List<String> _productItems(String currentMethod, String currentProduct) {
    final base = TreatmentCatalog.methodToProducts[currentMethod] ?? const [];
    if (base.contains(currentProduct)) return base;
    return [currentProduct, ...base];
  }

  @override
  Widget build(BuildContext context) {
    final controller = ref.read(
      woundCaptureControllerProvider(widget.draftKey).notifier,
    );
    // Kura+ habilitado por usuario (premium_enabled) O por el add-on del centro.
    final isPremium = ref.watch(kuraProtocolEnabledProvider);

    if (!_initializedFromEngine) {
      _initializedFromEngine = true;
      if (controller.liveOutput != null) {
        // No auto-aplicar; se espera que el clinico active el switch.
      }
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Abordaje de la herida')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (isPremium)
                  Card(
                    color: KuraColors.primary.withOpacity(0.06),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          const Icon(Icons.auto_awesome, color: KuraColors.primary),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('Utilizar protocolo Kura+',
                                    style: TextStyle(fontWeight: FontWeight.w800)),
                                Text(
                                  'La plataforma sugiere el régimen; podrás editarlo libremente.',
                                  style: TextStyle(
                                      fontSize: 12, color: KuraColors.darkText.withOpacity(0.6)),
                                ),
                              ],
                            ),
                          ),
                          Switch(
                            value: _useKuraProtocol,
                            activeColor: KuraColors.primary,
                            onChanged: (v) {
                              setState(() => _useKuraProtocol = v);
                              if (v && controller.liveOutput != null) {
                                _applyKuraSuggestion(controller.liveOutput!);
                              }
                            },
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  Card(
                    color: KuraColors.chipBg,
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Row(
                        children: [
                          Icon(Icons.lock_outline, color: KuraColors.darkText.withOpacity(0.5)),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'El Protocolo Kura+ es una función premium. Contacta al administrador '
                              'para activarla en tu cuenta.',
                              style: TextStyle(
                                  fontSize: 12, color: KuraColors.darkText.withOpacity(0.6)),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                if (_useKuraProtocol && _appliedOutput != null) ...[
                  const SizedBox(height: 12),
                  _KuraSummaryCard(output: _appliedOutput!),
                ],
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Componentes del régimen',
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700)),
                    TextButton.icon(
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('Añadir método'),
                      onPressed: _addManualComponent,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                if (_components.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Text('Sin componentes aún. Añade uno o activa el Protocolo Kura+.'),
                  )
                else
                  ..._components.asMap().entries.map((entry) {
                    final i = entry.key;
                    final row = entry.value;
                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          children: [
                            _OriginBadge(origin: row.origin),
                            const SizedBox(width: 10),
                            Expanded(
                              child: DropdownButtonFormField<String>(
                                // Tolerante: si el metodo sugerido por el motor
                                // Kura+ no esta en el catalogo base (p. ej. se
                                // agrego uno nuevo al motor y aun no se
                                // reflejo aqui), se inyecta como opcion extra
                                // en vez de dejar el campo en blanco (bug #6).
                                value: row.method,
                                decoration: const InputDecoration(labelText: 'Método'),
                                items: _methodItems(row.method)
                                    .map((m) => DropdownMenuItem(value: m, child: Text(m)))
                                    .toList(),
                                onChanged: (v) {
                                  if (v == null) return;
                                  setState(() {
                                    row.method = v;
                                    final products = TreatmentCatalog.methodToProducts[v];
                                    row.product = (products != null && products.isNotEmpty)
                                        ? products.first
                                        : row.product;
                                  });
                                  _markEdited(i);
                                },
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: DropdownButtonFormField<String>(
                                // Misma tolerancia que el dropdown de Metodo:
                                // el producto sugerido siempre se muestra,
                                // aunque no pertenezca a la lista base de ese
                                // metodo en el catalogo.
                                value: row.product,
                                decoration: const InputDecoration(labelText: 'Producto'),
                                items: _productItems(row.method, row.product)
                                    .map((p) => DropdownMenuItem(value: p, child: Text(p)))
                                    .toList(),
                                onChanged: (v) {
                                  if (v == null) return;
                                  setState(() => row.product = v);
                                  _markEdited(i);
                                },
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline, color: KuraColors.danger),
                              onPressed: () => setState(() => _components.removeAt(i)),
                            ),
                          ],
                        ),
                      ),
                    );
                  }),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Descripción final del tratamiento',
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700)),
                    IconButton(
                      icon: Icon(
                        _isListening ? Icons.mic : Icons.mic_none,
                        color: _isListening ? KuraColors.danger : KuraColors.primary,
                      ),
                      tooltip: _speechAvailable
                          ? 'Dictado por voz'
                          : 'Dictado por voz no disponible en este dispositivo',
                      onPressed: _speechAvailable ? _toggleListening : null,
                    ),
                  ],
                ),
                TextField(
                  controller: _descriptionCtrl,
                  maxLines: 6,
                  decoration: const InputDecoration(
                    hintText: 'Describe el tratamiento realizado, indicaciones y plan de seguimiento...',
                  ),
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  icon: _saving
                      ? const SizedBox(
                          height: 16,
                          width: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.check_circle_outline),
                  label: Text(_saving ? 'Guardando...' : 'Guardar consulta'),
                  style: FilledButton.styleFrom(
                    backgroundColor: KuraColors.primary,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  onPressed: _saving ? null : () => _save(context, controller),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _save(BuildContext context, WoundCaptureController controller) async {
    setState(() => _saving = true);
    final repo = await DataRepository.instance();

    final componentsRecords = _components
        .map((c) => TreatmentComponentRecord(
              id: '',
              treatmentPlanId: '',
              method: c.method,
              product: c.product,
              origin: c.origin,
            ))
        .toList();

    try {
      final plan = await repo.saveTreatmentPlan(
        consultationId: widget.consultationId,
        woundId: widget.woundId,
        usedKuraProtocol: _useKuraProtocol,
        finalDescription: _descriptionCtrl.text,
        components: componentsRecords,
      );

      if (_useKuraProtocol && _appliedOutput != null) {
        final hasEdits = _components.any((c) => c.origin == ComponentOrigin.kuraEdited) ||
            _components.length != _appliedOutput!.regimen.length;
        await repo.saveKuraRecommendation(
          consultationId: widget.consultationId,
          woundId: widget.woundId,
          treatmentPlanId: plan.id,
          output: _appliedOutput!,
          decision: hasEdits ? ClinicianDecision.editada : ClinicianDecision.aceptada,
        );
      }

      await repo.updateConsultationDraftStatus(widget.consultationId, false);
      // La bitacora de auditoria de treatment_plans la genera el trigger
      // AFTER UPDATE de Postgres (audit_trigger_fn), no una llamada manual
      // desde el cliente: asi se garantiza que nadie pueda falsificarla (no
      // hay politica de INSERT en audit_log).
    } catch (e, st) {
      debugPrint('Error al guardar plan de tratamiento: $e\n$st');
      if (context.mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo guardar la consulta: $e')),
        );
      }
      return;
    }

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Consulta guardada correctamente.')),
      );
      // TreatmentStepScreen se abre con Navigator.push (imperativo) sobre la
      // ruta de captura de herida (GoRouter). Se hace pop del push imperativo
      // y luego se navega explicitamente a la pagina del paciente: usar solo
      // popUntil(isFirst) podia dejar al usuario en la pantalla de captura
      // de la herida en vez de en la ficha del paciente.
      Navigator.of(context).pop();
      if (context.mounted) {
        context.go('/patients/${widget.patientId}');
      }
    }
  }
}

class _KuraSummaryCard extends StatelessWidget {
  final KuraEngineOutput output;
  const _KuraSummaryCard({required this.output});

  @override
  Widget build(BuildContext context) {
    return Card(
      color: KuraColors.chipBg,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Escenario ${output.dominantScenario.code} · ${output.dominantScenario.commercialPhenotype}',
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            Text(
              'Modelo: ${output.modelVersion} · Reglas: ${output.rulesVersion}',
              style: TextStyle(fontSize: 11, color: KuraColors.darkText.withOpacity(0.5)),
            ),
            if (output.interconsultas.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                children: output.interconsultas
                    .map((i) => Chip(
                          label: Text(i.especialidad, style: const TextStyle(fontSize: 11)),
                          backgroundColor:
                              (i.esUrgente ? KuraColors.danger : KuraColors.infoBlue)
                                  .withOpacity(0.1),
                        ))
                    .toList(),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _OriginBadge extends StatelessWidget {
  final ComponentOrigin origin;
  const _OriginBadge({required this.origin});

  @override
  Widget build(BuildContext context) {
    IconData icon;
    Color color;
    String tooltip;
    switch (origin) {
      case ComponentOrigin.kuraSuggested:
        icon = Icons.auto_awesome;
        color = KuraColors.primary;
        tooltip = 'Sugerido por Kura+';
        break;
      case ComponentOrigin.kuraEdited:
        icon = Icons.edit;
        color = KuraColors.warning;
        tooltip = 'Sugerido y editado';
        break;
      case ComponentOrigin.manual:
        icon = Icons.person_outline;
        color = KuraColors.darkText;
        tooltip = 'Manual';
        break;
    }
    return Tooltip(
      message: tooltip,
      child: CircleAvatar(
        radius: 14,
        backgroundColor: color.withOpacity(0.15),
        child: Icon(icon, size: 14, color: color),
      ),
    );
  }
}
