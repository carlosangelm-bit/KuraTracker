import 'package:flutter/material.dart';

/// Puntos de quiebre de layout de la app (Flutter Web + móvil). Antes cada
/// pantalla los hardcodeaba inline; centralizarlos permite un comportamiento
/// consistente entre pantallas.
abstract class Breakpoints {
  /// Rail vs. barra inferior (coincide con AppShell) y umbral general "ancho".
  static const double wide = 900;

  /// Reflow de tarjetas: 2 columnas a partir de aquí.
  static const double twoCol = 900;

  /// Reflow de tarjetas: 3 columnas a partir de aquí.
  static const double threeCol = 1400;

  /// Maestro-detalle (lista + detalle lado a lado) a partir de aquí.
  static const double twoPane = 1050;

  /// Ancho cómodo de lectura para formularios/listas de texto.
  static const double reading = 760;
}

/// Reparte una lista de "bloques" (tarjetas/secciones) en 1/2/3 columnas según
/// el ancho disponible, con distribución round-robin para balancear la altura.
/// Es la palanca principal para que el desktop APROVECHE el ancho en pantallas
/// con muchas tarjetas (en vez de estirarlas en una sola columna).
class ResponsiveColumns extends StatelessWidget {
  final List<Widget> blocks;
  final double columnSpacing;
  final double blockSpacing;
  final double twoColMin;
  final double threeColMin;

  const ResponsiveColumns({
    super.key,
    required this.blocks,
    this.columnSpacing = 20,
    this.blockSpacing = 20,
    this.twoColMin = Breakpoints.twoCol,
    this.threeColMin = Breakpoints.threeCol,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final w = c.maxWidth;
        final cols = w < twoColMin ? 1 : (w < threeColMin ? 2 : 3);
        if (cols == 1) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < blocks.length; i++) ...[
                if (i > 0) SizedBox(height: blockSpacing),
                blocks[i],
              ],
            ],
          );
        }
        final columns = List.generate(cols, (_) => <Widget>[]);
        for (var i = 0; i < blocks.length; i++) {
          columns[i % cols].add(blocks[i]);
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var ci = 0; ci < cols; ci++) ...[
              if (ci > 0) SizedBox(width: columnSpacing),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var bi = 0; bi < columns[ci].length; bi++) ...[
                      if (bi > 0) SizedBox(height: blockSpacing),
                      columns[ci][bi],
                    ],
                  ],
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

/// Centra el contenido con un ancho máximo cómodo de lectura. Para pantallas de
/// formulario o listas de texto que, sin acotar, se ven "alargadas" a todo el
/// ancho en desktop. Reemplaza los `ConstrainedBox`/`Center` ad-hoc repartidos
/// por la app.
class PageMaxWidth extends StatelessWidget {
  final Widget child;
  final double maxWidth;
  final EdgeInsetsGeometry? padding;

  const PageMaxWidth({
    super.key,
    required this.child,
    this.maxWidth = Breakpoints.reading,
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: padding != null ? Padding(padding: padding!, child: child) : child,
      ),
    );
  }
}

/// Rail de secciones (maestro) para pantallas con pestañas: en desktop
/// reemplaza el TabBar horizontal por una lista vertical a la izquierda, con el
/// contenido de la sección (detalle) a la derecha. Aprovecha el ancho. Se
/// desplaza si hay muchas secciones y la pantalla es corta.
class SectionRail extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final List<(IconData, String)> destinations;

  const SectionRail({
    super.key,
    required this.selectedIndex,
    required this.onSelected,
    required this.destinations,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) => SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: c.maxHeight),
          child: IntrinsicHeight(
            child: NavigationRail(
              selectedIndex: selectedIndex,
              onDestinationSelected: onSelected,
              labelType: NavigationRailLabelType.all,
              groupAlignment: -1,
              destinations: [
                for (final d in destinations)
                  NavigationRailDestination(
                      icon: Icon(d.$1), label: Text(d.$2)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Layout maestro-detalle: en ancho ≥ [breakpoint] muestra la lista [master] a
/// la izquierda (ancho fijo [masterWidth]) y el [detail] a la derecha; en móvil
/// muestra solo [master] (la navegación al detalle la maneja la pantalla, p. ej.
/// empujando una ruta). Así el desktop usa el ancho con dos paneles reales.
class TwoPane extends StatelessWidget {
  final Widget master;
  final Widget detail;
  final double breakpoint;
  final double masterWidth;
  final double divider;

  const TwoPane({
    super.key,
    required this.master,
    required this.detail,
    this.breakpoint = Breakpoints.twoPane,
    this.masterWidth = 360,
    this.divider = 1,
  });

  /// True si en este ancho se muestran los dos paneles (útil para que la
  /// pantalla decida navegar por ruta vs. seleccionar en el panel).
  static bool isWide(BuildContext context) =>
      MediaQuery.of(context).size.width >= Breakpoints.twoPane;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        if (c.maxWidth < breakpoint) return master;
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(width: masterWidth, child: master),
            VerticalDivider(width: divider, thickness: divider),
            Expanded(child: detail),
          ],
        );
      },
    );
  }
}
