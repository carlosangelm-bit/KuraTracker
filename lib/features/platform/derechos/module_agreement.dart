import 'package:flutter/material.dart';

import '../../../core/design/tokens.dart';

/// Los cuatro casos de la comparación DERECHO × INTERRUPTOR de un módulo (§5.2).
enum ModuleAgreementCase { normal, rightOff, onWithoutRight, noRight }

class ModuleAgreement {
  final ModuleAgreementCase kind;
  final String message;
  const ModuleAgreement(this.kind, this.message);
}

/// La regla que JUSTIFICA la pantalla Centro · Licencia (§5.2): por cada módulo se
/// comparan el DERECHO (org_entitlements) y el INTERRUPTOR (module_settings del
/// centro) y salen cuatro casos. El tercero —encendido en el centro pero SIN
/// derecho— es la razón de ser del rediseño: hoy 0115 exime al master, así que el
/// interruptor puede quedar encendido sin derecho y, bajo el AND, "nadie lo ve".
/// Sin este caso a la vista, el rediseño entero se cae solo.
ModuleAgreement moduleAgreement({
  required bool hasRight,
  required bool switchOn,
}) {
  if (hasRight && switchOn) {
    return const ModuleAgreement(ModuleAgreementCase.normal, 'Activo');
  }
  if (hasRight && !switchOn) {
    return const ModuleAgreement(
        ModuleAgreementCase.rightOff, 'Con derecho, apagado en el centro.');
  }
  if (!hasRight && switchOn) {
    return const ModuleAgreement(ModuleAgreementCase.onWithoutRight,
        'Encendido en el centro, pero sin derecho: nadie lo ve.');
  }
  return const ModuleAgreement(ModuleAgreementCase.noRight, 'Sin derecho');
}

/// Etiqueta de estado del módulo: el mensaje del caso con SU color, todo desde
/// [BrandTokens] (incluidos statusWarningText/statusSuccessText de la etapa 1; el
/// rojo es statusDanger, que sí tiene contraste como texto). Ligera a propósito
/// —solo material + tokens— para montarse en un widget test sin las dependencias
/// pesadas de la pantalla.
class ModuleAgreementLabel extends StatelessWidget {
  final ModuleAgreement agreement;
  const ModuleAgreementLabel(this.agreement, {super.key});

  static Color colorFor(BrandTokens t, ModuleAgreementCase kind) {
    switch (kind) {
      case ModuleAgreementCase.normal:
        return t.statusSuccessText;
      case ModuleAgreementCase.rightOff:
        return t.statusWarningText;
      case ModuleAgreementCase.onWithoutRight:
        return t.statusDanger;
      case ModuleAgreementCase.noRight:
        return t.textDisabled;
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = BrandTokens.of(context);
    return Text(
      agreement.message,
      style: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w700,
        color: colorFor(t, agreement.kind),
      ),
    );
  }
}
