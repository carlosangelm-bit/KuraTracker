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
/// [onWithoutRightMessage] y [rightOffMessage] permiten texto propio por fila para
/// los dos casos de desacuerdo: el "interruptor" no es igual en todos los módulos
/// (module:clinico se "enciende" por asientos, no por un switch), así que su copy
/// debe hablar de asientos, en ambas direcciones.
ModuleAgreement moduleAgreement({
  required bool hasRight,
  required bool switchOn,
  String? onWithoutRightMessage,
  String? rightOffMessage,
}) {
  if (hasRight && switchOn) {
    return const ModuleAgreement(ModuleAgreementCase.normal, 'Activo');
  }
  if (hasRight && !switchOn) {
    return ModuleAgreement(ModuleAgreementCase.rightOff,
        rightOffMessage ?? 'Con derecho, apagado en el centro.');
  }
  if (!hasRight && switchOn) {
    return ModuleAgreement(
        ModuleAgreementCase.onWithoutRight,
        onWithoutRightMessage ??
            'Encendido en el centro, pero sin derecho: nadie lo ve.');
  }
  return const ModuleAgreement(ModuleAgreementCase.noRight, 'Sin derecho');
}

/// El MOTIVO bajo el nombre del módulo: línea COMPLETA, sin ellipsis. La fila de la
/// tabla crece para mostrarlo entero (nunca se trunca). Color textSecondary desde
/// [BrandTokens]. Ligera para probarse sola.
class ModuleReasonText extends StatelessWidget {
  final String text;
  const ModuleReasonText(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    final t = BrandTokens.of(context);
    return Text(
      text,
      softWrap: true, // sin maxLines ni overflow ellipsis: se ve completo
      style: TextStyle(fontSize: 11, color: t.textSecondary, height: 1.35),
    );
  }
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
