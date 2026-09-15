import 'package:flutter/material.dart';

import '../../core/design/tokens.dart';
import '../../core/widgets/dashed_border_box.dart';
import '../../models/center_type.dart';
import '../../models/organization.dart';
import '../../services/data_repository.dart';
import 'derechos/center_license_data.dart';

/// Plataforma · Centros (§5.1, canvas "Consola master · Derechos" — artboard Main).
/// Sustituye las tarjetas viejas (que no decían nada de derechos) por las siete
/// columnas: Centro · Tipo · Plan · Módulos con derecho · Asientos clínicos · Origen ·
/// Requiere atención. Todo lo derivado (píldoras, Origen, Requiere atención) sale de
/// [center_license_data] —la MISMA fuente que el panel de Licencia—, no de una lógica
/// propia, para que las dos pantallas no discrepen.
///
/// Prioridad de columnas definida desde el principio (§9): la TABLA solo se pinta cuando
/// el contenido tiene ≥ 1000 px; por debajo (1000/430 px) cae a TARJETAS —otra forma,
/// sin encabezados que partir ni importes que cortar—. Fonts-free a propósito (usa
/// BrandTokens.forCenterType, no el centerTypeColor de app_shell) para poder probarse
/// sin google_fonts.
class PlatformCentersView extends StatelessWidget {
  final DataRepository repo;
  final List<Organization> organizations;
  final String? selectedOrgId;
  final ValueChanged<String> onSelect;
  final VoidCallback onChanged;
  final ValueChanged<Organization> onMembers;
  const PlatformCentersView({
    super.key,
    required this.repo,
    required this.organizations,
    required this.selectedOrgId,
    required this.onSelect,
    required this.onChanged,
    required this.onMembers,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final wide = c.maxWidth >= 1000;
      final rows = organizations.map(_derive).toList();
      if (wide) return _CentersTable(view: this, rows: rows);
      return _CentersCards(view: this, rows: rows);
    });
  }

  _CenterData _derive(Organization o) {
    final summary = repo.licenseSummaryFor(o.id).clinicalSeats;
    return _CenterData(
      org: o,
      plan: _planLabel(repo, o.id),
      modules: moduleLicenseRows(repo, o.id),
      seatsUsed: summary.used,
      seatsContracted: summary.contracted,
      origin: centerOrigin(repo, o.id),
      attention: centerAttention(repo, o.id),
    );
  }

  // ---- controles conservados (tipo, activo con confirmación, miembros) --------

  Future<void> _changeType(BuildContext context, Organization o, CenterType? t) async {
    if (t == null || t == o.centerType) return;
    await repo.setCenterType(o.id, t);
    onChanged();
  }

  /// Apagar un centro entero pide CONFIRMACIÓN que lo nombra y dice qué implica —
  /// apagar es legítimo, un toque accidental no. Reactivar no pregunta.
  Future<void> _toggleActive(BuildContext context, Organization o, bool value) async {
    if (!value) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (dctx) => AlertDialog(
          title: Text('¿Desactivar "${o.name}"?'),
          content: const Text(
              'Nadie de este centro podrá entrar a la app mientras esté desactivado. '
              'Los datos no se borran; se puede reactivar después.'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dctx, false),
                child: const Text('Cancelar')),
            FilledButton(
                onPressed: () => Navigator.pop(dctx, true),
                child: const Text('Desactivar')),
          ],
        ),
      );
      if (ok != true) return; // cancelar no cambia nada
    }
    await repo.setOrganizationActive(o.id, value);
    onChanged();
  }
}

/// Datos derivados de un centro para la fila/tarjeta (calculados una vez).
class _CenterData {
  final Organization org;
  final String plan;
  final List<ModuleLicenseRow> modules;
  final int seatsUsed;
  final int seatsContracted;
  final CenterOrigin origin;
  final CenterAttention attention;
  const _CenterData({
    required this.org,
    required this.plan,
    required this.modules,
    required this.seatsUsed,
    required this.seatsContracted,
    required this.origin,
    required this.attention,
  });
}

String _planLabel(DataRepository repo, String orgId) {
  for (final e in repo.entitlementsFor(orgId)) {
    if (e.kind == 'plan' && e.status == 'active') {
      switch (e.key) {
        case 'prueba':
          return 'Prueba';
        case 'basico':
          return 'Básico';
        case 'gratuito':
          return 'Gratuito';
        default:
          return e.key;
      }
    }
  }
  return '—';
}

const _moduleShort = <String, String>{
  'clinico': 'Clínico',
  'admin': 'Admin',
  'insumos': 'Insumos',
  'comercial': 'Comercial',
};

