/// Formato de dinero en MXN (centavos → pesos). Vive en core para que los widgets
/// compartidos no dependan de una pantalla. Los montos del catálogo son centavos.
library;

String _grouped(int wholePesos) => wholePesos
    .toString()
    .replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (m) => ',');

/// "$1,200" si es peso entero; "$1,234.50" si trae centavos. Para precios de
/// licencia (enteros) sale sin decimales.
String pesosFromCents(int cents) {
  final whole = cents ~/ 100;
  final frac = cents % 100;
  final s = _grouped(whole);
  return frac == 0 ? '\$$s' : '\$$s.${frac.toString().padLeft(2, '0')}';
}

/// Siempre con dos decimales ("$1,104.00") — para las celdas de dinero de una
/// tabla, donde la precisión de la moneda es la regla.
String moneyMXN(int cents) {
  final whole = cents ~/ 100;
  final frac = cents % 100;
  return '\$${_grouped(whole)}.${frac.toString().padLeft(2, '0')}';
}

/// Un monto ausente (null) se pinta "—", nunca "$0": un ausente no es un cero.
String moneyOrDash(int? cents) => cents == null ? '—' : pesosFromCents(cents);
