import 'package:flutter/material.dart';

import '../../core/design/tokens.dart';
import '../../models/app_user.dart';
import '../../models/license_summary.dart';
import '../../services/data_repository.dart';
import 'license_plan_builder_screen.dart';

/// Panel de Licencias del administrador del centro (Fase 2, rediseño del canvas).
/// Cuatro estados: NORMAL (hero + tabla + módulos + Kura+), CONFIGURADOR (pantalla
/// aparte, [LicensePlanBuilderScreen]), PRUEBA VENCIDA y TECHO DEL AUTOSERVICIO.
///
/// Precios: SIEMPRE de billing_catalog (repo.unitAmountCents), nunca a mano.
/// Color: SIEMPRE BrandTokens.of(context) — así un hospital sale azul, no morado.
/// El pago abre el NAVEGADOR (no embebe Stripe: regla del 30% de Apple).
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
  DataRepository get repo => widget.repo;
  String get _org => widget.organizationId!;

  int _u(String kind, String key) => repo.unitAmountCents(kind, key, 'month');

  bool get _admin => repo.premiumAdminFor(_org);
  bool get _insumos => repo.premiumInsumosFor(_org);
  bool get _comercial => repo.premiumComercialFor(_org);

  int _monthlyTotalCents(LicenseSummary s) {
    final proto = s.protocolo.contracted < 0 ? 0 : s.protocolo.contracted;
    return s.clinicalSeats.contracted * _u('seat', 'clinico') +
        proto * _u('seat', 'protocolo') +
        (_admin ? _u('module', 'admin') : 0) +
        (_insumos ? _u('module', 'insumos') : 0) +
        (_comercial ? _u('module', 'comercial') : 0);
  }

  List<AppUser> _kuraAssigned() => repo
      .listUsers()
      .where((u) =>
          u.organizationId == _org && u.isActive && u.premiumEnabled)
      .toList()
    ..sort((a, b) => a.fullName.toLowerCase().compareTo(b.fullName.toLowerCase()));

  @override
  Widget build(BuildContext context) {
    final t = BrandTokens.of(context);
    if (widget.organizationId == null) {
      return Center(
        child: Text('Selecciona un centro para ver sus licencias.',
            style: TextStyle(color: t.textSecondary)),
      );
    }
    final s = repo.licenseSummaryFor(_org);

    if (s.trialExpired) return _trialExpiredView(t, s);

    final ceiling = s.state == LicenseState.techoAutoservicio;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (s.pastDue) ...[_impagoBand(t), const SizedBox(height: 12)],
        _hero(t, s, ceiling: ceiling),
        const SizedBox(height: 14),
        _includedCard(t),
        const SizedBox(height: 14),
        _planTable(t, s),
        const SizedBox(height: 14),
        _sectionTitle(t, 'Módulos'),
        _moduleCard(t,
            title: 'Administración (avanzada)',
            active: _admin,
            monthlyCents: _u('module', 'admin'),
            unlocks: 'Config del protocolo, sitios extra, marca y 3 cupos '
                'administrativos dedicados.'),
        _moduleCard(t,
            title: 'Insumos',
            active: _insumos,
            monthlyCents: _u('module', 'insumos'),
            unlocks: 'Inventario, mapeo, consumo y reabasto.'),
        _moduleCard(t,
            title: 'Comercial',
            active: _comercial,
            monthlyCents: _u('module', 'comercial'),
            unlocks: 'Cotización y venta de productos.'),
        const SizedBox(height: 14),
        _kuraCard(t, s),
      ],
    );
  }

  // ---------------- Hero ----------------

  Widget _hero(BrandTokens t, LicenseSummary s, {required bool ceiling}) {
    final total = _monthlyTotalCents(s);
    final concepts = <String>[
      if (s.clinicalSeats.contracted > 0)
        '${s.clinicalSeats.contracted} asiento${s.clinicalSeats.contracted == 1 ? '' : 's'} clínico${s.clinicalSeats.contracted == 1 ? '' : 's'}',
      if ((s.protocolo.contracted) > 0) '${s.protocolo.contracted} Kura+',
      if (_admin) 'Administración',
      if (_insumos) 'Insumos',
      if (_comercial) 'Comercial',
    ];
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [t.heroTop, t.heroBottom],
        ),
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            s.plan == 'prueba' ? 'Tu prueba' : 'Tu plan',
            style: TextStyle(
                color: t.onBrand.withValues(alpha: 0.8),
                fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(pesosFromCents(total),
                  style: TextStyle(
                      color: t.onBrand,
                      fontSize: 34,
                      fontWeight: FontWeight.w900)),
              const SizedBox(width: 6),
              Text('/mes',
                  style: TextStyle(
                      color: t.onBrand.withValues(alpha: 0.85),
                      fontSize: 16,
                      fontWeight: FontWeight.w600)),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            concepts.isEmpty ? 'Aún sin conceptos activos.' : concepts.join('  ·  '),
            style: TextStyle(color: t.onBrand.withValues(alpha: 0.9), fontSize: 13),
          ),
          const SizedBox(height: 16),
          if (ceiling) ...[
            Text(
              'Llegaste al máximo del autoservicio ($kSelfServiceSeatCeiling '
              'asientos clínicos). Para crecer más, te armamos una cotización.',
              style:
                  TextStyle(color: t.onBrand.withValues(alpha: 0.95), fontSize: 12.5),
            ),
            const SizedBox(height: 10),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                  backgroundColor: t.onBrand, foregroundColor: t.heroBottom),
              onPressed: _requestAssistedQuote,
              icon: const Icon(Icons.support_agent_outlined),
              label: const Text('Solicitar cotización asistida'),
            ),
          ] else
            FilledButton.icon(
              style: FilledButton.styleFrom(
                  backgroundColor: t.onBrand, foregroundColor: t.heroBottom),
              onPressed: () => _openBuilder(s),
              icon: const Icon(Icons.tune),
              label: Text(repo.supportsLicenseCheckout
                  ? 'Arma tu plan'
                  : 'Arma tu plan (solicitud)'),
            ),
        ],
      ),
    );
  }

  // ---------------- "Ya viene incluido" ----------------

  Widget _includedCard(BrandTokens t) {
    const items = [
      'Dar de alta usuarios (dentro de tus asientos clínicos)',
      'Registrar tu primer sitio',
      'Cargar el catálogo base y las escalas del protocolo',
      'Ver licencias, registro de divulgaciones y exportar el expediente',
    ];
    return Container(
      decoration: BoxDecoration(
        color: t.statusSuccess.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: t.statusSuccess.withValues(alpha: 0.35)),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.verified_outlined, color: t.statusSuccess, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text('Ya viene incluido con tus asientos clínicos',
                    style: TextStyle(
                        fontWeight: FontWeight.w800, color: t.textPrimary)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          for (final it in items)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.check, size: 16, color: t.statusSuccess),
                  const SizedBox(width: 8),
                  Expanded(
                      child: Text(it,
                          style: TextStyle(fontSize: 13, color: t.textPrimary))),
                ],
              ),
            ),
        ],
      ),
    );
  }

  // ---------------- Tabla del plan (5 columnas) ----------------

  Widget _planTable(BrandTokens t, LicenseSummary s) {
    final protoContracted =
        s.protocolo.contracted < 0 ? 0 : s.protocolo.contracted;
    final clinicoUnit = _u('seat', 'clinico');
    final protoUnit = _u('seat', 'protocolo');
    final adminUnit = _u('module', 'admin');

    DataRow row(String concepto, String uso, String contratado,
            String precio, String subtotal,
            {bool warn = false}) =>
        DataRow(cells: [
          DataCell(Text(concepto,
              style: TextStyle(
                  fontWeight: FontWeight.w600, color: t.textPrimary))),
          DataCell(Text(uso,
              style: TextStyle(
                  color: warn ? t.statusWarning : t.textPrimary,
                  fontWeight: warn ? FontWeight.w700 : FontWeight.w400))),
          DataCell(Text(contratado, style: TextStyle(color: t.textPrimary))),
          DataCell(Text(precio, style: TextStyle(color: t.textSecondary))),
          DataCell(Text(subtotal,
              style: TextStyle(
                  fontWeight: FontWeight.w700, color: t.textPrimary))),
        ]);

    return _sectionCard(
      t,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          headingRowHeight: 40,
          dataRowMinHeight: 44,
          dataRowMaxHeight: 56,
          columnSpacing: 22,
          headingTextStyle: TextStyle(
              fontWeight: FontWeight.w800, fontSize: 12, color: t.textSecondary),
          columns: const [
            DataColumn(label: Text('Concepto')),
            DataColumn(label: Text('Uso')),
            DataColumn(label: Text('Contratado')),
            DataColumn(label: Text('Precio unitario')),
            DataColumn(label: Text('Subtotal')),
          ],
          rows: [
            row(
              'Asiento clínico',
              '${s.clinicalSeats.used}',
              '${s.clinicalSeats.contracted}',
              '${pesosFromCents(clinicoUnit)} c/u',
              pesosFromCents(s.clinicalSeats.contracted * clinicoUnit),
              warn: s.clinicalSeats.full,
            ),
            row(
              'Protocolo Kura+',
              '${s.protocolo.used}',
              '$protoContracted',
              '${pesosFromCents(protoUnit)} c/u',
              pesosFromCents(protoContracted * protoUnit),
            ),
            row(
              'Cupo administrativo',
              '${s.adminSlots.used}',
              _admin ? '3 incluidos' : '0',
              '${pesosFromCents(adminUnit)} módulo',
              pesosFromCents(_admin ? adminUnit : 0),
              warn: s.adminSeatOverflow > 0,
            ),
            row(
              'Cuidadores',
              '${s.caregivers}',
              '—',
              pesosFromCents(0),
              pesosFromCents(0),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------- Tarjetas de módulos ----------------

  Widget _moduleCard(BrandTokens t,
      {required String title,
      required bool active,
      required int monthlyCents,
      required String unlocks}) {
    return Card(
      color: t.surface,
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        leading: Icon(
            active ? Icons.check_circle : Icons.lock_outline,
            color: active ? t.statusSuccess : t.textDisabled),
        title: Text(title,
            style:
                TextStyle(fontWeight: FontWeight.w700, color: t.textPrimary)),
        subtitle: Text(unlocks,
            style: TextStyle(fontSize: 12, color: t.textSecondary)),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(active ? 'Activo' : 'No contratado',
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: active ? t.statusSuccess : t.textSecondary)),
            Text('${pesosFromCents(monthlyCents)}/mes',
                style: TextStyle(fontSize: 12, color: t.textSecondary)),
          ],
        ),
      ),
    );
  }

  // ---------------- Kura+ asignado ----------------

  Widget _kuraCard(BrandTokens t, LicenseSummary s) {
    final has = s.hasProtocoloAddon;
    final assigned = has ? _kuraAssigned() : const <AppUser>[];
    return _sectionCard(
      t,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.workspace_premium_outlined,
                  size: 20, color: t.brandPrimary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  has
                      ? 'Protocolo Kura+ asignado (${assigned.length} de ${s.protocolo.contracted})'
                      : 'Protocolo Kura+',
                  style: TextStyle(
                      fontWeight: FontWeight.w800, color: t.textPrimary),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (!has)
            Text('Add-on no contratado. Se compra por centro y se asigna por '
                'persona (en Usuarios).',
                style: TextStyle(fontSize: 13, color: t.textSecondary))
          else if (assigned.isEmpty)
            Text('Nadie tiene Kura+ asignado todavía. Asígnalo en Usuarios.',
                style: TextStyle(fontSize: 13, color: t.textSecondary))
          else
            for (final u in assigned)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  children: [
                    Icon(Icons.person_outline, size: 16, color: t.textSecondary),
                    const SizedBox(width: 8),
                    Expanded(
                        child: Text(u.fullName,
                            style: TextStyle(
                                fontSize: 13, color: t.textPrimary))),
                    Text(u.email,
                        style:
                            TextStyle(fontSize: 11, color: t.textSecondary)),
                  ],
                ),
              ),
        ],
      ),
    );
  }

  // ---------------- Estado: prueba vencida ----------------

  Widget _trialExpiredView(BrandTokens t, LicenseSummary s) {
    final activeUsers = repo
        .listUsers()
        .where((u) => u.organizationId == _org && u.isActive)
        .length;
    // Plan sugerido desde el uso REAL: asientos = demanda actual (mín. 1); Kura+ =
    // asignados; módulos = los que ya estaban activos en la prueba.
    final suggestClinico =
        s.clinicalSeats.used > 0 ? s.clinicalSeats.used : 1;
    final suggestProtocolo = _kuraAssigned().length;
    final suggestCents = suggestClinico * _u('seat', 'clinico') +
        suggestProtocolo * _u('seat', 'protocolo') +
        (_admin ? _u('module', 'admin') : 0) +
        (_insumos ? _u('module', 'insumos') : 0) +
        (_comercial ? _u('module', 'comercial') : 0);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [t.heroTop, t.heroBottom],
            ),
          ),
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Esto es lo que construiste en 30 días',
                  style: TextStyle(
                      color: t.onBrand,
                      fontSize: 20,
                      fontWeight: FontWeight.w900)),
              const SizedBox(height: 14),
              Wrap(
                spacing: 24,
                runSpacing: 12,
                children: [
                  _stat(t, '${s.patientsUsed}', 'pacientes'),
                  _stat(t, '$activeUsers', 'usuarios activos'),
                  _stat(t, '${s.clinicalSeats.used}', 'asientos en uso'),
                  _stat(t, '${_kuraAssigned().length}', 'con Kura+'),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _availabilityCard(
                t,
                title: 'Sigue disponible',
                color: t.statusSuccess,
                icon: Icons.lock_open_outlined,
                items: const [
                  'Leer todo el expediente',
                  'Exportar los datos del centro',
                  'Registro de divulgaciones',
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _availabilityCard(
                t,
                title: 'En pausa',
                color: t.statusWarning,
                icon: Icons.pause_circle_outline,
                items: const [
                  'Crear y editar notas clínicas',
                  'Alta de nuevos usuarios',
                  'Nuevas valoraciones y seguimientos',
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        _sectionCard(
          t,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Tu plan sugerido, armado desde tu uso real',
                  style: TextStyle(
                      fontWeight: FontWeight.w800, color: t.textPrimary)),
              const SizedBox(height: 8),
              Text(
                '$suggestClinico asiento${suggestClinico == 1 ? '' : 's'} clínico'
                '${suggestClinico == 1 ? '' : 's'}'
                '${suggestProtocolo > 0 ? ' · $suggestProtocolo Kura+' : ''}'
                '${_admin ? ' · Administración' : ''}'
                '${_insumos ? ' · Insumos' : ''}'
                '${_comercial ? ' · Comercial' : ''}',
                style: TextStyle(fontSize: 13, color: t.textPrimary),
              ),
              const SizedBox(height: 6),
              Text('${pesosFromCents(suggestCents)} /mes',
                  style: TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 22,
                      color: t.brandPrimary)),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: () => _openBuilder(
                  s,
                  clinico: suggestClinico,
                  protocolo: suggestProtocolo,
                ),
                icon: const Icon(Icons.tune),
                label: Text(repo.supportsLicenseCheckout
                    ? 'Reactivar con este plan'
                    : 'Solicitar este plan'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _stat(BrandTokens t, String value, String label) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(value,
              style: TextStyle(
                  color: t.onBrand, fontSize: 26, fontWeight: FontWeight.w900)),
          Text(label,
              style: TextStyle(
                  color: t.onBrand.withValues(alpha: 0.85), fontSize: 12)),
        ],
      );

  Widget _availabilityCard(BrandTokens t,
          {required String title,
          required Color color,
          required IconData icon,
          required List<String> items}) =>
      Container(
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.35)),
        ),
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 18, color: color),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(title,
                      style: TextStyle(
                          fontWeight: FontWeight.w800, color: t.textPrimary)),
                ),
              ],
            ),
            const SizedBox(height: 6),
            for (final it in items)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Text('• $it',
                    style: TextStyle(fontSize: 12.5, color: t.textPrimary)),
              ),
          ],
        ),
      );

  // ---------------- Impago (banda) ----------------

  Widget _impagoBand(BrandTokens t) => Container(
        decoration: BoxDecoration(
          color: t.statusDanger.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: t.statusDanger.withValues(alpha: 0.4)),
        ),
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: t.statusDanger),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Pago vencido. El expediente sigue accesible; el alta de nuevos '
                'usuarios se cierra hasta regularizar.',
                style: TextStyle(
                    fontWeight: FontWeight.w600, color: t.textPrimary),
              ),
            ),
          ],
        ),
      );

  // ---------------- Helpers de layout ----------------

  Widget _sectionTitle(BrandTokens t, String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8, left: 2),
        child: Text(text,
            style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 15,
                color: t.textPrimary)),
      );

  Widget _sectionCard(BrandTokens t, {required Widget child}) => Container(
        decoration: BoxDecoration(
          color: t.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: t.border),
        ),
        padding: const EdgeInsets.all(14),
        child: child,
      );

  // ---------------- Acciones ----------------

  Future<void> _openBuilder(LicenseSummary s,
      {int? clinico, int? protocolo}) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => LicensePlanBuilderScreen(
          repo: repo,
          organizationId: _org,
          user: widget.user,
          initialClinico: clinico ??
              (s.clinicalSeats.contracted > 0 ? s.clinicalSeats.contracted : 1),
          initialProtocolo: protocolo ??
              (s.protocolo.contracted < 0 ? 0 : s.protocolo.contracted),
          initialAdmin: _admin,
          initialInsumos: _insumos,
          initialComercial: _comercial,
        ),
      ),
    );
    if (saved == true && mounted) setState(() {});
  }

  Future<void> _requestAssistedQuote() async {
    final user = widget.user;
    if (user == null) return;
    await repo.requestLicenses(
      organizationId: _org,
      kind: 'seat_clinico',
      note: 'Cotización asistida (techo del autoservicio).',
      by: user,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Solicitud enviada. Te contactamos para tu cotización.')));
  }
}
