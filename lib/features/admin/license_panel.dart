import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/kura_theme.dart';
import '../../models/app_user.dart';
import '../../models/license_summary.dart';
import '../../services/data_repository.dart';

/// Panel de licencias del administrador del centro (Fase 2). Muestra cuántas
/// licencias quedan (los 4 contadores) y, según el estado, el camino para crecer.
///
/// Compra: con backend de Stripe (prod/sandbox) los botones de crecer abren el
/// checkout de suscripción (license-checkout → redirige a Stripe, o actualiza la
/// suscripción existente con prorrateo). En la demo (LocalStore) no hay pila de
/// pagos, así que caen al formulario de "Solicitar" (license_requests). En ambos
/// casos NINGÚN botón escribe un derecho aquí: lo escribe el webhook/master. El
/// techo del autoservicio (>5 clínicos) sigue siendo solicitud asistida.
class LicensePanel extends StatefulWidget {
  final DataRepository repo;
  final String? organizationId;
  final AppUser? user;
  const LicensePanel({
    super.key,
    required this.repo,
    required this.organizationId,
    required this.user,
  });

  @override
  State<LicensePanel> createState() => _LicensePanelState();
}

class _LicensePanelState extends State<LicensePanel> {
  @override
  Widget build(BuildContext context) {
    if (widget.organizationId == null) {
      return const Center(child: Text('Selecciona un centro para ver sus licencias.'));
    }
    final s = widget.repo.licenseSummaryFor(widget.organizationId);
    final state = s.state;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (state == LicenseState.impago) _impagoBand(),
        if (state == LicenseState.gratuito)
          _freePlanCard(s)
        else ...[
          _counter(
            'Asientos clínicos',
            s.clinicalSeats,
            highlight: state == LicenseState.lleno,
            subtitle: 'Se cobran por persona con rol clínico.',
          ),
          _counter(
            'Cupos administrativos',
            s.adminSlots,
            subtitle: s.adminSlots.contracted == 0
                ? 'Incluidos con el módulo Administración (no contratado).'
                : 'Incluidos en Administración; del 4.º paga como clínico.',
          ),
          _caregiverCard(s.caregivers),
          _protocoloCard(s),
        ],
        const SizedBox(height: 12),
        _cta(state, s),
      ],
    );
  }

  // ---------------- Contadores ----------------

  Widget _counter(String title, LicenseCounter c,
      {bool highlight = false, String? subtitle}) {
    final color = highlight ? KuraColors.warning : KuraColors.darkText;
    final valueText = c.unlimited
        ? '${c.used} · sin tope'
        : '${c.used} de ${c.contracted} en uso'
            '${c.available > 0 ? ' · ${c.available} disponible${c.available == 1 ? '' : 's'}' : ''}';
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        leading: Icon(Icons.badge_outlined, color: color),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(valueText,
                style: TextStyle(
                    color: color, fontWeight: FontWeight.w700, fontSize: 13)),
            if (subtitle != null)
              Text(subtitle,
                  style: const TextStyle(fontSize: 11, color: KuraColors.darkText)),
          ],
        ),
        trailing: highlight
            ? const Icon(Icons.error_outline, color: KuraColors.warning)
            : null,
      ),
    );
  }

  Widget _caregiverCard(int n) => Card(
        margin: const EdgeInsets.only(bottom: 10),
        child: ListTile(
          leading: const Icon(Icons.volunteer_activism_outlined),
          title: const Text('Cuidadores',
              style: TextStyle(fontWeight: FontWeight.w700)),
          subtitle: Text('$n · no consumen licencia',
              style: const TextStyle(fontSize: 13, color: KuraColors.success)),
        ),
      );

  Widget _protocoloCard(LicenseSummary s) {
    final c = s.protocolo;
    final text = s.hasProtocoloAddon
        ? '${c.used} de ${c.contracted} asignadas'
        : 'Add-on no contratado';
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        leading: const Icon(Icons.workspace_premium_outlined),
        title: const Text('Protocolo Kura+',
            style: TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(
            '$text · se compran por centro y se asignan por persona (en Usuarios).',
            style: const TextStyle(fontSize: 13)),
        trailing: s.hasProtocoloAddon
            ? TextButton(
                onPressed: () => _openRequest(
                    kind: 'protocolo', title: 'Solicitar más licencias de Kura+'),
                child: const Text('Solicitar'))
            : null,
      ),
    );
  }

  // ---------------- Estados/CTA ----------------

  Widget _impagoBand() => Card(
        color: KuraColors.danger.withValues(alpha: 0.10),
        margin: const EdgeInsets.only(bottom: 12),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              const Icon(Icons.warning_amber_rounded, color: KuraColors.danger),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Pago vencido. El expediente sigue accesible; el alta de nuevos '
                  'usuarios se cierra hasta regularizar. Actualiza el método de pago.',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              FilledButton(
                onPressed: () => _openRequest(
                    kind: 'otro',
                    title: 'Actualizar método de pago',
                    presetNote: 'Actualizar método de pago / regularizar.'),
                child: const Text('Actualizar tarjeta'),
              ),
            ],
          ),
        ),
      );

  Widget _freePlanCard(LicenseSummary s) {
    // SIN contador de pacientes: el tope del plan gratuito es un trigger en el
    // servidor que aún no existe (fase 2). Publicar "N de 5" como constante del
    // cliente contradice el principio de la rama —el servidor impone el derecho,
    // no la UI— y repetiría el defecto de la auditoría del 1-sep (prometer en la
    // UI algo que el producto no respalda). Vuelve el contador cuando el trigger
    // exista, respaldado por el servidor.
    return const Card(
      margin: EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Plan gratuito',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
            SizedBox(height: 6),
            Text('Suscríbete para crecer: más pacientes, asientos y módulos.',
                style: TextStyle(fontSize: 12)),
          ],
        ),
      ),
    );
  }

  Widget _cta(LicenseState state, LicenseSummary s) {
    switch (state) {
      case LicenseState.impago:
        return const SizedBox.shrink(); // la banda ya trae su acción
      case LicenseState.gratuito:
        return FilledButton.icon(
          onPressed: _grow(
              kind: 'otro',
              title: 'Suscribirse',
              presetNote: 'Quiero suscribirme (salir del plan gratuito).'),
          icon: const Icon(Icons.rocket_launch_outlined),
          label: const Text('Suscribirse'),
        );
      case LicenseState.techoAutoservicio:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Llegaste al máximo del autoservicio. Para más licencias, cuéntanos '
              'cuántas necesitas y te contactamos.',
              style: TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: () => _openRequest(
                  kind: 'seat_clinico', title: 'Solicitar más licencias'),
              icon: const Icon(Icons.support_agent_outlined),
              label: const Text('Solicitar más licencias'),
            ),
          ],
        );
      case LicenseState.lleno:
        return FilledButton.icon(
          onPressed: _grow(kind: 'seat_clinico', title: 'Agregar licencias'),
          icon: const Icon(Icons.add),
          label: Text(_buyLabel('Agregar licencias')),
        );
      case LicenseState.holgado:
        return OutlinedButton.icon(
          onPressed: _grow(kind: 'seat_clinico', title: 'Agregar licencias'),
          icon: const Icon(Icons.add),
          label: Text(_buyLabel('Agregar licencias')),
        );
    }
  }

  /// Con backend de pagos, crecer = comprar; en demo, crecer = solicitar.
  VoidCallback _grow({required String kind, required String title, String? presetNote}) =>
      widget.repo.supportsLicenseCheckout
          ? _openPurchase
          : () => _openRequest(kind: kind, title: title, presetNote: presetNote);

  String _buyLabel(String requestLabel) =>
      widget.repo.supportsLicenseCheckout ? 'Comprar licencias' : requestLabel;

  // ---------------- Compra (checkout de suscripción) ----------------

  Future<void> _openPurchase() async {
    var interval = 'month';
    final clinicoCtrl = TextEditingController();
    final protocoloCtrl = TextEditingController();
    var admin = false, insumos = false, comercial = false;

    final cart = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Contratar licencias'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'month', label: Text('Mensual')),
                    ButtonSegment(value: 'year', label: Text('Anual')),
                  ],
                  selected: {interval},
                  onSelectionChanged: (s) => setLocal(() => interval = s.first),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: clinicoCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                      labelText: 'Asientos clínicos', hintText: '0'),
                ),
                TextField(
                  controller: protocoloCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                      labelText: 'Asientos Protocolo Kura+', hintText: '0'),
                ),
                const SizedBox(height: 4),
                CheckboxListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  value: admin,
                  onChanged: (v) => setLocal(() => admin = v ?? false),
                  title: const Text('Módulo Administración'),
                ),
                CheckboxListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  value: insumos,
                  onChanged: (v) => setLocal(() => insumos = v ?? false),
                  title: const Text('Módulo Insumos'),
                ),
                CheckboxListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  value: comercial,
                  onChanged: (v) => setLocal(() => comercial = v ?? false),
                  title: const Text('Módulo Comercial'),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Te lleva al pago de Stripe. Si ya tienes suscripción, ajusta la '
                  'existente y el prorrateo aparece en tu próxima factura.',
                  style: TextStyle(fontSize: 11, color: KuraColors.darkText),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancelar')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Continuar')),
          ],
        ),
      ),
    );
    if (cart != true || !mounted) return;

    final seats = <String, int>{};
    final cl = int.tryParse(clinicoCtrl.text.trim()) ?? 0;
    final pr = int.tryParse(protocoloCtrl.text.trim()) ?? 0;
    if (cl > 0) seats['clinico'] = cl;
    if (pr > 0) seats['protocolo'] = pr;
    final modules = <String>[
      if (admin) 'admin',
      if (insumos) 'insumos',
      if (comercial) 'comercial',
    ];
    if (seats.isEmpty && modules.isEmpty) {
      _snack('Elige al menos un asiento o módulo.');
      return;
    }

    final res = await widget.repo
        .startLicenseCheckout(interval: interval, seats: seats, modules: modules);
    if (!mounted) return;

    final url = res['url'] as String?;
    if (url != null) {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      return;
    }
    if (res['updated'] == true) {
      _snack('Suscripción actualizada. El prorrateo aparece en tu próxima factura.');
      setState(() {});
      return;
    }
    final err = res['error'] as String? ?? 'No se pudo iniciar la compra.';
    if (res['status'] == 409) {
      // Techo del autoservicio: la función ya dejó la solicitud.
      setState(() {});
    }
    _snack(err);
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  // ---------------- Formulario de solicitud ----------------

  Future<void> _openRequest({
    required String kind,
    required String title,
    String? presetNote,
  }) async {
    final qtyCtrl = TextEditingController();
    final noteCtrl = TextEditingController(text: presetNote ?? '');
    final wantsQty = kind == 'seat_clinico' || kind == 'protocolo';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (wantsQty)
              TextField(
                controller: qtyCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                    labelText: '¿Cuántas más?', hintText: 'p. ej. 3'),
              ),
            TextField(
              controller: noteCtrl,
              maxLines: 2,
              decoration: const InputDecoration(labelText: 'Nota (opcional)'),
            ),
            const SizedBox(height: 8),
            const Text(
              'Se envía a la plataforma. No es un cobro: te contactamos para '
              'confirmarlo.',
              style: TextStyle(fontSize: 11, color: KuraColors.darkText),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Enviar')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final user = widget.user;
    if (user == null || widget.organizationId == null) return;
    await widget.repo.requestLicenses(
      organizationId: widget.organizationId!,
      kind: kind,
      requestedQuantity: int.tryParse(qtyCtrl.text.trim()),
      note: noteCtrl.text.trim().isEmpty ? null : noteCtrl.text.trim(),
      by: user,
    );
    if (!mounted) return;
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Solicitud enviada. Te contactamos pronto.')),
    );
  }
}
