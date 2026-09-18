import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/session_provider.dart';
import '../../core/design/tokens.dart';
import '../../core/widgets/kura_module_lock.dart';
import '../../models/inventory.dart';
import '../../models/note_option_catalog.dart';
import '../../models/protocol_product_rule.dart';
import '../../services/data_repository.dart';
import 'protocol_product_rules_screen.dart';

/// La Matriz del protocolo (§15 etapa 6). UNA pantalla, tres estados por permiso:
///  · AUTORA (current_user_can_author_catalog: admin del centro con protocol:author, o master) →
///    edita el CATÁLOGO Kura+ y ata identidades contra product_catalog en vivo.
///  · con módulo sin autoría → sus reglas PROPIAS.
///  · sin permiso → se DICE, no se deja en blanco.
///
/// La cabecera muestra —y, para master, cambia EN VIVO— con qué régimen resuelve el centro
/// (el interruptor del desacople). Es el guion de la presentación: atar, prender, y ver el
/// régimen cambiar en las pantallas clínicas, desde aquí mismo.
class ProtocolMatrixScreen extends ConsumerStatefulWidget {
  final DataRepository repo;
  final String? organizationId;
  const ProtocolMatrixScreen(
      {required this.repo, required this.organizationId, super.key});

  @override
  ConsumerState<ProtocolMatrixScreen> createState() =>
      _ProtocolMatrixScreenState();
}

// Etiquetas legibles de contexto (TOP-LEVEL: las comparte la tabla y el editor de reglas).
// Los valores crudos vienen del catálogo (Excel); el texto es el del DOMINIO (mismas palabras
// de las pantallas clínicas), no inventado. Un valor sin mapa cae a su forma cruda (visible,
// para cazarlo), no a un guion bajo silencioso.
const _ctxKindLabel = {
  'etiologia': 'Etiología',
  'piel': 'Piel',
  'evolucion': 'Evolución',
};
const _ctxValueLabel = {
  'lpp': 'Lesión por presión (LPP)',
  'pie_diabetico': 'Pie diabético',
  'quemaduras': 'Quemaduras',
  'quirurgica': 'Quirúrgica',
  'insuf_venosa': 'Insuficiencia venosa',
  'desgarro': 'Desgarro cutáneo',
  'dai': 'DAI (dermatitis asociada a incontinencia)',
  'marsi': 'MARSI (lesión por adhesivos)',
  'mdrpi': 'MDRPI (lesión por dispositivo médico)',
  'seguimiento': 'Seguimiento',
};

class _ProtocolMatrixScreenState extends ConsumerState<ProtocolMatrixScreen> {
  // Reflejo local del interruptor tras un cambio de master, para que se vea al instante (la
  // hidratación de la org llega después; la RPC ya actualizó la base que leen las clínicas).
  bool? _switchOverride;
  bool _flipping = false;
  // Filtros (§presentación): con 35 reglas, 17 solo en apósito, recorrer a scroll no se sostiene
  // en vivo. Se filtra por PASO (categoría) y por CONTEXTO.
  String? _catFilter; // KuraTag.dbValue | null = todos
  String? _ctxFilter; // context_value | null = todos

  DataRepository get repo => widget.repo;
  String? get org => widget.organizationId;

  bool get _resolvesFromCatalog =>
      _switchOverride ?? repo.resolvesFromCatalog(org);

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(sessionProvider).user;
    final isMaster = user?.isMaster ?? false;
    final isAdmin = user?.isAdmin ?? false;
    // Candado COMERCIAL (module:admin), como todas las pantallas hijas de /admin: gate del CENTRO,
    // va antes de la autoría. PERO el MASTER lo TRASCIENDE (coherente con 0012: ve y gestiona todos
    // los centros) — y aquí es imperativo: el interruptor de fuente de resolución es EXCLUSIVO de
    // master y vive DENTRO de esta pantalla; sin esta excepción, el único que puede accionarlo sería
    // el único que no puede abrirla. Orden: master pasa siempre → si no, sin módulo → bloqueo con
    // precio. La enumeración en admin_gated_screens_lock_test exige AMBAS caras (sin módulo y sin
    // master → bloqueo; master → NO bloqueo).
    if (!isMaster && !repo.premiumAdminFor(org)) {
      return adminModuleLockedBody(
          repo: repo,
          organizationId: org,
          description:
              'Edita el régimen por paso y contexto, y ata cada uno al producto de tu centro.');
    }

