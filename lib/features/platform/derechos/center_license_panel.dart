import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/design/tokens.dart';
import '../../../core/format/money.dart';
import '../../../core/widgets/kura_data_table.dart';
import '../../../core/widgets/kura_stat.dart';
import '../../../models/app_user.dart';
import '../../../models/module_key.dart';
import '../../../models/org_entitlement.dart';
import '../../../services/data_repository.dart';
import 'module_agreement.dart';

/// Centro · Licencia (§5.2), consola master · Derechos, etapa 2. La pantalla que
/// justifica el rediseño: por cada módulo compara el DERECHO (org_entitlements) con
/// el INTERRUPTOR (module_settings) y muestra los cuatro casos — incluido el
/// silencioso "encendido sin derecho: nadie lo ve" (rojo). Todo color desde
/// [BrandTokens]; importes desde billing_catalog vía unitAmountCents (null → "—").
/// Reusa KuraDataTable/KuraStat en vez de dibujar tablas nuevas.
class CenterLicensePanel extends StatelessWidget {
  final DataRepository repo;
  final String? organizationId;
  final AppUser? user;
  const CenterLicensePanel({
    super.key,
    required this.repo,
    required this.organizationId,
    required this.user,
  });

  // Un módulo de pago del grupo Módulos. `switchKey` = null cuando el módulo no
  // tiene interruptor propio (admin se gatea por rol/derecho, no por module_settings).
  static const _modules = <({String key, String label, ModuleKey? switchKey})>[
    (key: 'admin', label: 'Administración avanzada', switchKey: null),
    (key: 'insumos', label: 'Insumos', switchKey: ModuleKey.insumos),
    (key: 'comercial', label: 'Comercial', switchKey: ModuleKey.comercial),
  ];

  static const _seats = <({String key, String label})>[
    (key: 'clinico', label: 'Asientos clínicos'),
    (key: 'protocolo', label: 'Protocolo Kura+'),
  ];

  OrgEntitlement? _ent(List<OrgEntitlement> ents, String kind, String key) {
    for (final e in ents) {
      if (e.kind == kind && e.key == key) return e;
    }
    return null;
  }

  /// El INTERRUPTOR crudo del centro (module_settings a nivel centro), independiente
  /// del derecho: es justo lo que permite detectar el "encendido sin derecho".
  bool _centerSwitch(ModuleKey m) {
    final ct = repo.centerTypeFor(organizationId);
    for (final s in repo.listModuleSettings(organizationId: organizationId)) {
      if (s.moduleKey == m.dbValue && s.siteId == null && s.profileId == null) {
        return s.enabled;
      }
    }
    return m.defaultFor(ct);
  }

  String _nameFor(String? profileId) {
    if (profileId == null) return '—';
    for (final u in repo.listUsers()) {
      if (u.id == profileId) return u.fullName;
    }
    return 'Master';
  }

  String _origen(OrgEntitlement? e) => e == null
      ? '—'
      : (e.source == 'stripe' ? 'Stripe' : 'A mano');

  String _vigencia(OrgEntitlement? e) {
    if (e == null) return '—';
    if (e.isPermanent) return 'Permanente';
    final end = e.currentPeriodEnd;
    return end == null ? '—' : DateFormat('dd/MM/yyyy').format(end);
  }

