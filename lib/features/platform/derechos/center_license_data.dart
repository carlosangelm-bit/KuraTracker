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
  final bool seatDerived; // su "encendido" se deriva de los asientos (clínico)
  final ModuleAgreement agreement;
  final int? amountCents;

  const ModuleLicenseRow({
    required this.key,
    required this.label,
    required this.ent,
    required this.hasRight,
    required this.hasSwitch,
    required this.switchOn,
    required this.seatDerived,
    required this.agreement,
    required this.amountCents,
  });
}

/// Cuenta de DESACUERDOS (derecho ≠ interruptor) para la cifra del panel. Excluye
/// las filas seatDerived: su "desacuerdo" (Clínico sin asientos) ya se cuenta como
/// falta de asientos en el grupo Asientos; contarlo aquí sería doble.
int disagreementCount(List<ModuleLicenseRow> rows) => rows
    .where((r) =>
        !r.seatDerived &&
        (r.agreement.kind == ModuleAgreementCase.rightOff ||
            r.agreement.kind == ModuleAgreementCase.onWithoutRight))
    .length;

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
  // Copy propio para los dos casos de desacuerdo. module:clinico habla de ASIENTOS,
  // no de interruptor, porque su "encendido" se deriva de los asientos.
  final String? onWithoutRightMessage; // caso rojo: encendido sin derecho
  final String? rightOffMessage; // caso ámbar: con derecho, apagado
  const _ModuleDesc(this.key, this.label,
      {this.switchKey,
      this.seatDerived = false,
      this.onWithoutRightMessage,
      this.rightOffMessage});
}

const _moduleDescriptors = <_ModuleDesc>[
  // module:clinico PRIMERO: es el derecho que exigen 0115 y canWriteModule para todo
  // el expediente; 0119 lo deriva de los asientos.
  _ModuleDesc('clinico', 'Clínico (expediente)',
      seatDerived: true,
      onWithoutRightMessage:
          'Con asientos activos pero sin el derecho clínico: nadie ve el expediente.',
      rightOffMessage: 'Sin asientos clínicos: nadie puede usar el expediente.'),
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
          seatDerived: d.seatDerived,
          agreement: moduleAgreement(
            hasRight: hasRight,
            switchOn: switchOn,
            onWithoutRightMessage: d.onWithoutRightMessage,
            rightOffMessage: d.rightOffMessage,
          ),
          amountCents: repo.unitAmountCents('module', d.key, 'month'),
        );
      }(),
  ];
}

/// "Origen" de un centro (§5.1, columna): de dónde vienen sus derechos ACTIVOS.
/// Vive aquí, no en la pantalla de Centros, para que Centros y Licencia no discrepen
/// sobre el mismo centro.
enum CenterOrigin { none, stripe, master, mixed }

CenterOrigin centerOrigin(DataRepository repo, String orgId) {
  final sources = repo
      .entitlementsFor(orgId)
      .where((e) => e.status == 'active')
      .map((e) => e.source)
      .toSet();
  final stripe = sources.contains('stripe');
  final master = sources.contains('master');
  if (stripe && master) return CenterOrigin.mixed;
  if (stripe) return CenterOrigin.stripe;
  if (master) return CenterOrigin.master;
  return CenterOrigin.none;
}

String centerOriginLabel(CenterOrigin o) => switch (o) {
      CenterOrigin.stripe => 'Stripe',
      CenterOrigin.master => 'A mano',
      CenterOrigin.mixed => 'Mixto',
      CenterOrigin.none => '—',
    };

/// "Requiere atención" (§5.1): el vencimiento más próximo a menos de 30 días, o un
/// desacuerdo derecho↔interruptor. Vacío → "—", nunca una fila inventada. Deriva de las
/// MISMAS primitivas que el panel de Licencia (entitlementsFor + disagreementCount).
class CenterAttention {
  /// Días desde el vencimiento pasado más reciente, si HAY un derecho activo ya vencido
  /// (el centro está en solo lectura por tiempo). Tiene prioridad sobre "vence pronto".
  final int? expiredDays;
  final int? expiresInDays; // vencimiento activo más próximo, si < 30 días
  final int disagreements;
  const CenterAttention(
      {this.expiredDays, this.expiresInDays, required this.disagreements});
  bool get isExpired => expiredDays != null;
  bool get any => expiredDays != null || expiresInDays != null || disagreements > 0;
}

