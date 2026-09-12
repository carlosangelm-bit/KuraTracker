import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/design/tokens.dart';
import '../../core/layout/responsive.dart';
import '../../models/app_user.dart';
import '../../models/license_summary.dart';
import '../../services/data_repository.dart';

/// Techo del autoservicio: hasta aquí el admin arma y compra solo; por encima,
/// cotización asistida. Espejo de kSelfServiceSeatCeiling (license_summary).
const int _seatCeiling = kSelfServiceSeatCeiling;

/// Formatea centavos MXN a pesos ("$1,200" / "$1,234.50"). Los montos del catálogo
/// son pesos enteros, así que casi siempre sale sin decimales.
String pesosFromCents(int cents) {
  final whole = cents ~/ 100;
  final frac = cents % 100;
  final s = whole
      .toString()
      .replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (m) => ',');
  return frac == 0 ? '\$$s' : '\$$s.${frac.toString().padLeft(2, '0')}';
}

/// Un precio ausente (null) se pinta "—", nunca "$0": un ausente no debe parecerse
/// a un cero.
String moneyOrDash(int? cents) => cents == null ? '—' : pesosFromCents(cents);

/// "Arma tu plan" — el configurador (uno de los cuatro estados del canvas). Steppers
/// de asientos clínicos y Protocolo Kura+ (Kura+ nunca > asientos), interruptores de
/// los tres módulos (Administración YA NO es obligatoria), conmutador mensual/anual
/// (anual = 10 meses) y resumen vivo con el delta contra el plan actual. El pago abre
/// el NAVEGADOR (no embebe Stripe: un checkout embebido de bienes digitales cae bajo
/// la regla del 30% de Apple, y el repo ya tiene ios/ y android/).
class LicensePlanBuilderScreen extends StatefulWidget {
  final DataRepository repo;
  final String organizationId;
  final AppUser? user;

  /// Valores iniciales del configurador (el plan actual, o el sugerido desde el uso
  /// real cuando se llega desde "prueba vencida").
  final int initialClinico;
  final int initialProtocolo;
  final bool initialAdmin;
  final bool initialInsumos;
  final bool initialComercial;

  const LicensePlanBuilderScreen({
    super.key,
    required this.repo,
    required this.organizationId,
    required this.user,
    required this.initialClinico,
    required this.initialProtocolo,
    required this.initialAdmin,
    required this.initialInsumos,
    required this.initialComercial,
  });

  @override
  State<LicensePlanBuilderScreen> createState() =>
      _LicensePlanBuilderScreenState();
}

class _LicensePlanBuilderScreenState extends State<LicensePlanBuilderScreen> {
  late int _clinico = widget.initialClinico;
  late int _protocolo = widget.initialProtocolo;
  late bool _admin = widget.initialAdmin;
  late bool _insumos = widget.initialInsumos;
  late bool _comercial = widget.initialComercial;
  String _interval = 'month';
  bool _busy = false;

  int? _unit(String kind, String key) =>
      widget.repo.unitAmountCents(kind, key, _interval);
  int? _unitMonthly(String kind, String key) =>
      widget.repo.unitAmountCents(kind, key, 'month');

  bool get _overCeiling => _clinico > _seatCeiling;

  /// Suma de una selección a un precio dado, con completitud POR FILA: si a un
  /// concepto activo le falta el precio, el total queda `complete=false` y no se
  /// suma como 0 (un ausente no es un cero).
  ({int cents, bool complete}) _sum(int? Function(String, String) price,
      {required int clinico,
      required int protocolo,
      required bool admin,
      required bool insumos,
      required bool comercial}) {
    var total = 0;
    var complete = true;
    void add(int? unit, int qty) {
      if (qty == 0) return;
      if (unit == null) {
        complete = false;
      } else {
        total += unit * qty;
      }
    }

    add(price('seat', 'clinico'), clinico);
    add(price('seat', 'protocolo'), protocolo);
    if (admin) add(price('module', 'admin'), 1);
    if (insumos) add(price('module', 'insumos'), 1);
    if (comercial) add(price('module', 'comercial'), 1);
    return (cents: total, complete: complete);
  }

  ({int cents, bool complete}) get _selectedTotal => _sum(_unit,
      clinico: _clinico,
      protocolo: _protocolo,
      admin: _admin,
      insumos: _insumos,
      comercial: _comercial);