/// Las píldoras de "Módulos con derecho": una por módulo, RELLENA si el centro tiene el
/// derecho (`hasRight`, leído de org_entitlements) y CONTORNO PUNTEADO textDisabled si
/// no. Se lee el DERECHO, nunca el interruptor: un centro con `module:insumos` pero el
/// interruptor de module_settings apagado sale relleno.
class CenterModulePills extends StatelessWidget {
  final List<ModuleLicenseRow> rows;
  const CenterModulePills({super.key, required this.rows});

  @override
  Widget build(BuildContext context) {
    final t = BrandTokens.of(context);
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final r in rows)
          KeyedSubtree(
            key: ValueKey('module-pill:${r.key}:${r.hasRight ? 'on' : 'off'}'),
            child: r.hasRight
                ? _pillFilled(t, _moduleShort[r.key] ?? r.label)
                : _pillDotted(t, _moduleShort[r.key] ?? r.label),
          ),
      ],
    );
  }

  Widget _pillFilled(BrandTokens t, String label) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
        decoration: BoxDecoration(
          color: t.brandPrimary.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 11, fontWeight: FontWeight.w700, color: t.brandPrimary)),
      );

  Widget _pillDotted(BrandTokens t, String label) => DashedBorderBox(
        color: t.textDisabled,
        radius: 20,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
          child: Text(label,
              style: TextStyle(fontSize: 11, color: t.textDisabled)),
        ),
      );
}

// ------------------------------------------------------------------ tabla ancha
class _CentersTable extends StatelessWidget {
  final PlatformCentersView view;
  final List<_CenterData> rows;
  const _CentersTable({required this.view, required this.rows});

  @override
  Widget build(BuildContext context) {
    final t = BrandTokens.of(context);
    TextStyle head() => TextStyle(
        fontSize: 11, fontWeight: FontWeight.w700, color: t.textSecondary);
    Widget hc(String s) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
        child: Text(s, style: head()));
    return SingleChildScrollView(
      child: Table(
        defaultVerticalAlignment: TableCellVerticalAlignment.middle,
        columnWidths: const {
          0: FlexColumnWidth(3), // Centro
          1: FlexColumnWidth(2.4), // Tipo
          2: FlexColumnWidth(1.4), // Plan
          3: FlexColumnWidth(4), // Módulos
          4: FlexColumnWidth(1.6), // Asientos
          5: FlexColumnWidth(1.6), // Origen
          6: FlexColumnWidth(2.4), // Requiere atención
          7: FlexColumnWidth(2.2), // acciones (activo + miembros)
        },
        children: [
          TableRow(
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: t.border)),
            ),
            children: [
              hc('Centro'),
              hc('Tipo'),
              hc('Plan'),
              hc('Módulos con derecho'),
              hc('Asientos'),
              hc('Origen'),
              hc('Requiere atención'),
              hc(''),
            ],
          ),
          for (final r in rows) _row(context, t, r),
        ],
      ),
    );
  }

  TableRow _row(BuildContext context, BrandTokens t, _CenterData r) {
    final o = r.org;
    Widget cell(Widget w) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10), child: w);
    return TableRow(
      decoration: BoxDecoration(
        color: o.id == view.selectedOrgId ? t.chipBg : null,
        border: Border(bottom: BorderSide(color: t.border)),
      ),
      children: [
        cell(_centerName(t, o)),
        cell(_typeDropdown(context, o)),
        cell(Text(r.plan, style: TextStyle(fontSize: 13, color: t.textPrimary))),
        cell(CenterModulePills(rows: r.modules)),
        cell(Text('${r.seatsUsed}/${r.seatsContracted}',
            style: TextStyle(fontSize: 13, color: t.textPrimary))),
        cell(Text(centerOriginLabel(r.origin),
            style: TextStyle(fontSize: 13, color: t.textSecondary))),
        cell(_attention(t, r.attention)),
        cell(_actions(context, o)),
      ],
    );
  }

  Widget _centerName(BrandTokens t, Organization o) => InkWell(
      onTap: () => view.onSelect(o.id),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            alignment: Alignment.center,
            decoration: BoxDecoration(
                color: BrandTokens.forCenterType(o.centerType)
                    .brandPrimary
                    .withValues(alpha: 0.12),
                shape: BoxShape.circle),
            child: Icon(Icons.hub_outlined,
                size: 16,
                color: BrandTokens.forCenterType(o.centerType).brandPrimary),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(o.name,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontWeight: FontWeight.w700, color: t.textPrimary)),
                if (o.isTest) _testTag(t),
                if (!o.isActive)
                  Text('Inactivo',
                      style: TextStyle(fontSize: 11, color: t.statusDanger)),
              ],
            ),
          ),
        ],
      ));

  Widget _typeDropdown(BuildContext context, Organization o) =>
      _CenterTypeDropdown(org: o, onChanged: (ct) => view._changeType(context, o, ct));

  Widget _attention(BrandTokens t, CenterAttention a) => Text(
        centerAttentionLabel(a),
        style: TextStyle(
            fontSize: 13,
            color: a.any ? t.statusWarningText : t.textSecondary,
            fontWeight: a.any ? FontWeight.w600 : FontWeight.w400),
      );

  Widget _actions(BuildContext context, Organization o) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ActiveSwitch(
              active: o.isActive,
              onChanged: (v) => view._toggleActive(context, o, v)),
          IconButton(
            tooltip: 'Miembros',
            icon: const Icon(Icons.group_outlined, size: 20),
            onPressed: () => view.onMembers(o),
          ),
        ],
      );
}

