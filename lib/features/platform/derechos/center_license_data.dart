import '../../../models/module_key.dart';
import '../../../models/org_entitlement.dart';
import '../../../services/data_repository.dart';
import 'module_agreement.dart';

/// Traducción del grant_type a español para la UI (hoy sale el valor crudo de la
/// base, sin acento). Un solo lugar. null / desconocido → "—".
String grantTypeLabel(String? raw) {
  switch (raw) {
    case 'comercial':
      return 'Acuerdo comercial';
    case 'cortesia':
      return 'Cortesía';
    default:
      return '—';
  }
}

/// La línea de MOTIVO que va bajo el nombre del módulo (§5.2, canvas): entre
/// comillas, solo en filas otorgadas a mano (source='master') y con motivo real.
/// Devuelve null cuando no hay que mostrar nada — así una fila de Stripe no pinta
/// comillas vacías.
String? moduleReasonLine(OrgEntitlement? e) {
  if (e == null || e.source != 'master') return null;
  final reason = e.reason?.trim();
  if (reason == null || reason.isEmpty) return null;
  return '"$reason"';
}

/// Una fila del grupo Módulos con su comparación derecho×interruptor ya resuelta.
class ModuleLicenseRow {
  final String key;
  final String label;
  final OrgEntitlement? ent;
  final bool hasRight;
  final bool hasSwitch; // tiene interruptor propio (module_settings)
  final bool switchOn;
  final ModuleAgreement agreement;
  final int? amountCents;

  const ModuleLicenseRow({
    required this.key,
    required this.label,
    required this.ent,
    required this.hasRight,
    required this.hasSwitch,
    required this.switchOn,
    required this.agreement,
    required this.amountCents,
  });
}

/// Descriptor de un módulo de pago del panel.
/// - [switchKey] != null: interruptor propio = module_settings de ese ModuleKey.
/// - [seatDerived] true: no tiene module_settings, pero su "encendido" se DERIVA de
///   los asientos (0119 deriva module:clinico de seat:clinico). Existe el estado
///   "con asientos, sin module:clinico" y debe verse en rojo.
/// - ninguno: sin interruptor ni derivación (admin) → el interruptor sigue al derecho.
class _ModuleDesc {
  final String key;
  final String label;
  final ModuleKey? switchKey;
  final bool seatDerived;
  // Copy propio para el caso rojo (encendido sin derecho). module:clinico habla de
  // ASIENTOS, no de interruptor, porque su "encendido" se deriva de los asientos.
  final String? onWithoutRightMessage;
  const _ModuleDesc(this.key, this.label,
      {this.switchKey, this.seatDerived = false, this.onWithoutRightMessage});
}

const _moduleDescriptors = <_ModuleDesc>[
  // module:clinico PRIMERO: es el derecho que exigen 0115 y canWriteModule para todo
  // el expediente; 0119 lo deriva de los asientos.
  _ModuleDesc('clinico', 'Clínico (expediente)',
      seatDerived: true,
      onWithoutRightMessage:
          'Con asientos activos pero sin el derecho clínico: nadie ve el expediente.'),
  _ModuleDesc('admin', 'Administración avanzada'),
  _ModuleDesc('insumos', 'Insumos', switchKey: ModuleKey.insumos),
  _ModuleDesc('comercial', 'Comercial', switchKey: ModuleKey.comercial),
];

bool _centerSwitch(DataRepository repo, String orgId, ModuleKey m) {
  final ct = repo.centerTypeFor(orgId);
  for (final s in repo.listModuleSettings(organizationId: orgId)) {
    if (s.moduleKey == m.dbValue && s.siteId == null && s.profileId == null) {
      return s.enabled;
    }
  }
  return m.defaultFor(ct);
}

/// Las filas del grupo Módulos, con el acuerdo derecho×interruptor por fila. Vive
/// aparte de la pantalla (sin widgets) para probar la conducta: quitar la fila de
/// module:clinico deja de pintar su caso rojo y la prueba cae.
List<ModuleLicenseRow> moduleLicenseRows(DataRepository repo, String orgId) {
  final ents = repo.entitlementsFor(orgId);
  OrgEntitlement? entOf(String key) {
    for (final e in ents) {
      if (e.kind == 'module' && e.key == key) return e;
    }
    return null;
  }

  return [
    for (final d in _moduleDescriptors)
      () {
        final e = entOf(d.key);
        final hasRight = e != null && e.status == 'active';
        final hasSwitch = d.switchKey != null;
        final bool switchOn;
        if (hasSwitch) {
          switchOn = _centerSwitch(repo, orgId, d.switchKey!);
        } else if (d.seatDerived) {
          // "Encendido" = el centro tiene asientos clínicos activos (el expediente
          // está en uso), aunque module:clinico esté cancelado.
          switchOn = repo.hasSeatEntitlement(orgId, 'clinico');
        } else {
          switchOn = hasRight; // admin: sin interruptor propio, nunca desacuerdo falso
        }
        return ModuleLicenseRow(
          key: d.key,
          label: d.label,
          ent: e,
          hasRight: hasRight,
          hasSwitch: hasSwitch,
          switchOn: switchOn,
          agreement: moduleAgreement(
            hasRight: hasRight,
            switchOn: switchOn,
            onWithoutRightMessage: d.onWithoutRightMessage,
          ),
          amountCents: repo.unitAmountCents('module', d.key, 'month'),
        );
      }(),
  ];
}
