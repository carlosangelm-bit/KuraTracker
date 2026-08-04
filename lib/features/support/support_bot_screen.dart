import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/design/tokens.dart';
import '../../core/providers/session_provider.dart';

/// Chat con el asistente de SOPORTE de la plataforma (CustomGPT vía Edge
/// Function support-bot). Recibe el contexto NO SENSIBLE del usuario
/// ({rol, centro, ruta, pantalla}) capturado al abrir, y lo envía en cada
/// mensaje para que el agente detecte el perfil y el proceso y personalice.
class SupportBotScreen extends ConsumerStatefulWidget {
  /// Contexto capturado en la pantalla desde la que se abrió la ayuda. Sin PHI.
  final Map<String, String>? sessionContext;
  const SupportBotScreen({super.key, this.sessionContext});

  @override
  ConsumerState<SupportBotScreen> createState() => _SupportBotScreenState();
}

class _Msg {
  final bool user;
  final String text;

  /// Cuando es true, la "burbuja" no muestra texto sino una nota de contacto con
  /// un humano (handoff informativo en la conversación).
  final bool handoff;
  const _Msg(this.user, this.text, {this.handoff = false});
}

/// Marca que el agente puede emitir (según sus instrucciones en CustomGPT) para
/// ofrecer contacto con un humano. Se oculta del texto mostrado.
const _handoffMarker = '[[CONTACTAR_HUMANO]]';

class _SupportBotScreenState extends ConsumerState<SupportBotScreen> {
  final _msgs = <_Msg>[];
  final _ctrl = TextEditingController();
  final _scroll = ScrollController();
  String? _sessionId;
  bool _starting = true;
  bool _sending = false;
  String? _startError;

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
      final id = await repo.supportBotStart();
      if (!mounted) return;
      setState(() {
        _sessionId = id;
        _starting = false;
        _msgs.add(const _Msg(false,
            'Hola 👋 Soy el asistente de KuraTracker. Te ayudo a usar la plataforma paso a paso, según tu perfil y la pantalla en la que estás. ¿Con qué te ayudo?'));
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
      final reply = await repo.supportBotSend(_sessionId!, text,
          context: widget.sessionContext);
      if (!mounted) return;
      // El agente puede pedir el handoff con una marca; se oculta del texto.
      final markerHit =
          reply.toUpperCase().contains(_handoffMarker.toUpperCase());
      final clean = reply
          .replaceAll(
              RegExp(RegExp.escape(_handoffMarker), caseSensitive: false), '')
          .trim();
      setState(() {
        _msgs.add(_Msg(false, clean.isEmpty ? '(sin respuesta)' : clean));
        if (markerHit && !(_msgs.isNotEmpty && _msgs.last.handoff)) {
          _msgs.add(const _Msg(false, '', handoff: true));
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _msgs.add(_Msg(false,
          'No pude responder: ${'$e'.replaceFirst('Exception: ', '')}')));
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
      appBar: AppBar(title: const Text('Asistente de ayuda')),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            color: t.statusNeutral.withValues(alpha: 0.10),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(
              'Ayuda sobre el uso de la plataforma. No da consejo médico ni '
              'accede a datos de tus pacientes.',
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
                          final m = _msgs[i];
                          return m.handoff ? _handoffBubble(t) : _bubble(t, m);
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
                icon: const Icon(Icons.refresh),
                label: const Text('Reintentar'),
                onPressed: () {
                  setState(() {
                    _starting = true;
                    _startError = null;
                  });
                  _start();
                },
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
        constraints:
            BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Text(m.text, style: TextStyle(color: fg, fontSize: 14)),
      ),
    );
  }

  Widget _handoffBubble(BrandTokens t) => Align(
        alignment: Alignment.centerLeft,
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 6),
          padding: const EdgeInsets.all(12),
          constraints:
              BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
          decoration: BoxDecoration(
            color: t.statusNeutral.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.support_agent_outlined,
                  size: 18, color: t.textSecondary),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  '¿Necesitas ayuda de una persona? El administrador de tu centro '
                  'puede apoyarte con altas de usuarios, permisos y módulos; para '
                  'fallas técnicas, escribe al equipo de KuraTracker.',
                  style: TextStyle(fontSize: 13, color: t.textSecondary),
                ),
              ),
            ],
          ),
        ),
      );

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
                    hintText: 'Escribe tu duda sobre la plataforma…',
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
}