    final canAuthor = repo.canAuthorProtocolCatalog(
        organizationId: org, isAdmin: isAdmin, isMaster: isMaster);

    // Módulo SIN autoría: reglas propias del centro. Se delega al editor existente (ahora también
    // un cuerpo sin Scaffold) para no perder la EDICIÓN de reglas propias. La unificación total de
    // ese modo dentro de la Matriz queda como seguimiento; el foco de esta etapa es el catálogo.
    if (!canAuthor && isAdmin) {
      return ProtocolProductRulesScreen(repo: repo, organizationId: org);
    }

    // CUERPO (sin Scaffold): vive DENTRO del shell de /admin; el título ('Matriz del
    // protocolo') y el riel los pone el shell.
    return canAuthor ? _catalogView(isMaster) : _noPermission();
  }

  // ------------------------------------------------------------------ AUTORA
  Widget _catalogView(bool isMaster) {
    final all = repo.listProtocolCatalogRules();
    // "Atado" = tiene insumo del centro (inventory_item_id), NO par shopify.
    final atadas = all.where((r) => r.isBound).length;
    // Atadas a un insumo EXTERNO (sin par shopify): el catálogo Kura+ NO puede
    // actualizarlas. Se cuenta para que armar el protocolo entero sobre externos sea una
    // decisión VISIBLE del centro, no una sorpresa a seis meses (condición de Carlos).
    final externas = all.where((r) => r.isBound && !r.hasIdentity).length;

    // Filtrado. El contexto disponible depende del paso elegido (para no ofrecer valores vacíos).
    final catPool = all
        .where((r) => _catFilter == null || r.category == _catFilter)
        .toList();
    final shown = catPool
        .where((r) => _ctxFilter == null || r.contextValue == _ctxFilter)
        .toList();
    // Agrupado por paso (categoría) para que se lea como matriz, no como lista corrida.
    final byCat = <String, List<ProtocolProductRule>>{};
    for (final r in shown) {
      byCat.putIfAbsent(r.category, () => []).add(r);
    }
    final cats = byCat.keys.toList()..sort();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _switchHeader(isMaster),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: Text(
                  'Catálogo Kura+ · $atadas de ${all.length} reglas con insumo atado'
                  '${externas > 0 ? ' · $externas a insumo externo (no se actualiza por catálogo)' : ''}',
                  style: TextStyle(
                      fontSize: 12,
                      color: BrandTokens.of(context).textSecondary)),
            ),
            FilledButton.icon(
              onPressed: () => _openRuleForm(),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Nueva regla'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _filters(all, catPool),
        const SizedBox(height: 12),
        if (shown.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Text('No hay reglas para ese filtro.'),
          )
        else
          // Tabla: la vista se recorre por COLUMNA. Scroll horizontal si no cabe (nunca desborda
          // el body). El contexto manda —es lo que identifica una regla dentro de un paso—; el
          // producto es la respuesta, va después.
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            // Ancho FIJO para que los Expanded (flex de columna) tengan un ancho acotado; se hace
            // más ancho que la pantalla en móvil → scroll horizontal, sin desbordar el body.
            child: SizedBox(
              width: (MediaQuery.of(context).size.width - 32)
                  .clamp(880.0, double.infinity),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _headerRow(),
                  const Divider(height: 1),
                  for (final c in cats) ...[
                    _categoryBand(c, byCat[c]!.length),
                    for (final r in byCat[c]!) _dataRow(r),
                  ],
                ],
              ),
            ),
          ),
      ],
    );
  }

  // -------- filtros por paso y por contexto --------
  Widget _filters(List<ProtocolProductRule> all, List<ProtocolProductRule> catPool) {
    final cats = (all.map((r) => r.category).toSet().toList())..sort();
    final ctxs = (catPool
        .map((r) => r.contextValue)
        .whereType<String>()
        .toSet()
        .toList())
      ..sort();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(spacing: 6, runSpacing: 4, children: [
          _chip('Todos los pasos', _catFilter == null,
              () => setState(() => _catFilter = null)),
          for (final c in cats)
            _chip(_catLabel(c), _catFilter == c, () {
              setState(() {
                _catFilter = c;
                _ctxFilter = null; // el contexto depende del paso
              });
            }),
        ]),
        if (ctxs.isNotEmpty) ...[
          const SizedBox(height: 6),
          Wrap(spacing: 6, runSpacing: 4, children: [
            _chip('Todo contexto', _ctxFilter == null,
                () => setState(() => _ctxFilter = null)),
            for (final v in ctxs)
              _chip(_ctxValueLabel[v] ?? v, _ctxFilter == v,
                  () => setState(() => _ctxFilter = v)),
          ]),
        ],
      ],
    );
  }

  Widget _chip(String label, bool selected, VoidCallback onTap) => ChoiceChip(
        label: Text(label, style: const TextStyle(fontSize: 12)),
        selected: selected,
        onSelected: (_) => onTap(),
      );

  String _catLabel(String category) {
    final tag = KuraTag.values.where((t) => t.dbValue == category);
    return tag.isEmpty ? category : tag.first.label;
  }

  // -------- tabla: encabezado, banda de paso, fila de datos --------
  // Pesos de columna, compartidos por encabezado y filas para que alineen.
  static const _wCtx = 3, _wScale = 3, _wNote = 3, _wProd = 3, _wQty = 1, _wId = 3;

  Widget _cell(Widget child, int flex) =>
      Expanded(flex: flex, child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
          child: child));

  Widget _hCell(String t, int flex) => _cell(
      Text(t,
          style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: BrandTokens.of(context).textSecondary)),
      flex);

  Widget _headerRow() => Row(children: [
        _hCell('CONTEXTO', _wCtx),
        _hCell('ESCALA · DISPARADOR', _wScale),
        _hCell('FRASE PARA LA NOTA', _wNote),
        _hCell('PRODUCTO · MARCA', _wProd),
        _hCell('CANT.', _wQty),
        _hCell('IDENTIDAD', _wId),
      ]);

  Widget _categoryBand(String category, int n) => Container(
        width: double.infinity,
        color: BrandTokens.of(context).chipBg,
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        child: Text('${_catLabel(category)}  ·  $n',
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
      );

  Widget _switchHeader(bool isMaster) {
    final catalog = _resolvesFromCatalog;
    final color = catalog ? BrandTokens.of(context).brandPrimary : BrandTokens.of(context).statusWarning;
    return Card(
      color: color.withValues(alpha: 0.06),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(catalog ? Icons.verified : Icons.folder_outlined,
                    size: 20, color: color),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Este centro resuelve el protocolo con:',
                          style: TextStyle(fontSize: 12)),
                      Text(
                        catalog
                            ? 'Catálogo Kura+'
                            : 'Reglas propias del centro',
                        style: TextStyle(
                            fontWeight: FontWeight.w800, color: color),
                      ),
                    ],
                  ),
                ),
                if (isMaster)
                  _flipping
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : Switch(value: catalog, onChanged: _flipSwitch),
              ],
            ),
            if (isMaster) ...[
              const SizedBox(height: 4),
              Text(
                catalog
                    ? 'Cámbialo para que vuelva a resolver con sus reglas propias.'
                    : 'Atá las identidades y, cuando esté listo, prendé el catálogo: el régimen '
                        'cambia en las pantallas clínicas al instante.',
                style: TextStyle(
                    fontSize: 11,
                    color: BrandTokens.of(context).textSecondary),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _flipSwitch(bool on) async {
    if (org == null) return;
    setState(() => _flipping = true);
    try {
      await repo.setOrgResolvesFromCatalog(org!, on);
      if (!mounted) return;
      setState(() {
        _switchOverride = on; // evidente al instante
        _flipping = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(on
              ? 'Ahora el centro resuelve con el catálogo Kura+.'
              : 'Ahora el centro resuelve con sus reglas propias.')));
    } catch (e) {
      if (!mounted) return;
      setState(() => _flipping = false);
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No se pudo cambiar el régimen.')));
    }
  }

  String _orDash(String s) => s.isEmpty ? '—' : s;

  String _qty(ProtocolProductRule r) {
    final v = r.quantityValue;
    final n = v == v.roundToDouble() ? v.toInt().toString() : v.toString();
    return switch (r.quantityMode) {
      QuantityMode.fixed => n,
      QuantityMode.perArea => '$n ×cm²',
      QuantityMode.perVolume => '$n ×cm³',
    };
  }

  Widget _dataRow(ProtocolProductRule r) {
    final t = BrandTokens.of(context);
    return DefaultTextStyle.merge(
      style: const TextStyle(fontSize: 12),
      child: DecoratedBox(
        decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: t.border, width: 0.5))),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // CONTEXTO manda: el VALOR en negrita (lo que distingue la regla dentro del paso), el
            // tipo pequeño encima. Ya no es prosa gris escondida.
            _cell(
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(_ctxKindLabel[r.contextKind] ?? r.contextKind ?? '—',
                      style: TextStyle(fontSize: 10, color: t.textSecondary)),
                  Text(_ctxValueLabel[r.contextValue] ?? r.contextValue ?? '—',
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                ]),
                _wCtx),
            _cell(
                Text(_orDash([r.scaleLabel, r.triggerLabel]
                    .whereType<String>()
                    .where((s) => s.isNotEmpty)
                    .join(' · '))),
                _wScale),
            _cell(Text(_orDash(r.notePhrase ?? '')), _wNote),
            _cell(
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(r.name ?? '—'),
                  if (r.brand != null && r.brand!.isNotEmpty)
                    Text(r.brand!,
                        style: TextStyle(fontSize: 11, color: t.textSecondary)),
                ]),
                _wProd),
            _cell(Text(_qty(r)), _wQty),
            _cell(_identityCell(r, t), _wId),
          ],
        ),
      ),
    );
  }

  Widget _identityCell(ProtocolProductRule r, BrandTokens t) => Row(
        children: [
          Expanded(
            child: r.isBound
                ? (r.hasIdentity
                    // Atado a un producto del catálogo Kura+ (tiene par shopify): el
                    // catálogo puede mantenerlo actualizado.
                    ? Row(children: [
                        Icon(Icons.link, size: 14, color: t.brandPrimary),
                        const SizedBox(width: 4),
                        Flexible(
                            child: Text('Insumo atado',
                                style: TextStyle(color: t.brandPrimary))),
                      ])
                    // Atado a un insumo EXTERNO (otro proveedor, sin par shopify): es del
                    // centro, el catálogo Kura+ NO lo actualiza. Marca visible en la fila.
                    : Row(children: [
                        Icon(Icons.link, size: 14, color: t.statusWarning),
                        const SizedBox(width: 4),
                        Flexible(
                            child: Text('Insumo externo',
                                style: TextStyle(color: t.statusWarning))),
                        Tooltip(
                          message: 'Insumo de otro proveedor (externo): es del centro. '
                              'El catálogo Kura+ no puede actualizar esta regla.',
                          child: Icon(Icons.info_outline,
                              size: 13, color: t.statusWarning),
                        ),
                      ]))
                : Row(children: [
                    Icon(Icons.link_off, size: 14, color: t.statusWarning),
                    const SizedBox(width: 4),
                    Flexible(
                        child: Text('Sin insumo asignado',
                            style: TextStyle(color: t.statusWarning))),
                  ]),
          ),
          TextButton(
            onPressed: () => _atar(r),
            child: Text(r.isBound ? 'Cambiar' : 'Atar'),
          ),
          IconButton(
            tooltip: 'Editar regla',
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.edit_outlined, size: 18),
            onPressed: () => _openRuleForm(existing: r),
          ),
          IconButton(
            tooltip: 'Borrar regla',
            visualDensity: VisualDensity.compact,
            icon: Icon(Icons.delete_outline, size: 18, color: t.statusWarning),
            onPressed: () => _deleteRule(r),
          ),
        ],
      );

  // ------------------------------------------------------------------ ATADO
  Future<void> _atar(ProtocolProductRule rule) async {
    // Se selecciona de los INSUMOS del centro (dados de alta en Insumos: jalados de
    // la tienda o creados a mano), NO del catálogo global de la tienda. Solo se
    // puede atar lo que el centro ya tiene de alta.
    final item = await showModalBottomSheet<InventoryItem>(
      context: context,
      isScrollControlled: true,
      builder: (_) =>
          _InventoryPickerSheet(repo: repo, organizationId: org, seed: rule.name ?? ''),
    );
    if (item == null || !mounted) return;
    // El VÍNCULO del protocolo es el INSUMO DEL CENTRO (`inventory_item_id`), no el par
    // shopify (Carlos: el protocolo se ata a insumos del centro, no al catálogo de la
    // tienda). Un insumo externo (creado a mano, sin producto de tienda) queda atado
    // igual por inventory_item_id. El par shopify se CONSERVA solo si el insumo lo trae,
    // como identidad de catálogo Kura+ (re-empate entre centros); NO es el vínculo. La
    // prosa (name/brand) no se toca: es lo que ve el clínico.
    final updated = ProtocolProductRule.fromJson({
      ...rule.toJson(),
      'inventory_item_id': item.id,
      'shopify_product_id': item.shopifyProductId,
      'shopify_variant_id': item.shopifyVariantId,
    });
    try {
      await repo.saveProtocolCatalogRule(updated);
      // NADA en silencio: se re-lee la regla y se confirma que el vínculo QUEDÓ. Si el
      // upsert fue rechazado por la RLS o no persistió, saveProtocolCatalogRule lanza
      // (lo caza el catch); si "guardó" pero sin vínculo, este chequeo lo delata.
      final saved = repo
          .listProtocolCatalogRules()
          .firstWhere((r) => r.id == updated.id, orElse: () => updated);
      if (!mounted) return;
      if (!saved.isBound) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('No se pudo atar a ${item.name}: el vínculo no quedó '
                'guardado. Intenta de nuevo.')));
        return;
      }
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Atado a ${item.name}'
              '${item.isExternal ? ' · insumo del centro (sin producto de tienda)' : ''}')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('No se pudo atar a ${item.name}: ${_clean(e)}')));
    }
  }

  // -------- Alta / edición / borrado de reglas del catálogo (§15 etapa 6, editor) --------
  // La autoridad la decide current_user_can_author_catalog() (RLS 0142); NO se agrega
  // condición nueva en el cliente. Nada en silencio: si el guardado/borrado falla, se dice.
  Future<void> _openRuleForm({ProtocolProductRule? existing}) async {
    final saved = await showModalBottomSheet<ProtocolProductRule>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _RuleFormSheet(existing: existing, organizationId: org),
    );
    if (saved == null || !mounted) return;
    try {
      await repo.saveProtocolCatalogRule(saved);
      if (!mounted) return;
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(existing == null ? 'Regla creada' : 'Regla actualizada')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('No se pudo guardar la regla: ${_clean(e)}')));
    }
  }

  Future<void> _deleteRule(ProtocolProductRule rule) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dctx) => AlertDialog(
        title: const Text('Borrar regla'),
        content: Text(
            '¿Borrar esta regla de ${_catLabel(rule.category)}'
            '${(rule.notePhrase ?? '').isNotEmpty ? ' · "${rule.notePhrase}"' : ''}? '
            'No se puede deshacer.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dctx, false),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(dctx, true),
              child: const Text('Borrar')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await repo.deleteProtocolCatalogRule(rule.id);
      if (!mounted) return;
      setState(() {});
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Regla borrada')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('No se pudo borrar la regla: ${_clean(e)}')));
    }
  }

  String _clean(Object e) => '$e'.replaceFirst('Exception: ', '');

  Widget _noPermission() => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.lock_outline,
                  size: 40, color: BrandTokens.of(context).textDisabled),
              const SizedBox(height: 12),
              const Text(
                'No tienes permiso para editar el protocolo de este centro. '
                'La edición es del administrador del centro.',
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
}

