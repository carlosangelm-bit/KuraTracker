import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/session_provider.dart';
import '../../core/design/tokens.dart';
import '../../core/widgets/kura_module_lock.dart';
import '../../models/note_option_catalog.dart';
import '../../models/product_catalog_item.dart';
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

  DataRepository get repo => widget.repo;
  String? get org => widget.organizationId;

  bool get _resolvesFromCatalog =>
      _switchOverride ?? repo.resolvesFromCatalog(org);

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(sessionProvider).user;
    final isMaster = user?.isMaster ?? false;
    final isAdmin = user?.isAdmin ?? false;
    // Candado COMERCIAL (module:admin), como todas las pantallas hijas de /admin: es un gate del
    // CENTRO, independiente del rol, así que va PRIMERO. Un centro sin el módulo ve el bloqueo con
    // precio, teclee quien teclee la URL. La enumeración en admin_gated_screens_lock_test exige que
    // esta pantalla lo conserve (si se le cae, la reja se pone roja).
    if (!repo.premiumAdminFor(org)) {
      return adminModuleLockedScaffold(context,
          repo: repo,
          organizationId: org,
          title: 'Matriz del protocolo',
          description:
              'Edita el régimen por paso y contexto, y ata cada uno al producto de tu centro.');
    }

    final canAuthor = repo.canAuthorProtocolCatalog(
        organizationId: org, isAdmin: isAdmin, isMaster: isMaster);

    // Módulo SIN autoría: reglas propias del centro. Se delega al editor existente (que trae su
    // propio Scaffold) para no perder la EDICIÓN de reglas propias. La unificación total de ese
    // modo dentro de la Matriz queda como seguimiento; el foco de esta etapa es el catálogo.
    if (!canAuthor && isAdmin) {
      return ProtocolProductRulesScreen(repo: repo, organizationId: org);
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Matriz del protocolo')),
      body: canAuthor ? _catalogView(isMaster) : _noPermission(),
    );
  }

  // ------------------------------------------------------------------ AUTORA
  Widget _catalogView(bool isMaster) {
    final rules = repo.listProtocolCatalogRules();
    final byCat = <String, List<ProtocolProductRule>>{};
    for (final r in rules) {
      byCat.putIfAbsent(r.category, () => []).add(r);
    }
    final cats = byCat.keys.toList()..sort();
    final atadas = rules.where((r) => r.hasIdentity).length;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _switchHeader(isMaster),
        const SizedBox(height: 12),
        Text('Catálogo Kura+ · $atadas de ${rules.length} reglas con producto atado',
            style: TextStyle(
                fontSize: 12,
                color: BrandTokens.of(context).textSecondary)),
        const SizedBox(height: 8),
        if (rules.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Text('El catálogo aún no tiene reglas.'),
          ),
        for (final c in cats) ...[
          _categoryTitle(c),
          for (final r in byCat[c]!) _ruleTile(r),
          const SizedBox(height: 8),
        ],
      ],
    );
  }

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

  Widget _categoryTitle(String category) {
    final tag = KuraTag.values.where((t) => t.dbValue == category);
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 4),
      child: Text(tag.isEmpty ? category : tag.first.label,
          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
    );
  }

  Widget _ruleTile(ProtocolProductRule r) {
    final ctx = [r.contextValue, r.scaleLabel, r.triggerLabel]
        .whereType<String>()
        .where((s) => s.isNotEmpty)
        .join(' · ');
    return Card(
      child: ListTile(
        title: Text(r.name ?? '(sin nombre)'),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (r.brand != null && r.brand!.isNotEmpty)
              Text(r.brand!, style: const TextStyle(fontSize: 12)),
            if (ctx.isNotEmpty)
              Text(ctx,
                  style: TextStyle(
                      fontSize: 11,
                      color: BrandTokens.of(context).textSecondary)),
            const SizedBox(height: 4),
            r.hasIdentity
                ? Row(children: [
                    Icon(Icons.link, size: 14, color: BrandTokens.of(context).brandPrimary),
                    const SizedBox(width: 4),
                    Text('Producto atado',
                        style: TextStyle(
                            fontSize: 12, color: BrandTokens.of(context).brandPrimary)),
                  ])
                : Row(children: [
                    Icon(Icons.link_off,
                        size: 14, color: BrandTokens.of(context).statusWarning),
                    const SizedBox(width: 4),
                    Text('Sin producto de la tienda asignado',
                        style: TextStyle(
                            fontSize: 12, color: BrandTokens.of(context).statusWarning)),
                  ]),
          ],
        ),
        trailing: TextButton(
          onPressed: () => _atar(r),
          child: Text(r.hasIdentity ? 'Cambiar' : 'Atar'),
        ),
      ),
    );
  }

  // ------------------------------------------------------------------ ATADO
  Future<void> _atar(ProtocolProductRule rule) async {
    final item = await showModalBottomSheet<ProductCatalogItem>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _ProductPickerSheet(
          repo: repo, seed: rule.name ?? ''),
    );
    if (item == null || !mounted) return;
    // La tabla es global: se reescribe la regla con el par shopify. saveProtocolCatalogRule quita
    // organization_id. Ata identidad SIN tocar la prosa (name/brand/alt siguen siendo lo que ve
    // el clínico); el humano ya desambiguó la presentación.
    final updated = ProtocolProductRule.fromJson({
      ...rule.toJson(),
      'shopify_product_id': item.shopifyProductId,
      'shopify_variant_id': item.shopifyVariantId ?? '',
    });
    await repo.saveProtocolCatalogRule(updated);
    if (!mounted) return;
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Atado: ${item.title}${item.variantTitle != null ? ' · ${item.variantTitle}' : ''}')));
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

