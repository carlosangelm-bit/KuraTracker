import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../core/theme/kura_theme.dart';

/// Un valor por mes (para las barras mensuales).
class MonthValue {
  final String label; // 'ene', 'feb'…
  final double value;
  const MonthValue(this.label, this.value);
}

/// Una rebanada de dona (con su color y etiqueta).
class DonutSlice {
  final String label;
  final double value;
  final Color color;
  const DonutSlice(this.label, this.value, this.color);
}

/// Tarjeta con una gráfica de barras mensual (p. ej. consumo o ingresos).
class MonthlyBarChart extends StatelessWidget {
  final String title;
  final List<MonthValue> data;
  final Color color;
  final String Function(double)? valueLabel;
  final Widget? headerTrailing;
  const MonthlyBarChart({
    super.key,
    required this.title,
    required this.data,
    this.color = KuraColors.primary,
    this.valueLabel,
    this.headerTrailing,
  });

  @override
  Widget build(BuildContext context) {
    final maxV = data.fold<double>(0, (a, m) => m.value > a ? m.value : a);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                    child: Text(title,
                        style: const TextStyle(fontWeight: FontWeight.w700))),
                if (headerTrailing != null) headerTrailing!,
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 160,
              child: maxV <= 0
                  ? const Center(child: Text('Sin datos en el periodo.'))
                  : BarChart(
                      BarChartData(
                        alignment: BarChartAlignment.spaceAround,
                        maxY: maxV * 1.25,
                        gridData: const FlGridData(show: false),
                        borderData: FlBorderData(show: false),
                        // Sin tooltip por defecto (el fondo/texto verde no se leía).
                        barTouchData: BarTouchData(enabled: false),
                        titlesData: FlTitlesData(
                          leftTitles: const AxisTitles(
                              sideTitles: SideTitles(showTitles: false)),
                          rightTitles: const AxisTitles(
                              sideTitles: SideTitles(showTitles: false)),
                          topTitles: const AxisTitles(
                              sideTitles: SideTitles(showTitles: false)),
                          bottomTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              reservedSize: 34,
                              getTitlesWidget: (value, meta) {
                                final i = value.toInt();
                                if (i < 0 || i >= data.length) {
                                  return const SizedBox.shrink();
                                }
                                final v = data[i].value;
                                return Padding(
                                  padding: const EdgeInsets.only(top: 6),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(data[i].label,
                                          style: const TextStyle(
                                              fontSize: 10,
                                              color: KuraColors.darkText)),
                                      if (v > 0)
                                        Text(
                                          valueLabel?.call(v) ?? '${v.toInt()}',
                                          style: TextStyle(
                                              fontSize: 9,
                                              fontWeight: FontWeight.w700,
                                              color: color),
                                        ),
                                    ],
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                        barGroups: [
                          for (var i = 0; i < data.length; i++)
                            BarChartGroupData(x: i, barRods: [
                              BarChartRodData(
                                toY: data[i].value,
                                color: color,
                                width: 16,
                                borderRadius:
                                    const BorderRadius.vertical(top: Radius.circular(4)),
                              ),
                            ]),
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Tarjeta con una gráfica de dona + leyenda (p. ej. estado del inventario).
class DonutCard extends StatelessWidget {
  final String title;
  final List<DonutSlice> slices;
  const DonutCard({super.key, required this.title, required this.slices});

  @override
  Widget build(BuildContext context) {
    final total = slices.fold<double>(0, (a, s) => a + s.value);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            if (total <= 0)
              const SizedBox(
                  height: 140, child: Center(child: Text('Sin datos.')))
            else
              Row(
                children: [
                  SizedBox(
                    width: 140,
                    height: 140,
                    child: PieChart(
                      PieChartData(
                        sectionsSpace: 2,
                        centerSpaceRadius: 36,
                        sections: [
                          for (final s in slices)
                            if (s.value > 0)
                              PieChartSectionData(
                                value: s.value,
                                color: s.color,
                                title: '${s.value.toInt()}',
                                radius: 26,
                                titleStyle: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white),
                              ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final s in slices)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 3),
                            child: Row(
                              children: [
                                Container(
                                    width: 10,
                                    height: 10,
                                    decoration: BoxDecoration(
                                        color: s.color, shape: BoxShape.circle)),
                                const SizedBox(width: 8),
                                Expanded(
                                    child: Text(s.label,
                                        style: const TextStyle(fontSize: 12))),
                                Text('${s.value.toInt()}',
                                    style: const TextStyle(
                                        fontSize: 12, fontWeight: FontWeight.w700)),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

/// Utilidad: etiqueta corta de mes en español desde un DateTime.
const kMonthShort = ['ene', 'feb', 'mar', 'abr', 'may', 'jun', 'jul', 'ago', 'sep', 'oct', 'nov', 'dic'];
