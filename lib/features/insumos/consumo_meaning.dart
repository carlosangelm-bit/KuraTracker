/// Helpers puros de la cifra "Consumo del mes" del Inventario. Viven aparte de la
/// pantalla (sin dependencias de Flutter) para poder probarse en local: la regla
/// del canvas es que la cifra NUNCA va sola — siempre sale con su línea de
/// comparación contra el mes anterior.
library;

const kSpanishMonths = [
  'enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio',
  'julio', 'agosto', 'septiembre', 'octubre', 'noviembre', 'diciembre',
];

String spanishMonth(int month) => kSpanishMonths[(month - 1) % 12];

/// Línea de "qué significa" de la cifra de consumo. SIEMPRE compara contra el mes
/// anterior. Sin consumo el mes anterior (`prev == 0`) no hay contra qué comparar:
/// se dice explícito, nunca se calcula un porcentaje contra cero ni se muestra la
/// cifra sola.
String consumoMeaning({
  required int current,
  required int prev,
  required String prevLabel,
}) {
  if (prev == 0) {
    return current == 0
        ? 'sin salidas registradas este mes'
        : 'sin $prevLabel para comparar';
  }
  final pct = ((current - prev) / prev * 100).round();
  // Signo menos tipográfico (−) para bajadas, como el canvas.
  final arrow = pct >= 0 ? '+$pct' : '−${-pct}';
  return '$arrow% contra $prevLabel';
}