  @override
  Widget build(BuildContext context) {
    final t = BrandTokens.of(context);
    final orgId = organizationId;
    if (orgId == null) {
      return Center(
        child: Text('Selecciona un centro para ver su licencia.',
            style: TextStyle(color: t.textSecondary)),
      );
    }

    final ents = repo.entitlementsFor(orgId);
    final fmt = DateFormat('dd/MM/yyyy');

    // Datos por módulo (incluye el acuerdo derecho×interruptor).
    final moduleRows = <({
      String label,
      OrgEntitlement? ent,
      bool hasRight,
      bool hasSwitch,
      bool switchOn,
      ModuleAgreement agreement,
      int? amountCents,
    })>[];
    var disagreements = 0;
    var rightsActive = 0;
    for (final m in _modules) {
      final e = _ent(ents, 'module', m.key);
      final hasRight = e != null && e.status == 'active';
      if (hasRight) rightsActive++;
      final hasSwitch = m.switchKey != null;
      // Sin interruptor propio (admin): el "interruptor" sigue al derecho, así nunca
      // aparece un desacuerdo falso.
      final switchOn = hasSwitch ? _centerSwitch(m.switchKey!) : hasRight;
      final ag = moduleAgreement(hasRight: hasRight, switchOn: switchOn);
      if (ag.kind == ModuleAgreementCase.rightOff ||
          ag.kind == ModuleAgreementCase.onWithoutRight) {
        disagreements++;
      }
      moduleRows.add((
        label: m.label,
        ent: e,
        hasRight: hasRight,
        hasSwitch: hasSwitch,
        switchOn: switchOn,
        agreement: ag,
        amountCents: repo.unitAmountCents('module', m.key, 'month'),
      ));
    }

    final summary = repo.licenseSummaryFor(orgId);

    return ListView(
      padding: const EdgeInsets.fromLTRB(28, 24, 28, 40),
      children: [
        _header(t),
        const SizedBox(height: 20),
        _statRow(t, [
          KuraStat(
            label: 'Módulos con derecho',
            value: '$rightsActive',
            meaning: 'de ${_modules.length} de pago',
          ),
          KuraStat(
            label: 'Desacuerdos',
            value: '$disagreements',
            meaning: 'derecho ≠ interruptor',
            tone: disagreements > 0 ? KuraStatTone.warning : KuraStatTone.normal,
          ),
          KuraStat(
            label: 'A mano al mes',
            value: moneyOrDash(_condonadoCents(ents)),
            meaning: 'valor de lista otorgado a mano',
          ),
        ]),
        const SizedBox(height: 22),
        _sectionTitle(t, 'Módulos'),
        const SizedBox(height: 10),
        _card(t, _modulesTable(t, moduleRows)),
        const SizedBox(height: 22),
        _sectionTitle(t, 'Asientos'),
        const SizedBox(height: 10),
        _card(t, _seatsTable(t, ents, summary)),
        const SizedBox(height: 22),
        _sectionTitle(t, 'Qué paga y qué no'),
        const SizedBox(height: 10),
        _whatPaysCard(t, ents, fmt),
      ],
    );
  }

