import 'package:flutter/material.dart';

import '../../../services/data_repository.dart';
import 'center_license_data.dart';
import 'grant_entitlement_dialog.dart';

/// Implementación del `MasterGrantLauncher` (la regla del master). Abre
/// [GrantEntitlementDialog] PRESELECCIONADO al módulo que le falta al centro
/// (initialTarget), con los demás módulos disponibles en el desplegable por si el master
/// quiere otorgar otro de paso. El master captura el MOTIVO (el razonamiento del acto —
/// que otorgar es un acto de dinero/propiedad, que hay cortesías, que el motivo distingue
/// una prueba corta de un acuerdo real— vive en el diálogo, no se le pregunta de nuevo).
/// Otorga vía `masterGrantEntitlement`; sus errores ya vienen traducidos del repo.
/// Devuelve true si se otorgó.
Future<bool> launchMasterGrant(
  BuildContext context, {
  required DataRepository repo,
  required String organizationId,
  required String moduleKey,
  required String moduleName,
}) async {
  final targets = <GrantTarget>[
    for (final r in moduleLicenseRows(repo, organizationId))
      GrantTarget(
        kind: 'module',
        key: r.key,
        label: r.label,
        monthlyCents: r.amountCents,
      ),
  ];
  // El módulo que disparó el candado va PRESELECCIONADO. Si por lo que sea no está en
  // la lista de módulos, se arma a mano y se antepone (nunca abrir sin preselección).
  var initial = targets.firstWhere(
    (g) => g.key == moduleKey,
    orElse: () => GrantTarget(
      kind: 'module',
      key: moduleKey,
      label: moduleName,
      monthlyCents: repo.unitAmountCents('module', moduleKey, 'month'),
    ),
  );
  if (!targets.any((g) => g.key == initial.key)) targets.insert(0, initial);

  final ok = await showDialog<bool>(
    context: context,
    builder: (_) => GrantEntitlementDialog(
      targets: targets,
      initialTarget: initial,
      onSubmit: ({
        required target,
        required grantType,
        required reason,
        quantity,
        until,
        required permanent,
      }) async {
        await repo.masterGrantEntitlement(
          organizationId: organizationId,
          kind: target.kind,
          key: target.key,
          quantity: quantity,
          grantType: grantType,
          reason: reason,
          until: until,
          permanent: permanent,
        );
      },
    ),
  );
  return ok == true;
}
