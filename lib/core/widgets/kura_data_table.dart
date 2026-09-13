

import 'package:flutter/material.dart';

import '../design/tints.dart';
import '../design/tokens.dart';
import 'dashed_border_box.dart';

/// El color de una celda numérica VIVE EN EL DATO, no en la fila: existencia ≤0
/// peligro, ≤ umbral aviso, si no éxito. La fila nunca se tiñe entera.
enum KuraCellStatus { none, danger, warning, success }

Color _statusColor(BrandTokens t, KuraCellStatus s) {
  switch (s) {
    case KuraCellStatus.none:
      return t.textPrimary;
    case KuraCellStatus.danger:
      return t.statusDanger;
    case KuraCellStatus.warning:
      return t.statusWarning;
    case KuraCellStatus.success:
      return t.statusSuccess;
  }
}

String _group(int n) => n
    .abs()
    .toString()
    .replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (m) => ',');

/// Definición de columna: ancho (fijo o flexible), alineación (numérica = derecha),
/// y si ordena al tocar el encabezado.
class KuraColumn {
  final String label;
  final double? width; // null = flexible
  final bool numeric; // derecha + cifras tabulares
  final bool sortable;
  const KuraColumn({
    required this.label,
    this.width,
    this.numeric = false,
    this.sortable = false,
  });
}

/// Una celda. Se construye por fábrica según su tipo; lleva su `sortValue` para que
/// el encabezado pueda ordenar por ella.
class KuraCell {
  final Comparable<dynamic>? sortValue;
  final Widget Function(BrandTokens t) builder;
  const KuraCell._(this.sortValue, this.builder);

  /// Texto a la izquierda (13px textPrimary).
  factory KuraCell.text(String value) => KuraCell._(
        value.toLowerCase(),
        (t) => Text(value,
            style: TextStyle(fontSize: 13, color: t.textPrimary)),
      );

  /// Celda de IDENTIDAD (primera columna): cuadro/avatar 30×30 + nombre y, debajo,
  /// SOLO el identificador (proveedor, folio, SKU, correo). radius 7 cosas, 30 personas.
  factory KuraCell.identity({
    required String name,
    String? identifier,
    String? initials,
    IconData? icon,
    bool person = false,
  }) =>
      KuraCell._(
        name.toLowerCase(),
        (t) => Row(
          children: [
            Container(
              width: 30,
              height: 30,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: t.chipBg,
                borderRadius: BorderRadius.circular(person ? 30 : 7),
              ),
              child: icon != null
                  ? Icon(icon, size: 16, color: t.brandPrimary)
                  : Text(
                      initials ?? _autoInitials(name),
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: AppType.bold,
                          color: t.brandPrimary),
                    ),
            ),
            const SizedBox(width: 11),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(name,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: AppType.semibold,
                          color: t.textPrimary)),
                  if (identifier != null)
                    Text(identifier,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 11, color: t.textDisabled)),
                ],
              ),
            ),
          ],
        ),
      );

  /// Número a la derecha con cifras tabulares y su unidad al lado (11px textDisabled).
  /// El color lo decide `status` (vive en el dato).
  factory KuraCell.number(
    num value, {
    String? unit,
    KuraCellStatus status = KuraCellStatus.none,
    int decimals = 0,
  }) {
    final text = decimals > 0
        ? value.toStringAsFixed(decimals)
        : (value < 0 ? '-' : '') + _group(value.round());
    return KuraCell._(
      value,
      (t) => Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.end,
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Text(text,
              style: TextStyle(
                  fontSize: 13,
                  color: _statusColor(t, status),
                  fontFeatures: const [FontFeature.tabularFigures()])),
          if (unit != null) ...[
            const SizedBox(width: 3),
            Text(unit,
                style: TextStyle(fontSize: 11, color: t.textDisabled)),
          ],
        ],
      ),
    );
  }

  /// Dinero a la derecha, dos decimales ("$1,104.00"), cifras tabulares.
  factory KuraCell.money(int cents, {KuraCellStatus status = KuraCellStatus.none}) {
    final whole = _group(cents ~/ 100);
    final frac = (cents.abs() % 100).toString().padLeft(2, '0');
    final text = '${cents < 0 ? '-' : ''}\$$whole.$frac';
    return KuraCell._(
      cents,
      (t) => Text(text,
          textAlign: TextAlign.right,
          style: TextStyle(
              fontSize: 13,
              color: _statusColor(t, status),
              fontFeatures: const [FontFeature.tabularFigures()])),
    );
  }

  /// Pastilla de celda (origen, estado, rol). Normal: chipBg. Atenuada: fondo
  /// background + borde punteado.
  factory KuraCell.pill(String label, {bool muted = false}) => KuraCell._(
        label.toLowerCase(),
        (t) {
          final content = Padding(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
            child: Text(label,
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: AppType.bold,
                    color: muted ? t.textSecondary : t.textPrimary)),
          );
          if (muted) {
            return Align(
              alignment: Alignment.centerLeft,
              child: DashedBorderBox(
                color: t.border,
                radius: AppRadii.pill,
                fill: t.background,
                child: content,
              ),
            );
          }
          return Align(
            alignment: Alignment.centerLeft,
            child: Container(
              decoration: BoxDecoration(
                  color: t.chipBg, borderRadius: AppRadii.pillR),
              child: content,
            ),
          );
        },
      );

  static String _autoInitials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '?';
    if (parts.length == 1) return parts.first.characters.first.toUpperCase();
    return (parts.first.characters.first + parts[1].characters.first)
        .toUpperCase();
  }
}

