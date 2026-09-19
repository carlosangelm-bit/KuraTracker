/// Regla ÚNICA del precio de venta de un insumo (spec 19-sep, Carlos). TODAS las puertas por las
/// que un insumo entra o cambia de precio —alta manual, edición, CSV (alta y re-subida), tienda
/// desde Inventario, sync de Shopify, seed de la demo— pasan por aquí, para que ninguna deje un
/// insumo con costo y sin precio en silencio.
///
/// Regla: si viene precio, ese (el centro lo capturó); si no y hay costo > 0, el DEFAULT
/// `costo / 0.75` (margen del 25 % sobre el precio de venta), redondeado a 2 decimales; si no hay
/// ninguno, `null` = SIN PRECIO (se marca y se cobra a costo, dicho en voz alta — nunca $0 mudo).
/// El default es punto de partida: el centro edita sus precios y su valor a mano NUNCA se pisa.
library;

/// Divisor del margen: `costo / 0.75` = costo × 1.333… (el costo es el 75 % del precio de venta).
const double kSalePriceMarginDivisor = 0.75;

/// Precio de venta resuelto según la regla única. `null` = el insumo queda SIN PRECIO.
double? resolveSalePrice({double? price, double? cost}) {
  if (price != null) return price;
  if (cost != null && cost > 0) {
    return double.parse((cost / kSalePriceMarginDivisor).toStringAsFixed(2));
  }
  return null;
}

/// El default derivado SOLO del costo (para el autocompletado de los formularios): costo / 0.75,
/// o null si no hay costo utilizable.
double? defaultSalePriceFromCost(double? cost) => resolveSalePrice(cost: cost);

/// Precio con el que queda un insumo que YA existe tras re-subir un CSV. El precio capturado a mano
/// NUNCA se pisa (Carlos, 19-sep): si la fila trae precio, ese manda (el CSV también es captura); si
/// no trae precio, se RESPETA el precio existente; y solo cuando el insumo no tenía precio se DERIVA
/// del costo (el de la fila, o en su defecto el existente). Así un reabasto por CSV —costos, sin
/// columna de precio— no borra en silencio los precios que el centro ajustó a mano.
double? salePriceOnCsvReupload({
  double? rowPrice,
  double? rowCost,
  double? existingPrice,
  double? existingCost,
}) {
  if (rowPrice != null) return rowPrice;
  if (existingPrice != null) return existingPrice;
  return resolveSalePrice(cost: rowCost ?? existingCost);
}
