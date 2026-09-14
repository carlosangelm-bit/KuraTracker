import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/design/tokens.dart';
import '../../../core/format/money.dart';

/// Un derecho que se puede otorgar (módulo o asiento), con su importe mensual ya
/// leído del catálogo. La pantalla arma la lista; el diálogo no toca el repo (así
/// se prueba en local).
class GrantTarget {
  final String kind; // 'module' | 'seat'
  final String key;
  final String label;
  final int? monthlyCents; // de billing_catalog; null → "—"
  final bool needsQuantity; // los asientos llevan cantidad
  const GrantTarget({
    required this.kind,
    required this.key,
    required this.label,
    required this.monthlyCents,
    this.needsQuantity = false,
  });
}

/// Meses del periodo entre [from] y [to], redondeando hacia arriba la fracción; al
/// menos 1. Para el total del periodo en la banda de consecuencia.
int periodMonths(DateTime from, DateTime to) {
  if (!to.isAfter(from)) return 1;
  var m = (to.year - from.year) * 12 + (to.month - from.month);
  if (to.day > from.day) m += 1;
  return m < 1 ? 1 : m;
}

typedef GrantSubmit = Future<void> Function({
  required GrantTarget target,
  required String grantType,
  required String reason,
  int? quantity,
  DateTime? until,
  required bool permanent,
});

/// Otorgar derecho (§5.3). Modal 620 px. Reglas de conducta:
/// - "Otorgar" deshabilitado mientras falte tipo, motivo (≥10) o vigencia.
/// - "Permanente" vacía y deshabilita el campo de fecha.
/// - La banda de consecuencia recalcula en vivo desde el catálogo: mensual + total
///   del periodo (hoy→fecha); con "Permanente" desaparece el total.
/// - La línea de solo lectura al vencer NO es colapsable ni opcional.
/// Los errores de masterGrantEntitlement ya vienen traducidos del repo: se muestran
/// tal cual.
class GrantEntitlementDialog extends StatefulWidget {
  final List<GrantTarget> targets;
  final GrantTarget? initialTarget;
  final GrantSubmit onSubmit;
  const GrantEntitlementDialog({
    super.key,
    required this.targets,
    required this.onSubmit,
    this.initialTarget,
  });

  @override
  State<GrantEntitlementDialog> createState() => _GrantEntitlementDialogState();
}

