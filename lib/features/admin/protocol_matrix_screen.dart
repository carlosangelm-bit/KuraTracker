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

class _ProtocolMatrixScreenState extends ConsumerState<ProtocolMatrixScreen> {
  // Reflejo local del interruptor tras un cambio de master, para que se vea al instante (la
  // hidratación de la org llega después; la RPC ya actualizó la base que leen las clínicas).
  bool? _switchOverride;
  bool _flipping = false;
  // Filtros (§presentación): con 35 reglas, 17 solo en apósito, recorrer a scroll no se sostiene
  // en vivo. Se filtra por PASO (categoría) y por CONTEXTO.
  String? _catFilter; // KuraTag.dbValue | null = todos
  String? _ctxFilter; // context_value | null = todos

  // Etiquetas legibles de contexto. Los valores crudos vienen del catálogo (Excel); el texto es el
  // del DOMINIO (mismas palabras de las pantallas clínicas), no inventado. Un valor sin mapa cae a
  // su forma cruda (visible, para cazarlo), no a un guion bajo silencioso.
  static const _ctxKindLabel = {
    'etiologia': 'Etiología',
    'piel': 'Piel',
    'evolucion': 'Evolución',
  };
  static const _ctxValueLabel = {
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
    final atadas = all.where((r) => r.hasIdentity).length;

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
        Text('Catálogo Kura+ · $atadas de ${all.length} reglas con producto atado',
            style: TextStyle(
                fontSize: 12, color: BrandTokens.of(context).textSecondary)),
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
            child: r.hasIdentity
                ? Row(children: [
                    Icon(Icons.link, size: 14, color: t.brandPrimary),
                    const SizedBox(width: 4),
                    Flexible(
                        child: Text('Producto atado',
                            style: TextStyle(color: t.brandPrimary))),
                  ])
                : Row(children: [
                    Icon(Icons.link_off, size: 14, color: t.statusWarning),
                    const SizedBox(width: 4),
                    Flexible(
                        child: Text('Sin producto asignado',
                            style: TextStyle(color: t.statusWarning))),
                  ]),
          ),
          TextButton(
            onPressed: () => _atar(r),
            child: Text(r.hasIdentity ? 'Cambiar' : 'Atar'),
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
    // La tabla es GLOBAL: se guarda el par shopify TOMADO DEL INSUMO. Un insumo
    // creado a mano (is_external, sin producto de tienda) no tiene par → la regla
    // queda HUÉRFANA (solo prosa) en el catálogo Kura+; el modelo ya lo contempla y
    // un centro cliente no podría resolver un id propio de todos modos. Ata identidad
    // SIN tocar la prosa (name/brand siguen siendo lo que ve el clínico).
    final hasPair = (item.shopifyProductId ?? '').isNotEmpty;
    final updated = ProtocolProductRule.fromJson({
      ...rule.toJson(),
      'shopify_product_id': item.shopifyProductId ?? '',
      'shopify_variant_id': item.shopifyVariantId ?? '',
    });
    await repo.saveProtocolCatalogRule(updated);
    if (!mounted) return;
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(hasPair
            ? 'Atado a ${item.name}'
            : 'Atado a ${item.name} · sin producto de tienda: en el catálogo Kura+ '
                'esta regla va solo con prosa (huérfana)')));
  }

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
