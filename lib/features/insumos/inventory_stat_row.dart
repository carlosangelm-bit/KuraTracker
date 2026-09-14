import 'package:flutter/material.dart';

import '../../core/format/money.dart';
import '../../core/widgets/kura_stat.dart';
import 'consumo_meaning.dart';

/// Fila de las cuatro cifras del Inventario (canvas §"Fila de cifras"). Vive en su
/// propio archivo LIGERO (sin las dependencias pesadas de la pantalla) para poder
/// montarse en un widget test local: así la invocación de "Consumo del mes" se
/// prueba por CONDUCTA (el render trae la comparación), no solo la función pura.
///
/// "Consumo del mes" recibe las piezas del mes en curso y del anterior y arma su
/// línea de comparación con [consumoMeaning] AQUÍ: quitar esa línea deja la cifra
/// sin comparación y el widget test se pone en rojo.
class InventoryStatRow extends StatelessWidget {
  final int articleCount;
  final int reorderCount; // bajo umbral + agotados
  final int outCount; // agotados
  final int valueCents; // valor a costo (existencia × costo)
  final int consumoCurrent; // piezas consumidas este mes
  final int consumoPrev; // piezas consumidas el mes anterior
  final String prevMonthLabel; // nombre del mes anterior

  const InventoryStatRow({
    super.key,
    required this.articleCount,
    required this.reorderCount,
    required this.outCount,
    required this.valueCents,
    required this.consumoCurrent,
    required this.consumoPrev,
    required this.prevMonthLabel,
  });

  @override
  Widget build(BuildContext context) {
    final stats = <Widget>[
      KuraStat(
        label: 'Artículos',
        value: '$articleCount',
        meaning: 'en esta sede',
      ),
      KuraStat(
        label: 'Por reordenar',
        value: '$reorderCount',
        meaning: 'bajo su umbral · $outCount agotados',
        tone: reorderCount > 0 ? KuraStatTone.warning : KuraStatTone.normal,
      ),
      KuraStat(
        label: 'Valor a costo',
        value: pesosFromCents(valueCents),
        meaning: 'MXN · existencia × costo',
      ),
      KuraStat(
        label: 'Consumo del mes',
        value: '$consumoCurrent',
        unit: 'pz',
        meaning: consumoMeaning(
          current: consumoCurrent,
          prev: consumoPrev,
          prevLabel: prevMonthLabel,
        ),
      ),
    ];
    return LayoutBuilder(
      builder: (context, c) {
        // Cuatro en fila cuando cabe; se envuelven en dos si no.
        final narrow = c.maxWidth < 720;
        final w = narrow ? (c.maxWidth - 16) / 2 : (c.maxWidth - 3 * 16) / 4;
        return Wrap(
          spacing: 16,
          runSpacing: 16,
          children: [for (final s in stats) SizedBox(width: w, child: s)],
        );
      },
    );
  }
}