/// Una fila: su `id` (para selección) y sus celdas (una por columna).
class KuraRow {
  final Object id;
  final List<KuraCell> cells;
  const KuraRow({required this.id, required this.cells});
}

/// Tabla de datos (canvas §1). Columnas con ancho y alineación declarados,
/// ordenamiento por encabezado, zebra, celda de identidad, pastilla, selección
/// múltiple opcional (con casilla en el encabezado que marca todas) y fila de
/// totales opcional. Los números van a la derecha con cifras tabulares. Todo color
/// sale de [BrandTokens]. Inventario la usa con totales y selección; Reportes con
/// selección sin totales; VAC sin ninguna.
class KuraDataTable extends StatefulWidget {
  final List<KuraColumn> columns;
  final List<KuraRow> rows;
  final List<KuraCell?>? totals; // fila de totales opcional (una celda por columna)
  final bool selectable;
  final Set<Object>? initiallySelected;
  final ValueChanged<Set<Object>>? onSelectionChanged;

  const KuraDataTable({
    super.key,
    required this.columns,
    required this.rows,
    this.totals,
    this.selectable = false,
    this.initiallySelected,
    this.onSelectionChanged,
  });

  @override
  State<KuraDataTable> createState() => _KuraDataTableState();
}

class _KuraDataTableState extends State<KuraDataTable> {
  int? _sortCol;
  bool _asc = true;
  late Set<Object> _selected =
      {...?widget.initiallySelected};

  List<KuraRow> get _sorted {
    if (_sortCol == null) return widget.rows;
    final col = _sortCol!;
    final rows = [...widget.rows];
    rows.sort((a, b) {
      final av = col < a.cells.length ? a.cells[col].sortValue : null;
      final bv = col < b.cells.length ? b.cells[col].sortValue : null;
      if (av == null && bv == null) return 0;
      if (av == null) return 1; // nulos al final
      if (bv == null) return -1;
      final c = Comparable.compare(av, bv);
      return _asc ? c : -c;
    });
    return rows;
  }

  void _onHeaderTap(int col) {
    setState(() {
      if (_sortCol == col) {
        _asc = !_asc;
      } else {
        _sortCol = col;
        _asc = true;
      }
    });
  }

  void _toggleAll(bool value) {
    setState(() {
      _selected = value ? {for (final r in widget.rows) r.id} : <Object>{};
    });
    widget.onSelectionChanged?.call({..._selected});
  }

  void _toggleRow(Object id, bool value) {
    setState(() {
      if (value) {
        _selected.add(id);
      } else {
        _selected.remove(id);
      }
    });
    widget.onSelectionChanged?.call({..._selected});
  }

  @override
  Widget build(BuildContext context) {
    final t = BrandTokens.of(context);
    final rows = _sorted;
    final allSelected =
        widget.rows.isNotEmpty && _selected.length == widget.rows.length;

    final columnWidths = <int, TableColumnWidth>{};
    var idx = 0;
    if (widget.selectable) {
      columnWidths[idx++] = const FixedColumnWidth(42);
    }
    for (final c in widget.columns) {
      columnWidths[idx++] = c.width != null
          ? FixedColumnWidth(c.width!)
          : const FlexColumnWidth();
    }

    return Table(
      columnWidths: columnWidths,
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      children: [
        _headerRow(t, allSelected),
        for (var i = 0; i < rows.length; i++) _dataRow(t, rows[i], i),
        if (widget.totals != null) _totalsRow(t),
      ],
    );
  }

