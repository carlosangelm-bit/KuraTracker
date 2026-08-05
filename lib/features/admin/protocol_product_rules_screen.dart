import 'package:flutter/material.dart';

import '../../core/theme/kura_theme.dart';
import '../../engine/models/kura_engine_enums.dart';
import '../../models/inventory.dart';
import '../../models/note_option_catalog.dart';
import '../../models/protocol_product_rule.dart';
import '../../services/data_repository.dart';

/// Configuración del vínculo PROTOCOLO → PRODUCTO por MEDIDA (0076). Por cada
/// categoría del protocolo (KuraTag), el admin define reglas que resuelven el
/// producto concreto y su cantidad según el área/volumen de la herida.
class ProtocolProductRulesScreen extends StatefulWidget {
  final DataRepository repo;
  final String? organizationId;
  const ProtocolProductRulesScreen({
    super.key,
    required this.repo,
    required this.organizationId,
  });
  @override
  State<ProtocolProductRulesScreen> createState() =>
      _ProtocolProductRulesScreenState();
}

class _ProtocolProductRulesScreenState
    extends State<ProtocolProductRulesScreen> {
  // Categorías con producto asociado (educación no lleva insumo cobrable).
  static const _categories = [
    KuraTag.limpieza,
    KuraTag.desbridamiento,
    KuraTag.rellenoCavidad,
    KuraTag.aposito,
    KuraTag.proteccionPiel,
    KuraTag.antimicrobiano,
    KuraTag.compresion,
    KuraTag.descarga,
  ];

  DataRepository get repo => widget.repo;
  String? get orgId => widget.organizationId;

  String _money(double v) => '\$${v.toStringAsFixed(2)}';

  String _fmtNum(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);

  String _exudateShort(String name) => switch (name) {
        'ninguno' => 'nulo',
        'escaso' => 'escaso',
        'moderado' => 'mod',
        'abundante' => 'abund',
        _ => name,
      };

  String _ruleSummary(ProtocolProductRule r) {
    final parts = <String>[];
    switch (r.dimension) {
      case RuleDimension.area:
        parts.add('Área ${_range(r)} cm²');
        break;
      case RuleDimension.volume:
        parts.add('Volumen ${_range(r)} cm³');
        break;
      case RuleDimension.none:
        parts.add('Siempre');
        break;
    }
    if (r.exudateLevels.isNotEmpty) {
      parts.add('Exud: ${r.exudateLevels.map((e) => _exudateShort(e)).join('/')}');
    }
    if (r.zoneGroups.isNotEmpty) {
      parts.add('Zona: ${r.zoneGroups.map(ZoneGroup.label).join('/')}');
    }
    if (r.infection == RuleInfection.yes) parts.add('c/infección');
    if (r.infection == RuleInfection.no) parts.add('s/infección');
    parts.add(switch (r.quantityMode) {
      QuantityMode.perArea => '${_fmtNum(r.quantityValue)}/cm²',
      QuantityMode.perVolume => '${_fmtNum(r.quantityValue)}/cm³',
      QuantityMode.fixed => '×${_fmtNum(r.quantityValue)}',
    });
    return parts.join(' · ');
  }

  String _range(ProtocolProductRule r) {
    final lo = r.minValue == null ? '0' : _fmtNum(r.minValue!);
    final hi = r.maxValue == null ? '∞' : _fmtNum(r.maxValue!);
    return '$lo–$hi';
  }

  @override
  Widget build(BuildContext context) {
    final allRules = orgId == null
        ? <ProtocolProductRule>[]
        : repo.listProtocolProductRules(orgId);
    final byCat = <String, List<ProtocolProductRule>>{};
    for (final r in allRules) {
      byCat.putIfAbsent(r.category, () => []).add(r);
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Productos del protocolo')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
        children: [
          Text(
            'Por cada paso del protocolo, define qué producto de tu inventario se '
            'usa y en qué cantidad. Puedes condicionarlo a la MEDIDA de la herida '
            '(p. ej. tamaño de apósito por área, relleno por volumen). Cuando el '
            'motor sugiera ese paso, la consulta resolverá el producto según la '
            'medición.',
            style: TextStyle(
                fontSize: 12, color: KuraColors.darkText.withValues(alpha: 0.6)),
          ),
          const SizedBox(height: 16),
          for (final cat in _categories)
            _categoryCard(cat, byCat[cat.dbValue] ?? const []),
        ],
      ),
    );
  }

  Widget _categoryCard(KuraTag cat, List<ProtocolProductRule> rules) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(cat.label,
                      style: const TextStyle(
                          fontWeight: FontWeight.w800, fontSize: 15)),
                ),
                TextButton.icon(
                  onPressed: () => _editRule(cat, null),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Regla'),
                ),
              ],
            ),
            if (rules.isEmpty)
              Padding(
                padding: const EdgeInsets.only(left: 2, bottom: 4),
                child: Text('Sin productos configurados.',
                    style: TextStyle(
                        fontSize: 12,
                        color: KuraColors.darkText.withValues(alpha: 0.5))),
              )
            else
              for (final r in rules)
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 2),
                  dense: true,
                  title: Text(r.name ?? 'Producto',
                      style: const TextStyle(fontSize: 14)),
                  subtitle: Text(_ruleSummary(r),
                      style: TextStyle(
                          fontSize: 12,
                          color: KuraColors.darkText.withValues(alpha: 0.6))),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(Icons.edit_outlined, size: 18),
                        onPressed: () => _editRule(cat, r),
                      ),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(Icons.delete_outline, size: 18),
                        onPressed: () async {
                          await repo.deleteProtocolProductRule(r.id);
                          if (mounted) setState(() {});
                        },
                      ),
                    ],
                  ),
                ),
          ],
        ),
      ),
    );
  }

  Future<void> _editRule(KuraTag cat, ProtocolProductRule? existing) async {
    if (orgId == null) return;
    final inventory =
        repo.listInventoryItems(organizationId: orgId).toList();
    if (inventory.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('No hay productos en el inventario del centro.')));
      return;
    }
    final saved = await showModalBottomSheet<ProtocolProductRule>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _RuleEditor(
        orgId: orgId!,
        category: cat,
        inventory: inventory,
        existing: existing,
        money: _money,
      ),
    );
    if (saved != null) {
      await repo.saveProtocolProductRule(saved);
      if (mounted) setState(() {});
    }
  }
}