class _GrantEntitlementDialogState extends State<GrantEntitlementDialog> {
  late GrantTarget? _target =
      widget.initialTarget ?? (widget.targets.isNotEmpty ? widget.targets.first : null);
  String? _grantType; // 'comercial' | 'cortesia'
  final _reasonCtrl = TextEditingController();
  final _qtyCtrl = TextEditingController();
  DateTime? _date;
  int? _presetDays;
  bool _permanent = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _reasonCtrl.dispose();
    _qtyCtrl.dispose();
    super.dispose();
  }

  bool get _reasonOk => _reasonCtrl.text.trim().length >= 10;
  bool get _vigenciaOk => _permanent || _date != null;
  bool get _qtyOk {
    if (_target?.needsQuantity != true) return true;
    final q = int.tryParse(_qtyCtrl.text.trim());
    return q != null && q >= 0;
  }

  bool get _canSubmit =>
      _target != null && _grantType != null && _reasonOk && _vigenciaOk && _qtyOk;

  void _setPreset(int days) {
    setState(() {
      _presetDays = days;
      _date = DateTime.now().add(Duration(days: days));
    });
  }

  void _togglePermanent(bool v) {
    setState(() {
      _permanent = v;
      if (v) {
        // "Permanente" VACÍA el campo de fecha.
        _date = null;
        _presetDays = null;
      }
    });
  }

  Future<void> _submit() async {
    if (!_canSubmit || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.onSubmit(
        target: _target!,
        grantType: _grantType!,
        reason: _reasonCtrl.text.trim(),
        quantity: _target!.needsQuantity
            ? int.tryParse(_qtyCtrl.text.trim())
            : null,
        until: _permanent ? null : _date,
        permanent: _permanent,
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      // Ya viene traducido del repo: mostrarlo tal cual.
      if (mounted) {
        setState(() {
          _busy = false;
          _error = '$e'.replaceFirst('Exception: ', '');
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = BrandTokens.of(context);
    final target = _target;
    final monthly = target?.monthlyCents;
    return Dialog(
      backgroundColor: t.surface,
      shape: RoundedRectangleBorder(borderRadius: AppRadii.mdR),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Otorgar derecho',
                  style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: t.textPrimary)),
              const SizedBox(height: 18),

              _fieldLabel(t, 'Derecho'),
              DropdownButtonFormField<GrantTarget>(
                value: target,
                decoration: _decoration(t),
                items: [
                  for (final g in widget.targets)
                    DropdownMenuItem(value: g, child: Text(g.label)),
                ],
                onChanged: (v) => setState(() {
                  _target = v;
                  _qtyCtrl.clear();
                }),
              ),
              const SizedBox(height: 16),

              _fieldLabel(t, 'Tipo'),
              Wrap(
                spacing: 8,
                children: [
                  _typeChip(t, 'comercial', 'Acuerdo comercial'),
                  _typeChip(t, 'cortesia', 'Cortesía'),
                ],
              ),
              const SizedBox(height: 16),

              if (target?.needsQuantity == true) ...[
                _fieldLabel(t, 'Cantidad (asientos)'),
                TextField(
                  controller: _qtyCtrl,
                  keyboardType: TextInputType.number,
                  decoration: _decoration(t),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 16),
              ],

              _fieldLabel(t, 'Motivo'),
              TextField(
                controller: _reasonCtrl,
                minLines: 2,
                maxLines: 3,
                decoration: _decoration(t).copyWith(
                  hintText: 'Al menos 10 caracteres',
                  helperText: _reasonOk
                      ? null
                      : 'El motivo debe tener al menos 10 caracteres.',
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 16),

              _fieldLabel(t, 'Vigencia'),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _presetChip(t, 30, '30 días'),
                  _presetChip(t, 90, '90 días'),
                  _presetChip(t, 365, '1 año'),
                ],
              ),
              const SizedBox(height: 8),
              if (_date != null && !_permanent)
                Text('Vence el ${DateFormat('dd/MM/yyyy').format(_date!)}',
                    style: TextStyle(fontSize: 13, color: t.textPrimary)),
              Row(
                children: [
                  Checkbox(
                    value: _permanent,
                    onChanged: (v) => _togglePermanent(v ?? false),
                  ),
                  Text('Permanente (a propósito, sin fecha)',
                      style: TextStyle(fontSize: 13, color: t.textPrimary)),
                ],
              ),
              const SizedBox(height: 16),

              _consequenceBand(t, monthly),

              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!,
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: t.statusDanger)),
              ],
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed:
                        _busy ? null : () => Navigator.of(context).pop(false),
                    child: const Text('Cancelar'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: (_canSubmit && !_busy) ? _submit : null,
                    style: FilledButton.styleFrom(
                      backgroundColor: t.brandPrimary,
                      foregroundColor: t.onBrand,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 12),
                    ),
                    child: _busy
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('Otorgar'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _fieldLabel(BrandTokens t, String s) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(s,
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: t.textSecondary)),
      );

  InputDecoration _decoration(BrandTokens t) => InputDecoration(
        isDense: true,
        border: OutlineInputBorder(borderRadius: AppRadii.smR),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      );

  Widget _typeChip(BrandTokens t, String value, String label) {
    final selected = _grantType == value;
    return InkWell(
      onTap: () => setState(() => _grantType = value),
      borderRadius: AppRadii.pillR,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? t.brandPrimary : t.surface,
          border: Border.all(color: selected ? t.brandPrimary : t.border),
          borderRadius: AppRadii.pillR,
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: selected ? t.onBrand : t.textSecondary)),
      ),
    );
  }

  Widget _presetChip(BrandTokens t, int days, String label) {
    final selected = !_permanent && _presetDays == days;
    final disabled = _permanent;
    return InkWell(
      onTap: disabled ? null : () => _setPreset(days),
      borderRadius: AppRadii.pillR,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? t.brandPrimary : t.surface,
          border: Border.all(color: selected ? t.brandPrimary : t.border),
          borderRadius: AppRadii.pillR,
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: disabled
                    ? t.textDisabled
                    : (selected ? t.onBrand : t.textSecondary))),
      ),
    );
  }

  Widget _consequenceBand(BrandTokens t, int? monthly) {
    final total = (!_permanent && _date != null && monthly != null)
        ? monthly * periodMonths(DateTime.now(), _date!)
        : null;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: t.chipBg,
        borderRadius: AppRadii.smR,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Mensual: ',
                  style: TextStyle(fontSize: 13, color: t.textSecondary)),
              Text(moneyOrDash(monthly),
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: t.textPrimary)),
            ],
          ),
          // Con "Permanente" marcada, desaparece el total y queda solo el mensual.
          if (!_permanent && _date != null) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                Text('Total del periodo: ',
                    style: TextStyle(fontSize: 13, color: t.textSecondary)),
                Text(moneyOrDash(total),
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: t.textPrimary)),
              ],
            ),
          ],
          const SizedBox(height: 8),
          // No colapsable ni opcional.
          Text(
            'Al vencer, el derecho queda en solo lectura; no se oculta.',
            style: TextStyle(fontSize: 11, color: t.textSecondary),
          ),
        ],
      ),
    );
  }
}