/// Selector de INSUMOS del centro (dados de alta en Insumos: jalados de la tienda o
/// creados a mano). Solo se puede atar lo que el centro ya tiene de alta. Un insumo
/// sin producto de tienda (is_external) se marca: al atarlo, la regla del catálogo
/// GLOBAL queda huérfana (solo prosa). NO se selecciona del catálogo global de tienda.
class _InventoryPickerSheet extends StatefulWidget {
  final DataRepository repo;
  final String? organizationId;
  final String seed;
  const _InventoryPickerSheet(
      {required this.repo, required this.organizationId, required this.seed});
  @override
  State<_InventoryPickerSheet> createState() => _InventoryPickerSheetState();
}

class _InventoryPickerSheetState extends State<_InventoryPickerSheet> {
  late final TextEditingController _ctrl =
      TextEditingController(text: _firstWord(widget.seed));
  String _q = '';

  static String _firstWord(String s) =>
      s.split(RegExp(r'[\s(®™]')).firstWhere((w) => w.isNotEmpty, orElse: () => '');

  @override
  void initState() {
    super.initState();
    _q = _ctrl.text.toLowerCase();
  }

  @override
  Widget build(BuildContext context) {
    final all =
        widget.repo.listInventoryItems(organizationId: widget.organizationId);
    final loadFailed = widget.repo.inventoryLoadFailed;
    // Dos estados de falla, no uno (en clínica, "rancio" es peor que "vacío"):
    //  - falló + vacío → no se pudo cargar (abajo, _CatalogLoadFailed);
    //  - falló + CON datos → hay respaldo de caché, pero es viejo (esta franja).
    final stale = loadFailed && all.isNotEmpty;
    final q = _q.trim().toLowerCase();
    final results = q.isEmpty
        ? all
        : all.where((it) {
            final hay = '${it.name} ${it.supplier ?? ''}'.toLowerCase();
            return q.split(' ').every((t) => hay.contains(t));
          }).toList();
    final t = BrandTokens.of(context);
    return Padding(
      padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
          left: 16,
          right: 16,
          top: 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('Elegí el insumo del centro',
              style: TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          TextField(
            controller: _ctrl,
            autofocus: true,
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText: 'Buscar por nombre o proveedor',
            ),
            onChanged: (v) => setState(() => _q = v),
          ),
          const SizedBox(height: 8),
          if (stale)
            _StaleCatalogBanner(
              onRetry: () async {
                await widget.repo.refreshInventory();
                if (mounted) setState(() {});
              },
            ),
          Flexible(
            child: results.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(24),
                    // Red de seguridad: si los insumos NO cargaron (falló la
                    // hidratación), NO decir "sin insumos" —eso lo haría ver como
                    // inventario vacío—; decir que falló y ofrecer reintentar.
                    child: (all.isEmpty && loadFailed)
                        ? _CatalogLoadFailed(
                            onRetry: () async {
                              await widget.repo.refreshInventory();
                              if (mounted) setState(() {});
                            },
                          )
                        : const Text(
                            'Sin insumos que coincidan. Dá de alta el insumo en '
                            'Insumos y vuelve a atar.'),
                  )
                : ListView.builder(
                    shrinkWrap: true,
                    itemCount: results.length,
                    itemBuilder: (_, i) {
                      final it = results[i];
                      final orphan = (it.shopifyProductId ?? '').isEmpty;
                      return ListTile(
                        title: Text(it.name),
                        subtitle: Text([
                          it.supplier,
                          if (orphan) 'sin producto de tienda (solo prosa)',
                        ].whereType<String>().where((s) => s.isNotEmpty).join(' · ')),
                        trailing: orphan
                            ? Icon(Icons.link_off, size: 18, color: t.statusWarning)
                            : null,
                        onTap: () => Navigator.pop(context, it),
                      );
                    },
                  ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

/// Franja de datos RANCIOS: el catálogo tiene respaldo en caché (se puede seguir
/// atando) pero la última actualización falló. En clínica, mostrar dato viejo como
/// actual es peor que mostrar vacío; por eso se avisa sin bloquear, con Reintentar.
class _StaleCatalogBanner extends StatelessWidget {
  const _StaleCatalogBanner({required this.onRetry});
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    final t = BrandTokens.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: t.chipBg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: t.statusWarning),
      ),
      child: Row(
        children: [
          Icon(Icons.history, size: 18, color: t.statusWarning),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Mostrando la última versión disponible; no se pudo actualizar.',
              style: TextStyle(fontSize: 12, color: t.textSecondary),
            ),
          ),
          TextButton(onPressed: onRetry, child: const Text('Reintentar')),
        ],
      ),
    );
  }
}