  TableRow _headerRow(BrandTokens t, bool allSelected) {
    final cells = <Widget>[];
    if (widget.selectable) {
      cells.add(_cellPad(
        _Checkbox(
          key: const ValueKey('kura-header-checkbox'),
          value: allSelected,
          onChanged: (v) => _toggleAll(v),
          brand: t.brandPrimary,
          border: t.textDisabled,
          onBrand: t.onBrand,
        ),
        header: true,
      ));
    }
    for (var i = 0; i < widget.columns.length; i++) {
      final col = widget.columns[i];
      final active = _sortCol == i;
      final label = Text(
        col.label.toUpperCase(),
        style: TextStyle(
            fontSize: 11,
            fontWeight: AppType.extrabold,
            letterSpacing: 0.06 * 11,
            color: t.textSecondary),
      );
      final arrow = active
          ? Padding(
              padding: const EdgeInsets.only(left: 4),
              child: Icon(_asc ? Icons.arrow_upward : Icons.arrow_downward,
                  size: 12, color: t.brandPrimary),
            )
          : const SizedBox.shrink();
      final content = Row(
        mainAxisAlignment:
            col.numeric ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [Flexible(child: label), arrow],
      );
      cells.add(_cellPad(
        col.sortable
            ? InkWell(onTap: () => _onHeaderTap(i), child: content)
            : content,
        header: true,
      ));
    }
    return TableRow(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: t.border)),
      ),
      children: cells,
    );
  }

  TableRow _dataRow(BrandTokens t, KuraRow row, int index) {
    final zebra = index.isEven ? Tints.brand(t, 0.02) : t.surface;
    final cells = <Widget>[];
    if (widget.selectable) {
      cells.add(_cellPad(_Checkbox(
        value: _selected.contains(row.id),
        onChanged: (v) => _toggleRow(row.id, v),
        brand: t.brandPrimary,
        border: t.textDisabled,
        onBrand: t.onBrand,
      )));
    }
    for (var i = 0; i < widget.columns.length; i++) {
      final numeric = widget.columns[i].numeric;
      final cell = i < row.cells.length ? row.cells[i].builder(t) : const SizedBox.shrink();
      cells.add(_cellPad(Align(
        alignment: numeric ? Alignment.centerRight : Alignment.centerLeft,
        child: cell,
      )));
    }
    return TableRow(
      decoration: BoxDecoration(
        color: zebra,
        border: Border(bottom: BorderSide(color: Tints.hairline(t))),
      ),
      children: cells,
    );
  }

  TableRow _totalsRow(BrandTokens t) {
    final totals = widget.totals!;
    final cells = <Widget>[];
    if (widget.selectable) cells.add(const SizedBox.shrink());
    for (var i = 0; i < widget.columns.length; i++) {
      final numeric = widget.columns[i].numeric;
      final cell = i < totals.length ? totals[i] : null;
      cells.add(Padding(
        padding: const EdgeInsets.only(left: 12, right: 12, top: 14, bottom: 12),
        child: Align(
          alignment: numeric ? Alignment.centerRight : Alignment.centerLeft,
          child: cell == null
              ? const SizedBox.shrink()
              : DefaultTextStyle.merge(
                  style: TextStyle(
                      fontSize: numeric ? 15 : 12,
                      fontWeight: numeric ? AppType.extrabold : AppType.bold,
                      color: numeric ? t.textPrimary : t.textSecondary),
                  child: cell.builder(t),
                ),
        ),
      ));
    }
    return TableRow(children: cells);
  }

  Widget _cellPad(Widget child, {bool header = false}) => Padding(
        padding: header
            ? const EdgeInsets.only(left: 12, right: 12, bottom: 10)
            : const EdgeInsets.all(12),
        child: child,
      );
}

/// Casilla 17×17 del canvas. Apagada: radius 5, borde 1.5, blanco. Encendida:
/// brandPrimary + palomita blanca.
class _Checkbox extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;
  final Color brand;
  final Color border;
  final Color onBrand;
  const _Checkbox({
    super.key,
    required this.value,
    required this.onChanged,
    required this.brand,
    required this.border,
    required this.onBrand,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => onChanged(!value),
      borderRadius: BorderRadius.circular(5),
      child: Container(
        width: 17,
        height: 17,
        decoration: BoxDecoration(
          color: value ? brand : Colors.transparent,
          borderRadius: BorderRadius.circular(5),
          border: value ? null : Border.all(color: border, width: 1.5),
        ),
        child: value ? Icon(Icons.check, size: 11, color: onBrand) : null,
      ),
    );
  }
}
