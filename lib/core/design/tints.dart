import 'package:flutter/material.dart';

import 'tokens.dart';

/// Tintes DERIVADOS de los tokens (nunca hex sueltos). Las superficies teñidas del
/// canvas —zebra de tabla, banda de bloqueo, fondos de alarma— se calculan desde
/// [BrandTokens] para que sigan la MARCA del centro (hospital azul, cuidadores rosa)
/// en lugar de un morado fijo, y para que el estado (aviso/peligro) sea idéntico en
/// las tres marcas. Es la mitad del valor del sistema: cero literales de color.
class Tints {
  Tints._();

  /// Tinte de MARCA sobre `surface` (zebra, banda de bloqueo). `alpha` bajo.
  static Color brand(BrandTokens t, double alpha) =>
      Color.alphaBlend(t.brandPrimary.withValues(alpha: alpha), t.surface);

  /// Tinte de un color de ESTADO sobre una base (fondos de alarma / cuadros de ícono).
  static Color status(Color state, Color over, double alpha) =>
      Color.alphaBlend(state.withValues(alpha: alpha), over);

  /// Borde teñido de un estado (más presente que el fondo, sin ser sólido).
  static Color statusBorder(Color state, Color over, double alpha) =>
      Color.alphaBlend(state.withValues(alpha: alpha), over);

  /// Línea fina más clara que `border` (separador de celda de tabla).
  static Color hairline(BrandTokens t) =>
      Color.alphaBlend(t.border.withValues(alpha: 0.55), t.surface);

  /// Tono OSCURO de un estado (texto legible sobre su tinte): acerca el estado al
  /// texto primario. `amount` = cuánto oscurece (0 = el estado puro).
  static Color darkTone(BrandTokens t, Color state, double amount) =>
      Color.alphaBlend(t.textPrimary.withValues(alpha: amount), state);
}