/// Estado de FALLA de carga de INSUMOS (distinto de "vacío"): la hidratación de
/// inventory_items no cargó, así que la lista no es de fiar. En producción es el
/// caso peligroso —el atado de la Matriz se vería vacío sin ruido— y aquí se dice
/// con todas las letras + Reintentar. Red de seguridad del hidratado por tandas
/// ([[refresh-collection-swallows-empty]]).
class _CatalogLoadFailed extends StatelessWidget {
  const _CatalogLoadFailed({required this.onRetry});
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    final t = BrandTokens.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.cloud_off, size: 40, color: t.statusWarning),
        const SizedBox(height: 8),
        const Text('No se pudieron cargar los insumos.',
            textAlign: TextAlign.center,
            style: TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        Text('No es que esté vacío: la carga falló. Reintentá.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: t.textSecondary)),
        const SizedBox(height: 12),
        FilledButton.tonalIcon(
          onPressed: onRetry,
          icon: const Icon(Icons.refresh),
          label: const Text('Reintentar'),
        ),
      ],
    );
  }
}

/// Editor de una regla del catálogo Kura+ (§15 etapa 6 — el ALTA/edición que faltaba;
/// sin él, "frase para la nota" quedaba vacía y el protocolo no servía en la nota).
/// Campos: paso, contexto (tipo+valor), escala·disparador, cantidad, y la FRASE. El
/// producto se ata aparte (botón Atar), no se re-hace aquí. La autoridad la decide la
/// RLS (current_user_can_author_catalog); esta hoja no agrega condición de cliente.
class _RuleFormSheet extends StatefulWidget {
  final ProtocolProductRule? existing;
  final String? organizationId;
  const _RuleFormSheet({this.existing, required this.organizationId});
  @override
  State<_RuleFormSheet> createState() => _RuleFormSheetState();
}