CenterAttention centerAttention(DataRepository repo, String orgId, {DateTime? now}) {
  final ref = now ?? DateTime.now();
  int? soonestFuture;
  int? mostRecentPast; // días desde el vencimiento pasado más reciente
  for (final e in repo.entitlementsFor(orgId).where((e) => e.status == 'active')) {
    final end = e.currentPeriodEnd;
    if (end == null) continue;
    if (end.isBefore(ref)) {
      // Derecho activo ya vencido → centro en solo lectura (canWriteModule exige
      // end.isAfter(now)). No se salta: es LA condición que más pide atención.
      final past = ref.difference(end).inDays;
      if (mostRecentPast == null || past < mostRecentPast) mostRecentPast = past;
    } else {
      final days = end.difference(ref).inDays;
      if (days < 30 && (soonestFuture == null || days < soonestFuture)) {
        soonestFuture = days;
      }
    }
  }
  return CenterAttention(
    expiredDays: mostRecentPast,
    expiresInDays: soonestFuture,
    disagreements: disagreementCount(moduleLicenseRows(repo, orgId)),
  );
}

/// Prioridad: vencido → vence en <30 → desacuerdos → "—".
String centerAttentionLabel(CenterAttention a) {
  if (a.expiredDays != null) {
    return a.expiredDays == 0 ? 'En solo lectura' : 'Venció hace ${a.expiredDays} d';
  }
  if (a.expiresInDays != null) return 'Vence en ${a.expiresInDays} d';
  if (a.disagreements > 0) {
    return '${a.disagreements} desacuerdo${a.disagreements == 1 ? '' : 's'}';
  }
  return '—';
}

/// Una fila del grupo Asientos. Su "acuerdo" es coherente con Módulos: un derecho de
/// asiento ACTIVO pero con cantidad 0 no habilita nada → ámbar "Derecho sin
/// asientos" (misma regla que usa hasSeatEntitlement / el interruptor derivado del
/// Clínico), no un derecho normal.
class SeatLicenseRow {
  final String key;
  final String label;
  final OrgEntitlement? ent;
  final bool hasAsientos; // activo y cantidad >= 1
  final int used;
  final int contracted;
  final ModuleAgreement agreement;
  final int? amountCents;

  const SeatLicenseRow({
    required this.key,
    required this.label,
    required this.ent,
    required this.hasAsientos,
    required this.used,
    required this.contracted,
    required this.agreement,
    required this.amountCents,
  });
}

const _seatDescriptors = <({String key, String label})>[
  (key: 'clinico', label: 'Asientos clínicos'),
  (key: 'protocolo', label: 'Protocolo Kura+'),
];

List<SeatLicenseRow> seatLicenseRows(DataRepository repo, String orgId) {
  final ents = repo.entitlementsFor(orgId);
  final summary = repo.licenseSummaryFor(orgId);
  OrgEntitlement? seatOf(String key) {
    for (final e in ents) {
      if (e.kind == 'seat' && e.key == key) return e;
    }
    return null;
  }

  return [
    for (final d in _seatDescriptors)
      () {
        final e = seatOf(d.key);
        final active = e != null && e.status == 'active';
        final qty = e?.quantity ?? 0;
        final hasAsientos = active && qty >= 1;
        final counter =
            d.key == 'clinico' ? summary.clinicalSeats : summary.protocolo;
        final ModuleAgreement agreement;
        if (!active) {
          agreement =
              const ModuleAgreement(ModuleAgreementCase.noRight, 'Sin derecho');
        } else if (qty >= 1) {
          agreement =
              const ModuleAgreement(ModuleAgreementCase.normal, 'Activo');
        } else {
          // Derecho ACTIVO con cantidad 0: no habilita nada. Ámbar, como Módulos.
          agreement = const ModuleAgreement(
              ModuleAgreementCase.rightOff, 'Derecho sin asientos');
        }
        return SeatLicenseRow(
          key: d.key,
          label: d.label,
          ent: e,
          hasAsientos: hasAsientos,
          used: counter.used,
          contracted: e?.quantity ?? counter.contracted,
          agreement: agreement,
          amountCents: repo.unitAmountCents('seat', d.key, 'month'),
        );
      }(),
  ];
}
