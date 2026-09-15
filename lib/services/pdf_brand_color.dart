import 'package:pdf/pdf.dart';

import '../core/design/tokens.dart';
import '../models/center_type.dart';

/// Color de marca para los PDF que se entregan al paciente (reporte de herida,
/// referencia, reporte de prevención). UN solo lugar para los tres generadores, en vez
/// de un literal repetido en cada uno.
///
/// Usa el color guardado del centro si es legible; si NO hay color guardado o es
/// ilegible, cae en el `brandPrimary` del PROPIO tipo de centro
/// ([BrandTokens.forCenterType], que no necesita BuildContext), no en un violeta fijo.
/// Así un hospital que nunca entró a Marca entrega sus documentos en azul, y cuidadores
/// en rosa — la misma marca que la pantalla de Marca le promete.
PdfColor brandPdfColor(String? savedHex, CenterType centerType) {
  final parsed = _parseHex(savedHex);
  if (parsed != null) return parsed;
  return PdfColor.fromInt(
      BrandTokens.forCenterType(centerType).brandPrimary.value);
}

/// Parsea `#RRGGBB` o `#AARRGGBB` (con o sin `#`). Devuelve null si falta o es ilegible
/// —longitud u dígitos inválidos— para que el llamador caiga en la marca del centro.
PdfColor? _parseHex(String? hex) {
  if (hex == null) return null;
  var h = hex.trim().replaceAll('#', '');
  if (h.isEmpty) return null;
  if (h.length == 6) h = 'FF$h';
  if (h.length != 8) return null;
  final v = int.tryParse(h, radix: 16);
  return v == null ? null : PdfColor.fromInt(v);
}
