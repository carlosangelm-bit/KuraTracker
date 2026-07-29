import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/design/tokens.dart';
import '../../core/providers/session_provider.dart';
import '../../models/app_user.dart';
import '../../models/vac_therapy.dart';
import '../../services/data_repository.dart';

/// Chat con el asistente VAC (CustomGPT vía Edge Function vac-bot). En el mismo
/// hilo, un botón permite salir del bot y contactar a la GUARDIA por WhatsApp.
class VacBotScreen extends ConsumerStatefulWidget {
  final String therapyId;
  const VacBotScreen({super.key, required this.therapyId});
  @override
  ConsumerState<VacBotScreen> createState() => _VacBotScreenState();
}

class _Msg {
  final bool user;
  final String text;
  const _Msg(this.user, this.text);
}

class _VacBotScreenState extends ConsumerState<VacBotScreen> {
  final _msgs = <_Msg>[];
  final _ctrl = TextEditingController();
  final _scroll = ScrollController();
  String? _sessionId;
  bool _starting = true;
  bool _sending = false;
  String? _startError;

  String? get _uid => ref.read(sessionProvider).user?.id;
  bool get _isAdmin => ref.read(sessionProvider).user?.role == AppRole.admin;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    final repo = ref.read(dataRepositoryProvider).valueOrNull;
    if (repo == null) {
      setState(() {
        _starting = false;
        _startError = 'No se pudo cargar el asistente.';
      });
      return;
    }
    try {
      final id = await repo.vacBotStart();
      if (!mounted) return;
      setState(() {
        _sessionId = id;
        _starting = false;
        _msgs.add(const _Msg(false,
            'Hola, soy el asistente de equipos VAC. Cuéntame qué alarma o duda tienes y te guío. Si hace falta, puedes contactar a la guardia con el botón de arriba.'));
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _starting = false;
        _startError = '$e'.replaceFirst('Exception: ', '');
      });
    }
  }

  Future<void> _send() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty || _sessionId == null || _sending) return;
    final repo = ref.read(dataRepositoryProvider).valueOrNull;
    if (repo == null) return;
    setState(() {
      _msgs.add(_Msg(true, text));
      _sending = true;
      _ctrl.clear();
    });
    _scrollDown();
    try {
      final reply = await repo.vacBotSend(_sessionId!, text);
      if (!mounted) return;
      setState(() => _msgs.add(_Msg(
          false, reply.trim().isEmpty ? '(sin respuesta)' : reply.trim())));
    } catch (e) {
      if (!mounted) return;
      setState(() => _msgs.add(_Msg(
          false, 'No pude responder: ${'$e'.replaceFirst('Exception: ', '')}')));
    } finally {
      if (mounted) setState(() => _sending = false);
      _scrollDown();
    }
  }

  void _scrollDown() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(_scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = BrandTokens.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Asesoría VAC'),
        actions: [
          TextButton.icon(
            style: TextButton.styleFrom(foregroundColor: const Color(0xFF25D366)),
            icon: const Icon(Icons.chat),
            label: const Text('Guardia'),
            onPressed: _contactHuman,
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            color: t.statusWarning.withValues(alpha: 0.10),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(
              'Orientativo, no sustituye el juicio clínico. Ante una alarma crítica, reinstala la terapia y contacta a la guardia.',
              style: TextStyle(fontSize: 12, color: t.textSecondary),
            ),
          ),
          Expanded(
            child: _starting
                ? const Center(child: CircularProgressIndicator())
                : _startError != null
                    ? _errorView(t)
                    : ListView.builder(
                        controller: _scroll,
                        padding: const EdgeInsets.all(16),
                        itemCount: _msgs.length + (_sending ? 1 : 0),
                        itemBuilder: (_, i) {
                          if (i >= _msgs.length) return _typing(t);
                          return _bubble(t, _msgs[i]);
                        },
                      ),
          ),
          if (!_starting && _startError == null) _inputBar(t),
        ],
      ),
    );
  }

  Widget _errorView(BrandTokens t) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.cloud_off_outlined, color: t.textSecondary),
              const SizedBox(height: 8),
              Text(_startError!, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                icon: const Icon(Icons.chat),
                label: const Text('Contactar guardia (WhatsApp)'),
                onPressed: _contactHuman,
              ),
            ],
          ),
        ),
      );

  Widget _bubble(BrandTokens t, _Msg m) {
    final align = m.user ? Alignment.centerRight : Alignment.centerLeft;
    final color =
        m.user ? t.brandPrimary : t.statusNeutral.withValues(alpha: 0.15);
    final fg = m.user ? Colors.white : t.textPrimary;
    return Align(
      alignment: align,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.78),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Text(m.text, style: TextStyle(color: fg, fontSize: 14)),
      ),
    );
  }

  Widget _typing(BrandTokens t) => Align(
        alignment: Alignment.centerLeft,
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 4),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
              color: t.statusNeutral.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(14)),
          child: const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2)),
        ),
      );

  Widget _inputBar(BrandTokens t) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _ctrl,
                  minLines: 1,
                  maxLines: 4,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _send(),
                  decoration: const InputDecoration(
                    isDense: true,
                    hintText: 'Escribe tu duda o la alarma…',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                onPressed: _sending ? null : _send,
                icon: const Icon(Icons.send),
              ),
            ],
          ),
        ),
      );

  Future<void> _contactHuman() async {
    final repo = ref.read(dataRepositoryProvider).valueOrNull;
    if (repo == null) return;
    final therapy = repo.getVacTherapy(widget.therapyId);
    if (therapy == null) return;
    var phone = repo.vacOncallPhone(therapy.organizationId);
    if (phone == null) {
      if (!_isAdmin) {
        _snack(
            'No hay número de guardia configurado. Pídele al administrador que lo capture.');
        return;
      }
      phone = await _configurePhone(repo, therapy.organizationId);
      if (phone == null) return;
    }
    final patient = repo.getPatient(therapy.patientId);
    final lastUser =
        _msgs.lastWhere((m) => m.user, orElse: () => const _Msg(true, ''));
    final msg = StringBuffer()
      ..writeln('Guardia VAC — solicitud de contacto')
      ..writeln('Paciente: ${patient?.fullName ?? therapy.patientId}')
      ..writeln('Equipo: ${therapy.equipment.label}')
      ..writeln('Parámetros: ${therapy.settingsLabel}')
      ..writeln('Ubicación: ${therapy.currentLocation?.label ?? '—'}');
    if (lastUser.text.isNotEmpty) msg.writeln('Consulta: ${lastUser.text}');
    final digits = phone.replaceAll(RegExp(r'[^0-9]'), '');
    final uri = Uri.parse(
        'https://wa.me/$digits?text=${Uri.encodeComponent(msg.toString())}');
    await repo.addVacEvent(
      organizationId: therapy.organizationId,
      therapyId: therapy.id,
      patientId: therapy.patientId,
      type: VacEventType.nota,
      byProfile: _uid,
      note: 'Contacto a guardia desde asesoría (bot).',
    );
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<String?> _configurePhone(DataRepository repo, String orgId) async {
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (dctx) => AlertDialog(
        title: const Text('Número de guardia VAC'),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.phone,
          autofocus: true,
          decoration: const InputDecoration(
              labelText: 'WhatsApp con lada', hintText: 'p. ej. 52 55 1234 5678'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dctx, false),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(dctx, true),
              child: const Text('Guardar')),
        ],
      ),
    );
    if (ok != true) return null;
    final phone = ctrl.text.trim();
    if (phone.isEmpty) return null;
    await repo.setVacOncallPhone(
        organizationId: orgId, phone: phone, updatedBy: _uid);
    return phone;
  }

  void _snack(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
}