/// Selector de producto contra product_catalog EN VIVO. El humano desambigua la presentación
/// (Border Flex vs su variante Lite; cuál de los Prontosan). NO se filtra por clasificación
/// (kura_tag/generic_product están vacías). Marca/línea a la vista para elegir bien.
class _ProductPickerSheet extends StatefulWidget {
  final DataRepository repo;
  final String seed;
  const _ProductPickerSheet({required this.repo, required this.seed});
  @override
  State<_ProductPickerSheet> createState() => _ProductPickerSheetState();
}

class _ProductPickerSheetState extends State<_ProductPickerSheet> {
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
    final all = widget.repo.listProductCatalog();
    final q = _q.trim().toLowerCase();
    final results = q.isEmpty
        ? all
        : all.where((p) {
            final hay =
                '${p.title} ${p.variantTitle ?? ''} ${p.vendor ?? ''} ${p.sku ?? ''}'
                    .toLowerCase();
            return q.split(' ').every((t) => hay.contains(t));
          }).toList();
    return Padding(
      padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
          left: 16,
          right: 16,
          top: 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('Elegí la presentación de la tienda',
              style: TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          TextField(
            controller: _ctrl,
            autofocus: true,
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText: 'Buscar por nombre, marca o SKU',
            ),
            onChanged: (v) => setState(() => _q = v),
          ),
          const SizedBox(height: 8),
          Flexible(
            child: results.isEmpty
                ? const Padding(
                    padding: EdgeInsets.all(24),
                    child: Text('Sin candidatos en la tienda para esa búsqueda.'),
                  )
                : ListView.builder(
                    shrinkWrap: true,
                    itemCount: results.length,
                    itemBuilder: (_, i) {
                      final p = results[i];
                      return ListTile(
                        title: Text(p.title),
                        subtitle: Text([
                          p.variantTitle,
                          p.vendor,
                          if (p.sku != null) 'SKU ${p.sku}',
                        ].whereType<String>().where((s) => s.isNotEmpty).join(' · ')),
                        onTap: () => Navigator.pop(context, p),
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