  /// Costo MENSUAL de la selección (base fija para el delta, sin importar el toggle).
  ({int cents, bool complete}) get _selectedMonthly => _sum(_unitMonthly,
      clinico: _clinico,
      protocolo: _protocolo,
      admin: _admin,
      insumos: _insumos,
      comercial: _comercial);

  /// Costo MENSUAL del plan actual del centro (para el delta).
  ({int cents, bool complete}) get _currentMonthly {
    final s = widget.repo.licenseSummaryFor(widget.organizationId);
    final protoContracted =
        s.protocolo.contracted < 0 ? 0 : s.protocolo.contracted;
    return _sum(_unitMonthly,
        clinico: s.clinicalSeats.contracted,
        protocolo: protoContracted,
        admin: widget.repo.premiumAdminFor(widget.organizationId),
        insumos: widget.repo.premiumInsumosFor(widget.organizationId),
        comercial: widget.repo.premiumComercialFor(widget.organizationId));
  }

  void _setClinico(int v) => setState(() {
        _clinico = v.clamp(0, 99);
        if (_protocolo > _clinico) _protocolo = _clinico; // Kura+ ≤ asientos.
      });

  Future<void> _continue() async {
    if (_overCeiling) return; // el CTA ya es "cotización asistida"
    setState(() => _busy = true);
    try {
      final seats = <String, int>{
        if (_clinico > 0) 'clinico': _clinico,
        if (_protocolo > 0) 'protocolo': _protocolo,
      };
      final modules = <String>[
        if (_admin) 'admin',
        if (_insumos) 'insumos',
        if (_comercial) 'comercial',
      ];
      if (seats.isEmpty && modules.isEmpty) {
        _snack('Elige al menos un asiento o módulo.');
        return;
      }
      if (widget.repo.supportsLicenseCheckout) {
        final res = await widget.repo.startLicenseCheckout(
            interval: _interval, seats: seats, modules: modules);
        if (!mounted) return;
        final url = res['url'] as String?;
        if (url != null) {
          // Abre el NAVEGADOR (no embebido): regla del 30% de Apple.
          await launchUrl(Uri.parse(url),
              mode: LaunchMode.externalApplication);
          return;
        }
        if (res['updated'] == true) {
          _snack(
              'Suscripción actualizada. El prorrateo aparece en tu próxima factura.');
          if (mounted) Navigator.of(context).pop(true);
          return;
        }
        _snack(res['error'] as String? ?? 'No se pudo iniciar la compra.');
      } else {
        // Demo (sin pila de pagos): deja la solicitud auditada.
        final user = widget.user;
        if (user == null) return;
        await widget.repo.requestLicenses(
          organizationId: widget.organizationId,
          kind: 'seat_clinico',
          requestedQuantity: _clinico,
          note: 'Plan armado: $_clinico clínico(s), $_protocolo Kura+, '
              '${modules.join('+')} · $_interval',
          by: user,
        );
        if (!mounted) return;
        _snack('Solicitud enviada. Te contactamos pronto.');
        Navigator.of(context).pop(true);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _assistedQuote() async {
    final user = widget.user;
    if (user == null) return;
    await widget.repo.requestLicenses(
      organizationId: widget.organizationId,
      kind: 'seat_clinico',
      requestedQuantity: _clinico,
      note: 'Cotización asistida (>$_seatCeiling asientos): $_clinico clínico(s), '
          '$_protocolo Kura+.',
      by: user,
    );
    if (!mounted) return;
    _snack('Solicitud enviada. Te contactamos para tu cotización.');
    Navigator.of(context).pop(true);
  }

  void _snack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(m)));
  }