// ---------------------------------------------------------------- tarjetas angostas
class _CentersCards extends StatelessWidget {
  final PlatformCentersView view;
  final List<_CenterData> rows;
  const _CentersCards({required this.view, required this.rows});

  @override
  Widget build(BuildContext context) {
    final t = BrandTokens.of(context);
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: rows.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, i) {
        final r = rows[i];
        final o = r.org;
        return Container(
          decoration: BoxDecoration(
            color: o.id == view.selectedOrgId ? t.chipBg : t.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: t.border),
          ),
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () => view.onSelect(o.id),
                      child: Text(o.name,
                          style: TextStyle(
                              fontWeight: FontWeight.w800, color: t.textPrimary)),
                    ),
                  ),
                  if (o.isTest) _testTag(t),
                ],
              ),
              const SizedBox(height: 8),
              _CenterTypeDropdown(
                  org: o, onChanged: (ct) => view._changeType(context, o, ct)),
              const SizedBox(height: 8),
              _kv(t, 'Plan', r.plan),
              _kv(t, 'Asientos clínicos', '${r.seatsUsed}/${r.seatsContracted}'),
              _kv(t, 'Origen', centerOriginLabel(r.origin)),
              _kv(t, 'Requiere atención', centerAttentionLabel(r.attention),
                  danger: r.attention.any),
              const SizedBox(height: 6),
              Text('Módulos con derecho',
                  style: TextStyle(fontSize: 11, color: t.textSecondary)),
              const SizedBox(height: 4),
              CenterModulePills(rows: r.modules),
              const SizedBox(height: 8),
              Row(
                children: [
                  const Text('Activo', style: TextStyle(fontSize: 12)),
                  _ActiveSwitch(
                      active: o.isActive,
                      onChanged: (v) => view._toggleActive(context, o, v)),
                  const Spacer(),
                  TextButton.icon(
                    icon: const Icon(Icons.group_outlined, size: 18),
                    label: const Text('Miembros'),
                    onPressed: () => view.onMembers(o),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _kv(BrandTokens t, String k, String v, {bool danger = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
                width: 140,
                child: Text(k,
                    style: TextStyle(fontSize: 12, color: t.textSecondary))),
            Expanded(
              child: Text(v,
                  style: TextStyle(
                      fontSize: 13,
                      color: danger ? t.statusWarningText : t.textPrimary,
                      fontWeight: danger ? FontWeight.w600 : FontWeight.w400)),
            ),
          ],
        ),
      );
}

Widget _testTag(BrandTokens t) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
          color: t.statusWarningText.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(8)),
      child: Text('PRUEBA',
          style: TextStyle(
              fontSize: 10, fontWeight: FontWeight.w800, color: t.statusWarningText)),
    );

class _CenterTypeDropdown extends StatelessWidget {
  final Organization org;
  final ValueChanged<CenterType?> onChanged;
  const _CenterTypeDropdown({required this.org, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return DropdownButton<CenterType>(
      value: org.centerType,
      isDense: true,
      isExpanded: true, // llena la columna y ELIPSA; sin esto desborda la celda
      underline: const SizedBox.shrink(),
      items: [
        for (final ct in CenterType.values)
          DropdownMenuItem(
              value: ct,
              child: Text(ct.label, style: const TextStyle(fontSize: 13))),
      ],
      onChanged: onChanged,
    );
  }
}

class _ActiveSwitch extends StatelessWidget {
  final bool active;
  final ValueChanged<bool> onChanged;
  const _ActiveSwitch({required this.active, required this.onChanged});

  @override
  Widget build(BuildContext context) => Switch(
        value: active,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        onChanged: onChanged,
      );
}