/// Editor de una regla (producto + dimensión + rango + cantidad).
class _RuleEditor extends StatefulWidget {
  final String orgId;
  final KuraTag category;
  final List<InventoryItem> inventory;
  final ProtocolProductRule? existing;
  final String Function(double) money;
  const _RuleEditor({
    required this.orgId,
    required this.category,
    required this.inventory,
    required this.existing,
    required this.money,
  });
  @override
  State<_RuleEditor> createState() => _RuleEditorState();
}

class _RuleEditorState extends State<_RuleEditor> {
  InventoryItem? _item;
  RuleDimension _dimension = RuleDimension.none;
  QuantityMode _qtyMode = QuantityMode.fixed;
  final _minCtrl = TextEditingController();
  final _maxCtrl = TextEditingController();
  final _qtyCtrl = TextEditingController(text: '1');
  // Condiciones (0077)
  final Set<String> _exudate = {};
  final Set<String> _zones = {};
  RuleInfection _infection = RuleInfection.any;

  static const _exudateLabels = {
    'ninguno': 'Ninguno',
    'escaso': 'Escaso',
    'moderado': 'Moderado',
    'abundante': 'Abundante',
  };

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    if (e != null) {
      _item = widget.inventory.where((i) => i.id == e.inventoryItemId).isNotEmpty
          ? widget.inventory.firstWhere((i) => i.id == e.inventoryItemId)
          : null;
      _dimension = e.dimension;
      _qtyMode = e.quantityMode;
      if (e.minValue != null) _minCtrl.text = _fmt(e.minValue!);
      if (e.maxValue != null) _maxCtrl.text = _fmt(e.maxValue!);
      _qtyCtrl.text = _fmt(e.quantityValue);
      _exudate.addAll(e.exudateLevels);
      _zones.addAll(e.zoneGroups);
      _infection = e.infection;
    }
  }

  static String _fmt(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();

  @override
  void dispose() {
    _minCtrl.dispose();
    _maxCtrl.dispose();
    _qtyCtrl.dispose();
    super.dispose();
  }

  double? _num(TextEditingController c) => c.text.trim().isEmpty
      ? null
      : double.tryParse(c.text.trim().replaceAll(',', '.'));

  void _save() {
    if (_item == null) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Elige un producto.')));
      return;
    }
    final qty = _num(_qtyCtrl) ?? 1;
    final rule = ProtocolProductRule(
      id: widget.existing?.id ?? '',
      organizationId: widget.orgId,
      category: widget.category.dbValue,
      inventoryItemId: _item!.id,
      name: _item!.name,
      dimension: _dimension,
      minValue: _dimension == RuleDimension.none ? null : _num(_minCtrl),
      maxValue: _dimension == RuleDimension.none ? null : _num(_maxCtrl),
      quantityMode: _qtyMode,
      quantityValue: qty,
      sortOrder: widget.existing?.sortOrder ?? 0,
      exudateLevels: _exudate.toList(),
      zoneGroups: _zones.toList(),
      infection: _infection,
      priority: widget.existing?.priority ?? 0,
    );
    Navigator.of(context).pop(rule);
  }

  Future<void> _pickProduct() async {
    final picked = await showModalBottomSheet<InventoryItem>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _InventorySearchSheet(
        items: widget.inventory,
        money: widget.money,
      ),
    );
    if (picked != null) setState(() => _item = picked);
  }

  @override
  Widget build(BuildContext context) {
    final measured = _dimension != RuleDimension.none;
    final unit = _dimension == RuleDimension.volume ? 'cm³' : 'cm²';
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 4,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${widget.category.label} · regla de producto',
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            const SizedBox(height: 12),

            // Producto (buscador con escritura)
            InputDecorator(
              decoration: const InputDecoration(
                  labelText: 'Producto del inventario', isDense: true),
              child: InkWell(
                onTap: _pickProduct,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          _item == null
                              ? 'Buscar producto…'
                              : '${_item!.name}  ·  ${widget.money(_item!.unitPrice ?? _item!.unitCost ?? 0)}',
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: _item == null
                                ? KuraColors.darkText.withValues(alpha: 0.5)
                                : KuraColors.darkText,
                          ),
                        ),
                      ),
                      const Icon(Icons.search, size: 20),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // ---- Condiciones (opcionales) ----
            Text('Condiciones (opcional — vacío = cualquiera)',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: KuraColors.primary)),
            const SizedBox(height: 8),
            Text('Exudado',
                style: TextStyle(
                    fontSize: 12,
                    color: KuraColors.darkText.withValues(alpha: 0.7))),
            const SizedBox(height: 4),
            Wrap(
              spacing: 6,
              children: [
                for (final e in ExudadoCantidad.values)
                  FilterChip(
                    label: Text(_exudateLabels[e.name] ?? e.name),
                    selected: _exudate.contains(e.name),
                    onSelected: (sel) => setState(() {
                      if (sel) {
                        _exudate.add(e.name);
                      } else {
                        _exudate.remove(e.name);
                      }
                    }),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Text('Zona anatómica',
                style: TextStyle(
                    fontSize: 12,
                    color: KuraColors.darkText.withValues(alpha: 0.7))),
            const SizedBox(height: 4),
            Wrap(
              spacing: 6,
              children: [
                for (final z in ZoneGroup.all)
                  FilterChip(
                    label: Text(ZoneGroup.label(z)),
                    selected: _zones.contains(z),
                    onSelected: (sel) => setState(() {
                      if (sel) {
                        _zones.add(z);
                      } else {
                        _zones.remove(z);
                      }
                    }),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Text('Infección / riesgo',
                style: TextStyle(
                    fontSize: 12,
                    color: KuraColors.darkText.withValues(alpha: 0.7))),
            const SizedBox(height: 4),
            Wrap(
              spacing: 6,
              children: [
                for (final inf in RuleInfection.values)
                  ChoiceChip(
                    label: Text(inf.label),
                    selected: _infection == inf,
                    onSelected: (_) => setState(() => _infection = inf),
                  ),
              ],
            ),
            const SizedBox(height: 16),

            // Dimensión
            Text('¿Depende de la medida de la herida?',
                style: TextStyle(
                    fontSize: 12,
                    color: KuraColors.darkText.withValues(alpha: 0.7))),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              children: [
                for (final d in RuleDimension.values)
                  ChoiceChip(
                    label: Text(d.label),
                    selected: _dimension == d,
                    onSelected: (_) => setState(() {
                      _dimension = d;
                      // Alinea el modo de cantidad con la dimensión por defecto.
                      if (d == RuleDimension.area &&
                          _qtyMode == QuantityMode.perVolume) {
                        _qtyMode = QuantityMode.fixed;
                      }
                      if (d == RuleDimension.volume &&
                          _qtyMode == QuantityMode.perArea) {
                        _qtyMode = QuantityMode.fixed;
                      }
                      if (d == RuleDimension.none) _qtyMode = QuantityMode.fixed;
                    }),
                  ),
              ],
            ),
            if (measured) ...[
              const SizedBox(height: 12),
              Text('Rango de ${_dimension.label.toLowerCase()} '
                  '(deja vacío para sin límite)',
                  style: TextStyle(
                      fontSize: 12,
                      color: KuraColors.darkText.withValues(alpha: 0.7))),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _minCtrl,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(
                          labelText: 'Mín', suffixText: unit, isDense: true),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _maxCtrl,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(
                          labelText: 'Máx', suffixText: unit, isDense: true),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 14),

            // Cantidad
            Row(
              children: [
                Expanded(
                  flex: 2,
                  child: DropdownButtonFormField<QuantityMode>(
                    value: _qtyMode,
                    isExpanded: true,
                    decoration: const InputDecoration(
                        labelText: 'Cantidad', isDense: true),
                    items: [
                      for (final m in QuantityMode.values)
                        DropdownMenuItem(value: m, child: Text(m.label)),
                    ],
                    onChanged: (v) =>
                        setState(() => _qtyMode = v ?? QuantityMode.fixed),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _qtyCtrl,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                        labelText: 'Valor', isDense: true),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              _qtyMode == QuantityMode.fixed
                  ? 'Se usa esa cantidad fija por sesión.'
                  : 'La cantidad = valor × ${_qtyMode == QuantityMode.perArea ? 'área (cm²)' : 'volumen (cm³)'} de la herida.',
              style: TextStyle(
                  fontSize: 11, color: KuraColors.darkText.withValues(alpha: 0.5)),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _save,
                child: const Text('Guardar regla'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Hoja de búsqueda de producto del inventario: escribe para filtrar.
class _InventorySearchSheet extends StatefulWidget {
  final List<InventoryItem> items;
  final String Function(double) money;
  const _InventorySearchSheet({required this.items, required this.money});
  @override
  State<_InventorySearchSheet> createState() => _InventorySearchSheetState();
}

class _InventorySearchSheetState extends State<_InventorySearchSheet> {
  String _q = '';
  @override
  Widget build(BuildContext context) {
    final q = _q.trim().toLowerCase();
    final filtered = q.isEmpty
        ? widget.items
        : widget.items
            .where((i) => i.name.toLowerCase().contains(q))
            .toList();
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 4,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Buscar producto',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
          const SizedBox(height: 8),
          TextField(
            autofocus: true,
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText: 'Escribe el nombre…',
              isDense: true,
            ),
            onChanged: (v) => setState(() => _q = v),
          ),
          const SizedBox(height: 8),
          ConstrainedBox(
            constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.5),
            child: filtered.isEmpty
                ? const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Center(child: Text('Sin resultados.')),
                  )
                : ListView.builder(
                    shrinkWrap: true,
                    itemCount: filtered.length,
                    itemBuilder: (_, i) {
                      final it = filtered[i];
                      return ListTile(
                        dense: true,
                        title: Text(it.name),
                        subtitle: Text(
                            widget.money(it.unitPrice ?? it.unitCost ?? 0)),
                        onTap: () => Navigator.of(context).pop(it),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