class _RuleFormSheetState extends State<_RuleFormSheet> {
  late String _category;
  String? _contextKind;
  String? _contextValue;
  late QuantityMode _quantityMode;
  late final TextEditingController _scale;
  late final TextEditingController _trigger;
  late final TextEditingController _qty;
  late final TextEditingController _note;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _category = e?.category ?? KuraTag.aposito.dbValue;
    _contextKind = e?.contextKind;
    _contextValue = e?.contextValue;
    _quantityMode = e?.quantityMode ?? QuantityMode.fixed;
    _scale = TextEditingController(text: e?.scaleLabel ?? '');
    _trigger = TextEditingController(text: e?.triggerLabel ?? '');
    _qty = TextEditingController(text: _fmtQty(e?.quantityValue ?? 1));
    _note = TextEditingController(text: e?.notePhrase ?? '');
  }

  static String _fmtQty(double v) => v == v.roundToDouble()
      ? v.toInt().toString()
      : v.toString();

  @override
  void dispose() {
    _scale.dispose();
    _trigger.dispose();
    _qty.dispose();
    _note.dispose();
    super.dispose();
  }

  String? _blank(String s) => s.trim().isEmpty ? null : s.trim();

  void _save() {
    final e = widget.existing;
    // Se construye la regla desde el formulario, PRESERVANDO lo que no se edita aquí:
    // identidad de producto (par shopify), prosa atada, medida y multi-factor.
    final rule = ProtocolProductRule(
      id: e?.id ?? '',
      organizationId: e?.organizationId ?? (widget.organizationId ?? ''),
      category: _category,
      quantityMode: _quantityMode,
      quantityValue: double.tryParse(_qty.text.trim()) ?? 1,
      contextKind: _contextKind,
      contextValue: _contextValue,
      scaleLabel: _blank(_scale.text),
      triggerLabel: _blank(_trigger.text),
      notePhrase: _blank(_note.text),
      // Preservados del existente (no editables en esta hoja):
      inventoryItemId: e?.inventoryItemId,
      name: e?.name,
      brand: e?.brand,
      altName: e?.altName,
      altBrand: e?.altBrand,
      shopifyProductId: e?.shopifyProductId,
      shopifyVariantId: e?.shopifyVariantId,
      etapaClinica: e?.etapaClinica,
      notas: e?.notas,
      sortOrder: e?.sortOrder ?? 0,
      dimension: e?.dimension ?? RuleDimension.none,
      minValue: e?.minValue,
      maxValue: e?.maxValue,
      exudateLevels: e?.exudateLevels ?? const [],
      zoneGroups: e?.zoneGroups ?? const [],
      infection: e?.infection ?? RuleInfection.any,
      priority: e?.priority ?? 0,
    );
    Navigator.pop(context, rule);
  }

  @override
  Widget build(BuildContext context) {
    final isNew = widget.existing == null;
    // Valores de contexto: los conocidos + el actual (si viniera crudo, no se pierde).
    final ctxValues = <String>{
      ..._ctxValueLabel.keys,
      if (_contextValue != null) _contextValue!,
    }.toList();
    return Padding(
      padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
          left: 16, right: 16, top: 16),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(isNew ? 'Nueva regla del protocolo' : 'Editar regla',
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: _category,
              decoration: const InputDecoration(labelText: 'Paso (categoría)'),
              items: [
                for (final tag in KuraTag.values)
                  DropdownMenuItem(value: tag.dbValue, child: Text(tag.label)),
              ],
              onChanged: (v) => setState(() => _category = v ?? _category),
            ),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                child: DropdownButtonFormField<String?>(
                  value: _contextKind,
                  decoration: const InputDecoration(labelText: 'Tipo de contexto'),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('Cualquiera')),
                    for (final e in _ctxKindLabel.entries)
                      DropdownMenuItem(value: e.key, child: Text(e.value)),
                  ],
                  onChanged: (v) => setState(() => _contextKind = v),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: DropdownButtonFormField<String?>(
                  value: _contextValue,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Contexto'),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('Cualquiera')),
                    for (final v in ctxValues)
                      DropdownMenuItem(
                          value: v,
                          child: Text(_ctxValueLabel[v] ?? v,
                              overflow: TextOverflow.ellipsis)),
                  ],
                  onChanged: (v) => setState(() => _contextValue = v),
                ),
              ),
            ]),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                child: TextField(
                  controller: _scale,
                  decoration: const InputDecoration(
                      labelText: 'Escala', hintText: 'p. ej. Área'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _trigger,
                  decoration: const InputDecoration(
                      labelText: 'Disparador', hintText: 'p. ej. > 10 cm²'),
                ),
              ),
            ]),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                child: DropdownButtonFormField<QuantityMode>(
                  value: _quantityMode,
                  decoration: const InputDecoration(labelText: 'Cantidad'),
                  items: [
                    for (final m in QuantityMode.values)
                      DropdownMenuItem(value: m, child: Text(m.label)),
                  ],
                  onChanged: (v) =>
                      setState(() => _quantityMode = v ?? _quantityMode),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 90,
                child: TextField(
                  controller: _qty,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Valor'),
                ),
              ),
            ]),
            const SizedBox(height: 8),
            TextField(
              controller: _note,
              minLines: 2,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'Frase para la nota',
                hintText: 'Lo que aparece en la nota clínica cuando aplica esta regla.',
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancelar')),
                const SizedBox(width: 8),
                FilledButton(
                    onPressed: _save,
                    child: Text(isNew ? 'Crear' : 'Guardar')),
              ],
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