  @override
  Widget build(BuildContext context) {
    final t = BrandTokens.of(context);
    final wide = MediaQuery.sizeOf(context).width >= 820;
    final config = _configColumn(t);
    final summary = _summaryColumn(t);
    return Scaffold(
      backgroundColor: t.background,
      appBar: AppBar(title: const Text('Arma tu plan')),
      body: PageMaxWidth(
        maxWidth: 1100,
        child: wide
            ? Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: config),
                    const SizedBox(width: 16),
                    SizedBox(width: 340, child: summary),
                  ],
                ),
              )
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [config, const SizedBox(height: 16), summary],
              ),
      ),
    );
  }

  // ---------------- Configuración (steppers + módulos + intervalo) ----------

  Widget _configColumn(BrandTokens t) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          _intervalToggle(t),
          const SizedBox(height: 12),
          _stepper(
            t,
            title: 'Asientos clínicos',
            subtitle: 'Uno por persona con rol clínico o de enfermería.',
            value: _clinico,
            unitCents: _unit('seat', 'clinico'),
            onChanged: _setClinico,
          ),
          _stepper(
            t,
            title: 'Protocolo Kura+',
            subtitle: 'Nunca más que tus asientos clínicos.',
            value: _protocolo,
            unitCents: _unit('seat', 'protocolo'),
            max: _clinico,
            onChanged: (v) => setState(() => _protocolo = v.clamp(0, _clinico)),
          ),
          const SizedBox(height: 8),
          Text('Módulos',
              style: TextStyle(
                  fontWeight: FontWeight.w700, color: t.textPrimary)),
          _moduleSwitch(
            t,
            title: 'Administración avanzada',
            subtitle: 'Config del protocolo, sitios extra, marca y 3 cupos '
                'admin dedicados. Lo básico ya viene incluido.',
            value: _admin,
            unitCents: _unit('module', 'admin'),
            onChanged: (v) => setState(() => _admin = v),
          ),
          _moduleSwitch(
            t,
            title: 'Insumos',
            subtitle: 'Inventario, mapeo, consumo y reabasto.',
            value: _insumos,
            unitCents: _unit('module', 'insumos'),
            onChanged: (v) => setState(() => _insumos = v),
          ),
          _moduleSwitch(
            t,
            title: 'Comercial',
            subtitle: 'Cotización y venta de productos.',
            value: _comercial,
            unitCents: _unit('module', 'comercial'),
            onChanged: (v) => setState(() => _comercial = v),
          ),
        ],
      );

  Widget _intervalToggle(BrandTokens t) => Row(
        children: [
          Expanded(
            child: SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'month', label: Text('Mensual')),
                ButtonSegment(value: 'year', label: Text('Anual · 10 meses')),
              ],
              selected: {_interval},
              onSelectionChanged: (s) => setState(() => _interval = s.first),
            ),
          ),
        ],
      );

  Widget _stepper(
    BrandTokens t, {
    required String title,
    required String subtitle,
    required int value,
    required int? unitCents,
    int? max,
    required ValueChanged<int> onChanged,
  }) {
    final atMax = max != null && value >= max;
    return Card(
      color: t.surface,
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: TextStyle(
                          fontWeight: FontWeight.w700, color: t.textPrimary)),
                  const SizedBox(height: 2),
                  Text(subtitle,
                      style:
                          TextStyle(fontSize: 11, color: t.textSecondary)),
                  const SizedBox(height: 2),
                  Text('${moneyOrDash(unitCents)} c/u',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: t.textSecondary)),
                ],
              ),
            ),
            IconButton(
              onPressed: value > 0 ? () => onChanged(value - 1) : null,
              icon: const Icon(Icons.remove_circle_outline),
            ),
            SizedBox(
              width: 28,
              child: Text('$value',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 18,
                      color: t.textPrimary)),
            ),
            IconButton(
              onPressed: atMax ? null : () => onChanged(value + 1),
              icon: const Icon(Icons.add_circle_outline),
            ),
          ],
        ),
      ),
    );
  }

  Widget _moduleSwitch(
    BrandTokens t, {
    required String title,
    required String subtitle,
    required bool value,
    required int? unitCents,
    required ValueChanged<bool> onChanged,
  }) =>
      Card(
        color: t.surface,
        margin: const EdgeInsets.only(bottom: 10),
        child: SwitchListTile(
          value: value,
          activeColor: t.brandPrimary,
          onChanged: onChanged,
          title: Text(title,
              style: TextStyle(
                  fontWeight: FontWeight.w700, color: t.textPrimary)),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(subtitle,
                  style: TextStyle(fontSize: 11, color: t.textSecondary)),
              Text(
                  '${moneyOrDash(unitCents)} / ${_interval == 'year' ? 'año' : 'mes'}',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: t.textSecondary)),
            ],
          ),
        ),
      );

  // ---------------- Resumen vivo (total + delta + CTA) ----------------------

  Widget _summaryColumn(BrandTokens t) {
    final annual = _interval == 'year';
    final total = _selectedTotal;
    final sel = _selectedMonthly;
    final cur = _currentMonthly;
    // El delta solo es fiable si AMBOS lados tienen todos sus precios.
    final deltaOk = sel.complete && cur.complete;
    final deltaMonthly = sel.cents - cur.cents;
    return Card(
      color: t.surface,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Resumen',
                style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                    color: t.textPrimary)),
            const SizedBox(height: 10),
            if (_clinico > 0)
              _line(t, 'Asientos clínicos ×$_clinico',
                  _unit('seat', 'clinico'), _clinico),
            if (_protocolo > 0)
              _line(t, 'Protocolo Kura+ ×$_protocolo',
                  _unit('seat', 'protocolo'), _protocolo),
            if (_admin)
              _line(t, 'Administración avanzada', _unit('module', 'admin'), 1),
            if (_insumos) _line(t, 'Insumos', _unit('module', 'insumos'), 1),
            if (_comercial)
              _line(t, 'Comercial', _unit('module', 'comercial'), 1),
            const Divider(),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(annual ? 'Total al año' : 'Total al mes',
                    style: TextStyle(
                        fontWeight: FontWeight.w800, color: t.textPrimary)),
                Text(
                    '${pesosFromCents(total.cents)}${annual ? ' /año' : ' /mes'}',
                    style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 18,
                        color: t.brandPrimary)),
              ],
            ),
            if (!total.complete)
              Text(
                  'Total incompleto: falta un precio en el catálogo. No se muestra '
                  'como \$0.',
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: t.statusWarning)),
            if (annual)
              Text('Equivale a 10 meses: pagas dos menos que mensual.',
                  style:
                      TextStyle(fontSize: 11, color: t.statusSuccess)),
            const SizedBox(height: 6),
            if (deltaOk)
              _deltaLine(t, deltaMonthly)
            else
              Text('Cambio vs plan actual: no disponible (falta un precio).',
                  style: TextStyle(fontSize: 12, color: t.textSecondary)),
            const SizedBox(height: 14),
            if (_overCeiling) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: t.statusWarning.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  'Más de $_seatCeiling asientos clínicos: por aquí ya no se '
                  'compra solo. Te armamos una cotización asistida.',
                  style: TextStyle(fontSize: 12, color: t.textPrimary),
                ),
              ),
              const SizedBox(height: 8),
              FilledButton.icon(
                onPressed: _busy ? null : _assistedQuote,
                icon: const Icon(Icons.support_agent_outlined),
                label: const Text('Solicitar cotización asistida'),
              ),
            ] else
              FilledButton.icon(
                onPressed: _busy ? null : _continue,
                icon: _busy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child:
                            CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.lock_outline),
                label: Text(widget.repo.supportsLicenseCheckout
                    ? 'Continuar al pago'
                    : 'Solicitar este plan'),
              ),
            if (widget.repo.supportsLicenseCheckout)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'El pago abre tu navegador (Stripe). Si ya tienes suscripción, '
                  'se ajusta y el prorrateo cae en tu próxima factura.',
                  style: TextStyle(fontSize: 11, color: t.textSecondary),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _line(BrandTokens t, String label, int? unitCents, int qty) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Flexible(
                child: Text(label,
                    style: TextStyle(fontSize: 13, color: t.textPrimary))),
            Text(moneyOrDash(unitCents == null ? null : unitCents * qty),
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: t.textPrimary)),
          ],
        ),
      );

  Widget _deltaLine(BrandTokens t, int deltaMonthly) {
    if (deltaMonthly == 0) {
      return Text('Sin cambio contra tu plan actual.',
          style: TextStyle(fontSize: 12, color: t.textSecondary));
    }
    final up = deltaMonthly > 0;
    return Row(
      children: [
        Icon(up ? Icons.trending_up : Icons.trending_down,
            size: 16, color: up ? t.statusWarning : t.statusSuccess),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            '${up ? '+' : '−'}${pesosFromCents(deltaMonthly.abs())} / mes '
            'vs tu plan actual',
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: up ? t.statusWarning : t.statusSuccess),
          ),
        ),
      ],
    );
  }
}