  // ---- Piezas ----
  Widget _header(BrandTokens t) {
    final name = repo.organizationById(organizationId)?.name ?? 'Centro';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Plataforma · Licencia',
            style: TextStyle(
                fontSize: 13, fontWeight: FontWeight.w600, color: t.textSecondary)),
        const SizedBox(height: 6),
        Text(name,
            style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.02 * 28,
                color: t.textPrimary)),
      ],
    );
  }

  Widget _sectionTitle(BrandTokens t, String s) => Text(s,
      style: TextStyle(
          fontSize: 16, fontWeight: FontWeight.w800, color: t.textPrimary));

  Widget _card(BrandTokens t, Widget child) => Container(
        decoration: BoxDecoration(
          color: t.surface,
          border: Border.all(color: t.border),
          borderRadius: AppRadii.mdR,
        ),
        padding: const EdgeInsets.fromLTRB(22, 18, 22, 8),
        child: child,
      );

  Widget _statRow(BrandTokens t, List<Widget> stats) => LayoutBuilder(
        builder: (context, c) {
          final w = c.maxWidth < 640
              ? c.maxWidth
              : (c.maxWidth - 2 * 16) / 3;
          return Wrap(
            spacing: 16,
            runSpacing: 16,
            children: [for (final s in stats) SizedBox(width: w, child: s)],
          );
        },
      );

  Widget _modulesTable(BrandTokens t, List rows) {
    return KuraDataTable(
      columns: const [
        KuraColumn(label: 'Módulo', fraction: 0.16),
        KuraColumn(label: 'Origen', fraction: 0.09),
        KuraColumn(label: 'Tipo', fraction: 0.10),
        KuraColumn(label: 'Otorgó', fraction: 0.12),
        KuraColumn(label: 'Vigencia', fraction: 0.11),
        KuraColumn(label: 'Interruptor', fraction: 0.10),
        KuraColumn(label: 'Estado', fraction: 0.22),
        KuraColumn(label: 'Importe', fraction: 0.10, numeric: true),
      ],
      rows: [
        for (final r in rows)
          KuraRow(id: r.label, cells: [
            KuraCell.identity(name: r.label as String, icon: Icons.widgets_outlined),
            KuraCell.pill(_origen(r.ent as OrgEntitlement?),
                muted: (r.ent as OrgEntitlement?) == null),
            _mutedText(t, (r.ent as OrgEntitlement?)?.grantType ?? '—'),
            _mutedText(t, _nameFor((r.ent as OrgEntitlement?)?.grantedBy)),
            _mutedText(t, _vigencia(r.ent as OrgEntitlement?)),
            _mutedText(
                t,
                (r.hasSwitch as bool)
                    ? ((r.switchOn as bool) ? 'Encendido' : 'Apagado')
                    : '—'),
            KuraCell.custom(
                build: (t) =>
                    ModuleAgreementLabel(r.agreement as ModuleAgreement)),
            KuraCell.money(r.amountCents as int?),
          ]),
      ],
    );
  }

  Widget _seatsTable(
      BrandTokens t, List<OrgEntitlement> ents, dynamic summary) {
    return KuraDataTable(
      columns: const [
        KuraColumn(label: 'Asiento', fraction: 0.20),
        KuraColumn(label: 'Origen', fraction: 0.10),
        KuraColumn(label: 'Tipo', fraction: 0.12),
        KuraColumn(label: 'Otorgó', fraction: 0.14),
        KuraColumn(label: 'Vigencia', fraction: 0.13),
        KuraColumn(label: 'Uso', fraction: 0.21),
        KuraColumn(label: 'Importe', fraction: 0.10, numeric: true),
      ],
      rows: [
        for (final s in _seats)
          () {
            final e = _ent(ents, 'seat', s.key);
            final counter =
                s.key == 'clinico' ? summary.clinicalSeats : summary.protocolo;
            final used = counter.used as int;
            final contracted = (e?.quantity) ?? (counter.contracted as int);
            return KuraRow(id: s.key, cells: [
              KuraCell.identity(name: s.label, icon: Icons.event_seat_outlined),
              KuraCell.pill(_origen(e), muted: e == null),
              _mutedText(t, e?.grantType ?? '—'),
              _mutedText(t, _nameFor(e?.grantedBy)),
              _mutedText(t, _vigencia(e)),
              e == null
                  ? _mutedText(t, '—')
                  : KuraCell.progress(
                      used: used, total: contracted < 0 ? 0 : contracted),
              KuraCell.money(repo.unitAmountCents('seat', s.key, 'month')),
            ]);
          }(),
      ],
    );
  }

  Widget _whatPaysCard(
      BrandTokens t, List<OrgEntitlement> ents, DateFormat fmt) {
    final active = ents.where((e) => e.status == 'active').toList();
    final stripe = active.where((e) => e.source == 'stripe').length;
    final master = active.where((e) => e.source == 'master').length;
    // Próximo vencimiento: el más cercano con fecha (no permanente).
    DateTime? next;
    for (final e in active) {
      if (e.isPermanent) continue;
      final end = e.currentPeriodEnd;
      if (end == null) continue;
      if (next == null || end.isBefore(next)) next = end;
    }
    return Container(
      decoration: BoxDecoration(
        color: t.surface,
        border: Border.all(color: t.border),
        borderRadius: AppRadii.mdR,
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _kv(t, 'Stripe', '$stripe derecho${stripe == 1 ? '' : 's'} activo${stripe == 1 ? '' : 's'}'),
          const SizedBox(height: 8),
          _kv(t, 'A mano', '$master derecho${master == 1 ? '' : 's'} otorgado${master == 1 ? '' : 's'}'),
          const SizedBox(height: 8),
          _kv(
            t,
            'Próximo vencimiento',
            next == null
                ? '—'
                : '${fmt.format(next)} · al vencer, el módulo queda en solo lectura (no se oculta).',
          ),
          const SizedBox(height: 8),
          _kv(t, 'Solicitudes del centro', '—'),
        ],
      ),
    );
  }

  Widget _kv(BrandTokens t, String k, String v) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 170,
            child: Text(k,
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: t.textSecondary)),
          ),
          Expanded(
            child: Text(v,
                style: TextStyle(fontSize: 13, color: t.textPrimary)),
          ),
        ],
      );

  KuraCell _mutedText(BrandTokens t, String v) => KuraCell.custom(
        sortValue: v.toLowerCase(),
        build: (t) => Text(v,
            style: TextStyle(
                fontSize: 13,
                color: v == '—' ? t.textDisabled : t.textSecondary)),
      );

  /// Valor de lista al mes de lo otorgado A MANO y activo (lo condonado). null si
  /// no hay ninguno con precio en catálogo.
  int? _condonadoCents(List<OrgEntitlement> ents) {
    int sum = 0;
    var any = false;
    for (final e in ents) {
      if (e.source != 'master' || e.status != 'active') continue;
      final c = repo.unitAmountCents(e.kind, e.key, 'month');
      if (c != null) {
        sum += c;
        any = true;
      }
    }
    return any ? sum : null;
  }
}
