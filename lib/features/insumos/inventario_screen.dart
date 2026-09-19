import 'package:csv/csv.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/design/tokens.dart';
import '../../core/pricing.dart';
import '../../core/format/money.dart';
import '../../core/providers/session_provider.dart';
import '../../core/providers/active_organization_provider.dart';
import '../../core/router/app_shell.dart' show UserMenuButton;
import '../../core/widgets/kura_action_bar.dart';
import '../../core/widgets/kura_data_table.dart';
import '../../core/widgets/kura_empty_state.dart';
import '../../core/widgets/kura_error_state.dart';
import '../../core/widgets/kura_module_lock.dart';
import '../../models/inventory.dart';
import '../../services/csv_download.dart';
import '../../services/data_repository.dart';
import 'consumo_meaning.dart';
import 'inventory_stat_row.dart';
import 'product_picker.dart';
import 'purchase_guard.dart';

/// Centavos a partir de un monto en pesos (double). Los helpers de dinero del
/// core hablan en centavos; el inventario guarda costo/precio en pesos.
int? _cents(double? pesos) => pesos == null ? null : (pesos * 100).round();

/// Inventario de insumos por SITIO (Insumos, Fase 3 premium), rediseñado sobre el
/// sistema de componentes: dato tabular servido como tabla (no como lista de
/// subtítulos de 11px), con cifras con contexto, buscador, filtros con conteo,
/// totales y las cuatro acciones pesadas con NOMBRE completo.
class InventarioScreen extends ConsumerStatefulWidget {
  const InventarioScreen({super.key});
  @override
  ConsumerState<InventarioScreen> createState() => _InventarioScreenState();
}

class _InventarioScreenState extends ConsumerState<InventarioScreen> {
  String? _siteId;
  bool _syncing = false;
  String _query = '';
  String _filter = 'all'; // all | low | out | store | external | nothreshold
  final _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  /// Bajada del espejo: trae existencias de Shopify y ajusta el inventario del
  /// sitio (solo centro Kura+ marcado como espejo).
  Future<void> _syncShopify(DataRepository repo, String? orgId) async {
    final siteId = _siteId;
    if (orgId == null || siteId == null) return;
    setState(() => _syncing = true);
    try {
      final n = await repo.syncShopifyInventory(orgId, siteId);
      if (mounted) {
        setState(() {});
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Existencias sincronizadas: $n ajuste(s).')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('$e'.replaceFirst('Exception: ', ''))));
      }
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  // Encabezado del CSV de carga masiva de inventario.
  static const _csvHeader = [
    'sku',
    'nombre',
    'proveedor',
    'costo',
    'precio',
    'moneda',
    'cantidad',
    'shopify_product_id',
    'shopify_variant_id',
    'umbral',
  ];

  /// Descarga un CSV con el catálogo global completo (para que el centro ajuste
  /// costo/cantidad) + una fila guía. Se puede agregar productos nuevos con
  /// filas cuyo shopify_product_id quede vacío.
  Future<void> _downloadCsv(DataRepository repo, String? orgId) async {
    final catalog = repo.listProductCatalog();
    final rows = <List<dynamic>>[_csvHeader];
    for (final p in catalog) {
      rows.add([
        p.sku ?? '',
        p.displayName,
        p.vendor ?? '',
        '', // costo (lo llena el centro)
        p.price?.toStringAsFixed(2) ?? '',
        p.currency ?? 'MXN',
        '', // cantidad inicial (lo llena el centro)
        p.shopifyProductId,
        p.shopifyVariantId ?? '',
        '', // umbral de reorden (lo llena el centro)
      ]);
    }
    // Fila-ejemplo de producto NUEVO (sin ids de Shopify = externo).
    rows.add([
      'SKU-EJEMPLO',
      'Producto propio del centro (ejemplo)',
      'Proveedor',
      '0.00',
      '0.00',
      'MXN',
      '0',
      '',
      '',
      '5', // umbral de reorden (ejemplo)
    ]);
    final content = const ListToCsvConverter().convert(rows);
    try {
      await downloadCsv('inventario_catalogo.csv', content);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('No se pudo descargar: $e')));
      }
    }
  }

  /// Carga un CSV y crea/repone artículos de inventario en el sitio actual.
  /// Con shopify_product_id → artículo ligado al catálogo; sin él → externo.
  Future<void> _uploadCsv(DataRepository repo, String? orgId) async {
    final siteId = _siteId;
    if (orgId == null || siteId == null) return;
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['csv'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final bytes = result.files.first.bytes;
    if (bytes == null) return;

    try {
      final content = String.fromCharCodes(bytes);
      final raw = const CsvToListConverter(eol: '\n', shouldParseNumbers: false)
          .convert(content);
      if (raw.isEmpty) throw 'CSV vacío.';

      // Índice de columnas por encabezado (tolerante al orden).
      final header =
          raw.first.map((e) => e.toString().trim().toLowerCase()).toList();
      int col(String name) => header.indexOf(name);
      final iSku = col('sku'),
          iName = col('nombre'),
          iProv = col('proveedor'),
          iCost = col('costo'),
          iPrice = col('precio'),
          iCur = col('moneda'),
          iQty = col('cantidad'),
          iPid = col('shopify_product_id'),
          iVid = col('shopify_variant_id'),
          iUmbral = col('umbral');
      if (iName < 0) throw 'Falta la columna "nombre".';

      final existing =
          repo.listInventoryItems(organizationId: orgId, siteId: siteId);
      final uid = ref.read(sessionProvider).user?.id;
      String? cell(List<dynamic> r, int i) =>
          i >= 0 && i < r.length ? r[i].toString().trim() : null;
      double? toNum(String? s) =>
          (s == null || s.isEmpty) ? null : double.tryParse(s.replaceAll(',', '.'));

      var created = 0, restocked = 0, skipped = 0, sinPrecio = 0;
      for (var k = 1; k < raw.length; k++) {
        final r = raw[k];
        final name = cell(r, iName) ?? '';
        if (name.isEmpty) continue;
        final pid = cell(r, iPid);
        final vid = cell(r, iVid);
        final qty = (toNum(cell(r, iQty)) ?? 0).round();
        final cost = toNum(cell(r, iCost));
        final price = toNum(cell(r, iPrice));
        final cur = cell(r, iCur);
        final sku = cell(r, iSku);
        final prov = cell(r, iProv);
        final threshold = int.tryParse(cell(r, iUmbral) ?? '');

        // ¿Ya existe? (por producto de Shopify si hay id; si no, por nombre.)
        InventoryItem? match;
        for (final it in existing) {
          final same = (pid != null && pid.isNotEmpty)
              ? it.shopifyProductId == pid
              : it.name.toLowerCase() == name.toLowerCase();
          if (same) {
            match = it;
            break;
          }
        }

        if (match == null) {
          final item = await repo.addInventoryItem(
            organizationId: orgId,
            siteId: siteId,
            name: name,
            isExternal: pid == null || pid.isEmpty,
            shopifyProductId: (pid != null && pid.isNotEmpty) ? pid : null,
            shopifyVariantId: (vid != null && vid.isNotEmpty) ? vid : null,
            unitCost: cost,
            unitPrice: price,
            currency: cur,
            supplier: (prov != null && prov.isNotEmpty) ? prov : null,
            reorderThreshold: threshold,
            notes: (sku != null && sku.isNotEmpty) ? 'SKU: $sku' : null,
            createdBy: uid,
          );
          created++;
          if (item.unitPrice == null) sinPrecio++;
          if (qty > 0) {
            await repo.addInventoryMovement(
              item: item,
              delta: qty,
              reason: InventoryReason.compra,
              unitCost: cost,
              note: 'Carga inicial (CSV)',
              createdBy: uid,
            );
          }
        } else {
          // Re-subir el CSV actualiza costo y precio del artículo existente con
          // la regla única (spec 19-sep): el centro repara precios re-subiendo
          // el CSV, no solo umbrales. Solo si la fila trae costo o precio.
          //
          // El precio capturado a mano NUNCA se pisa (Carlos, verificación
          // 19-sep): si la fila trae precio explícito, ese manda (el CSV también
          // es captura); si NO trae precio, se respeta el que el insumo ya tenga
          // y solo se DERIVA cuando el insumo no tiene precio. Así un reabasto por
          // CSV (costos, sin columna precio) no borra los precios ajustados a mano.
          if (cost != null || price != null) {
            final newPrice = salePriceOnCsvReupload(
                rowPrice: price,
                rowCost: cost,
                existingPrice: match.unitPrice,
                existingCost: match.unitCost);
            await repo.updateInventoryItem(match.id,
                unitCost: cost, unitPrice: newPrice);
            if (newPrice == null) sinPrecio++;
          } else if (match.unitPrice == null) {
            sinPrecio++;
          }
          // Actualiza el umbral del artículo existente si el CSV lo trae (así
          // el centro que ya cargó todo puede fijar umbrales re-subiendo el CSV).
          if (threshold != null && match.reorderThreshold != threshold) {
            await repo.updateInventoryItem(match.id,
                reorderThreshold: threshold);
          }
          if (qty > 0) {
            await repo.addInventoryMovement(
              item: match,
              delta: qty,
              reason: InventoryReason.compra,
              unitCost: cost,
              note: 'Reabasto (CSV)',
              createdBy: uid,
            );
            restocked++;
          } else {
            skipped++;
          }
        }
      }
      if (mounted) {
        setState(() {});
        final base = 'CSV: $created creados, $restocked reabastecidos'
            '${skipped > 0 ? ', $skipped sin cambios' : ''}.';
        // Aviso, no candado: un insumo sin precio se cobra a costo (dicho en
        // voz alta), pero el centro debe saber cuántos quedaron así.
        final aviso = sinPrecio > 0
            ? ' $sinPrecio sin precio (se cobrarán a costo — captura el precio).'
            : '';
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('$base$aviso'),
            backgroundColor: sinPrecio > 0 ? Colors.orange.shade800 : null));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('No se pudo cargar el CSV: $e')));
      }
    }
  }

  /// Consumo del mes en curso (piezas) y comparación contra el mes anterior. La
  /// cifra NUNCA va sola: siempre sale con su línea de comparación (acuerdo del
  /// canvas). `pct` es null cuando el mes anterior no tuvo consumo (no hay contra
  /// qué comparar).
  ({int current, int prev, String prevLabel}) _consumo(
      DataRepository repo, String siteId) {
    final consumos = repo
        .listInventoryMovements(siteId: siteId)
        .where((m) => m.reason == InventoryReason.consumo);
    final now = DateTime.now();
    int inMonth(int y, int mo) => consumos
        .where((m) => m.createdAt.year == y && m.createdAt.month == mo)
        .fold(0, (a, m) => a + m.delta.abs());
    final prevDate = DateTime(now.year, now.month - 1, 1);
    return (
      current: inMonth(now.year, now.month),
      prev: inMonth(prevDate.year, prevDate.month),
      prevLabel: spanishMonth(prevDate.month),
    );
  }

  @override
  Widget build(BuildContext context) {
    final repoAsync = ref.watch(dataRepositoryProvider);
    final user = ref.watch(sessionProvider).user;
    // Sin rol de compra: la compra de insumos es del admin del centro.
    if (!canPurchaseSupplies(user)) return purchaseDeniedScaffold('Inventario');

    final t = BrandTokens.of(context);
    return Scaffold(
      backgroundColor: t.background,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        backgroundColor: t.surface,
        elevation: 0,
        toolbarHeight: 52,
        actions: const [UserMenuButton()],
      ),
      body: repoAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, st) => _wrap(
          t,
          KuraErrorState(
            title: 'No pudimos cargar el inventario',
            reassurance: 'Tus existencias y movimientos están a salvo; solo '
                'no pudimos leerlos ahora.',
            detail: '$e',
            onRetry: () => ref.invalidate(dataRepositoryProvider),
          ),
        ),
        data: (repo) => _body(context, t, repo, user),
      ),
    );
  }

  Widget _wrap(BrandTokens t, Widget child) => Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1200),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(40, 30, 40, 44),
            child: child,
          ),
        ),
      );

  Widget _body(
      BuildContext context, BrandTokens t, DataRepository repo, dynamic user) {
    // centro ACTIVO (no el de origen): la capacidad se pregunta sobre el centro activo
    final orgId = ref.watch(activeOrganizationIdProvider);

    // Sin módulo: sección completa del bloqueo (precio de billing_catalog + salida
    // a Licencias), no una línea gris suelta.
    if (!repo.premiumInsumosFor(orgId)) {
      return _wrap(
        t,
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _header(t, repo, orgId, sites: const [], centerMode: true),
            const SizedBox(height: 24),
            KuraModuleLock.section(
              repo: repo,
              organizationId: orgId ?? '',
              moduleKey: 'insumos',
              moduleName: 'Insumos',
              description: 'Inventario por sede, consumo, costeo y reabasto de '
                  'tus insumos —de la tienda Kura+ o de cualquier proveedor.',
            ),
          ],
        ),
      );
    }

    final sites =
        repo.listSites(organizationId: orgId).where((s) => s.isActive).toList();
    if (sites.isEmpty) {
      // El inventario es POR SITIO (sede). Un centro recién creado no tiene ninguno:
      // no es un error, es el primer paso. Se explica y se da la acción (no callejón).
      return _wrap(
        t,
        KuraEmptyState(
          icon: Icons.add_location_alt_outlined,
          title: 'Primero, una sede',
          message: 'El inventario se lleva por sede: cada sitio tiene su propia '
              'existencia. Este centro todavía no tiene ninguna. Da de alta una '
              'sede y aquí podrás capturar sus artículos.',
          primaryLabel: 'Configurar sedes',
          onPrimary: () => context.go('/admin/sitios'),
        ),
      );
    }

    // Alcance (0053): 'center' = una sola bolsa; 'site' = por sitio con selector.
    // El espejo de Shopify unifica por centro sin importar el scope.
    final scope = repo.inventoryScopeFor(orgId);
    final mirrorUnified = repo.shopifyMirrorFor(orgId);
    final centerMode = scope == 'center' || mirrorUnified;
    if (centerMode) {
      _siteId = sites.first.id;
    } else {
      _siteId ??= repo.primarySiteIdForProfile(user?.id) ?? sites.first.id;
      if (!sites.any((s) => s.id == _siteId)) _siteId = sites.first.id;
    }

    final items = repo.listInventoryItems(organizationId: orgId, siteId: _siteId);
    final onHand = repo.inventoryOnHand(_siteId!);
    int oh(InventoryItem it) => onHand[it.id] ?? 0;

    // Estado vacío.
    if (items.isEmpty) {
      return _wrap(
        t,
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _header(t, repo, orgId, sites: sites, centerMode: centerMode),
            const SizedBox(height: 40),
            KuraEmptyState(
              icon: Icons.inventory_2_outlined,
              title: 'Todavía no hay artículos en esta sede',
              message: 'Agrega productos de tu tienda o captura los que compras '
                  'con otro proveedor. Si ya los tienes en una hoja, súbelos de '
                  'una vez.',
              primaryLabel: 'Agregar artículo',
              onPrimary: () => _addItem(repo, orgId),
              secondaryLabel: 'Cargar CSV',
              onSecondary: () => _uploadCsv(repo, orgId),
            ),
          ],
        ),
      );
    }

    // Conteos para las cifras y los filtros (sobre todos los del sitio).
    final outCount = items.where((it) => oh(it) <= 0).length;
    final lowCount = items
        .where((it) =>
            it.reorderThreshold != null &&
            oh(it) > 0 &&
            oh(it) <= it.reorderThreshold!)
        .length;
    final reorderCount = outCount + lowCount; // "Por reordenar"
    final storeCount = items.where((it) => !it.isExternal).length;
    final externalCount = items.where((it) => it.isExternal).length;
    final noThresholdCount =
        items.where((it) => it.reorderThreshold == null).length;
    // Insumos con costo pero sin precio de venta: por la regla única no deberían
    // existir (costo>0 ⇒ precio), así que un conteo>0 son legados/casos a la mano
    // que se cobrarán A COSTO. Aviso, no candado.
    final sinPrecioCount = items
        .where((it) => (it.unitCost ?? 0) > 0 && it.unitPrice == null)
        .length;
    final invValuePesos =
        items.fold<double>(0, (a, it) => a + (it.unitCost ?? 0) * oh(it));
    final consumo = _consumo(repo, _siteId!);

    // Filtro + búsqueda.
    final q = _query.trim().toLowerCase();
    bool matchesFilter(InventoryItem it) {
      final h = oh(it);
      switch (_filter) {
        case 'low':
          return it.reorderThreshold != null &&
              h > 0 &&
              h <= it.reorderThreshold!;
        case 'out':
          return h <= 0;
        case 'store':
          return !it.isExternal;
        case 'external':
          return it.isExternal;
        case 'nothreshold':
          return it.reorderThreshold == null;
        default:
          return true;
      }
    }

    bool matchesQuery(InventoryItem it) {
      if (q.isEmpty) return true;
      return it.name.toLowerCase().contains(q) ||
          (it.supplier ?? '').toLowerCase().contains(q) ||
          (it.notes ?? '').toLowerCase().contains(q);
    }

    final shown =
        items.where((it) => matchesFilter(it) && matchesQuery(it)).toList();
    final shownPz = shown.fold<int>(0, (a, it) => a + oh(it));
    final shownValue =
        shown.fold<double>(0, (a, it) => a + (it.unitCost ?? 0) * oh(it));

    return ListView(
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1200),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(40, 30, 40, 44),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _header(t, repo, orgId, sites: sites, centerMode: centerMode),
                  const SizedBox(height: 24),
                  // Fila de cifras.
                  InventoryStatRow(
                    articleCount: items.length,
                    reorderCount: reorderCount,
                    outCount: outCount,
                    valueCents: _cents(invValuePesos) ?? 0,
                    consumoCurrent: consumo.current,
                    consumoPrev: consumo.prev,
                    prevMonthLabel: consumo.prevLabel,
                  ),
                  if (sinPrecioCount > 0) ...[
                    const SizedBox(height: 16),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 18, vertical: 14),
                      decoration: BoxDecoration(
                        color: Colors.orange.shade50,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.orange.shade200),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.warning_amber_rounded,
                              color: Colors.orange.shade800, size: 20),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              '$sinPrecioCount ${sinPrecioCount == 1 ? 'insumo tiene' : 'insumos tienen'} '
                              'costo pero no precio de venta: se cobrarán a costo. '
                              'Captura su precio para no vender sin margen.',
                              style: TextStyle(
                                  color: Colors.orange.shade900,
                                  fontSize: 13.5),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 20),
                  // Barra de acciones.
                  _cardBox(
                    t,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 22, vertical: 18),
                    child: KuraActionBar(
                      searchHint: 'Buscar por nombre, SKU o proveedor',
                      searchController: _searchCtrl,
                      onSearchChanged: (v) => setState(() => _query = v),
                      primaryLabel: 'Agregar artículo',
                      primaryIcon: Icons.add,
                      onPrimary: () => _addItem(repo, orgId),
                      moreActions: [
                        if (mirrorUnified)
                          KuraMenuAction(
                            label: 'Sincronizar existencias con Shopify',
                            icon: Icons.sync,
                            onSelected: () => _syncShopify(repo, orgId),
                          ),
                        KuraMenuAction(
                          label: 'Fijar umbral de reorden en lote',
                          icon: Icons.rule,
                          onSelected: () => _batchThreshold(repo, orgId),
                        ),
                        KuraMenuAction(
                          label: 'Descargar catálogo en CSV',
                          icon: Icons.download_outlined,
                          onSelected: () => _downloadCsv(repo, orgId),
                        ),
                        KuraMenuAction(
                          label: 'Cargar CSV',
                          icon: Icons.upload_outlined,
                          onSelected: () => _uploadCsv(repo, orgId),
                        ),
                      ],
                      filters: [
                        _f('Todos', items.length, 'all'),
                        _f('Bajo umbral', lowCount, 'low'),
                        _f('Agotados', outCount, 'out'),
                        _f('Tienda Kura+', storeCount, 'store'),
                        _f('Externos', externalCount, 'external'),
                        _f('Sin umbral', noThresholdCount, 'nothreshold'),
                      ],
                      showingText:
                          'Mostrando ${shown.length} de ${items.length}',
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Tabla.
                  _cardBox(
                    t,
                    padding: const EdgeInsets.fromLTRB(24, 22, 24, 8),
                    child: _table(t, repo, shown, oh, shownPz, shownValue),
                  ),
                  const SizedBox(height: 16),
                  // Avisos al pie.
                  _footerNotices(
                    t,
                    repo,
                    orgId,
                    noThresholdCount: noThresholdCount,
                    mirrorUnified: mirrorUnified,
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  KuraFilter _f(String label, int count, String key) => KuraFilter(
        label: label,
        count: count,
        selected: _filter == key,
        onTap: () => setState(() => _filter = key),
      );

  // ---------------- Encabezado ----------------
  Widget _header(BrandTokens t, DataRepository repo, String? orgId,
      {required List sites, required bool centerMode}) {
    final showSelector = !centerMode && sites.length > 1;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              InkWell(
                onTap: () => context.go('/insumos'),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.arrow_back, size: 17, color: t.textSecondary),
                    const SizedBox(width: 6),
                    Text('Insumos',
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: t.textSecondary)),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Text('Inventario',
                  style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.02 * 28,
                      color: t.textPrimary)),
            ],
          ),
        ),
        if (showSelector) ...[
          const SizedBox(width: 20),
          _siteSelector(t, sites),
        ],
      ],
    );
  }

  Widget _siteSelector(BrandTokens t, List sites) {
    final current = sites.firstWhere((s) => s.id == _siteId,
        orElse: () => sites.first);
    return Container(
      decoration: BoxDecoration(
        color: t.surface,
        border: Border.all(color: t.border),
        borderRadius: AppRadii.pillR,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _siteId,
          isDense: true,
          icon: Icon(Icons.expand_more, size: 13, color: t.textSecondary),
          borderRadius: AppRadii.mdR,
          selectedItemBuilder: (_) => [
            for (final _ in sites)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.place, size: 15, color: t.brandPrimary),
                  const SizedBox(width: 9),
                  Text(current.name,
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: t.textPrimary)),
                ],
              ),
          ],
          items: [
            for (final s in sites)
              DropdownMenuItem<String>(
                value: s.id as String,
                child: Text(s.name as String,
                    style: const TextStyle(fontSize: 13)),
              ),
          ],
          onChanged: (v) => setState(() => _siteId = v),
        ),
      ),
    );
  }

  Widget _cardBox(BrandTokens t,
          {required Widget child, required EdgeInsets padding}) =>
      Container(
        decoration: BoxDecoration(
          color: t.surface,
          border: Border.all(color: t.border),
          borderRadius: AppRadii.mdR,
        ),
        padding: padding,
        child: child,
      );

  // ---------------- Tabla ----------------
  Widget _table(BrandTokens t, DataRepository repo, List<InventoryItem> shown,
      int Function(InventoryItem) oh, int totalPz, double totalValue) {
    KuraCellStatus stockStatus(InventoryItem it, int h) {
      if (h <= 0) return KuraCellStatus.danger;
      // Sin umbral NO se pinta de aviso: no tiene contra qué compararse.
      if (it.reorderThreshold != null && h <= it.reorderThreshold!) {
        return KuraCellStatus.warning;
      }
      return KuraCellStatus.success;
    }

    return KuraDataTable(
      initialSortColumn: 0,
      columns: const [
        KuraColumn(label: 'Artículo', fraction: 0.30, sortable: true),
        KuraColumn(label: 'Origen', fraction: 0.13, sortable: true),
        KuraColumn(
            label: 'Existencia', fraction: 0.11, numeric: true, sortable: true),
        KuraColumn(label: 'Umbral', fraction: 0.09, numeric: true),
        KuraColumn(label: 'Costo', fraction: 0.10, numeric: true, sortable: true),
        KuraColumn(label: 'Precio', fraction: 0.10, numeric: true),
        KuraColumn(label: 'Valor', fraction: 0.10, numeric: true, sortable: true),
        KuraColumn(label: '', fraction: 0.07, numeric: true),
      ],
      rows: [
        for (final it in shown)
          KuraRow(
            id: it.id,
            cells: _rowCells(t, repo, it, oh(it), stockStatus(it, oh(it))),
          ),
      ],
      totals: [
        KuraCell.custom(
          sortValue: null,
          build: (t) => Text('${shown.length} artículos',
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: t.textSecondary)),
        ),
        null,
        KuraCell.custom(
          build: (t) => Text('${_grouped(totalPz)} pz',
              textAlign: TextAlign.right,
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: t.textPrimary)),
        ),
        null,
        null,
        null,
        KuraCell.custom(
          build: (t) => Text(moneyMXN(_cents(totalValue) ?? 0),
              textAlign: TextAlign.right,
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: t.textPrimary)),
        ),
        null,
      ],
    );
  }

  List<KuraCell> _rowCells(BrandTokens t, DataRepository repo, InventoryItem it,
      int h, KuraCellStatus status) {
    final valueCents =
        it.unitCost == null ? null : ((it.unitCost! * h) * 100).round();
    final low = it.reorderThreshold != null && h <= it.reorderThreshold!;
    return [
      // Artículo — cuadro 30×30 + nombre + proveedor · SKU, tappable → detalle.
      KuraCell.custom(
        sortValue: it.name.toLowerCase(),
        build: (t) => InkWell(
          onTap: () => _openItem(repo, it),
          child: Row(
            children: [
              _thumb(t, it),
              const SizedBox(width: 11),
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(it.name,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: t.textPrimary)),
                    if (_subline(it).isNotEmpty)
                      Text(_subline(it),
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 11, color: t.textDisabled)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      // Origen.
      it.isExternal
          ? KuraCell.pill('Externo', muted: true)
          : KuraCell.pill('Tienda Kura+'),
      // Existencia.
      KuraCell.number(h, unit: 'pz', status: status),
      // Umbral.
      KuraCell.custom(
        sortValue: it.reorderThreshold ?? -1,
        build: (t) => Text(
          it.reorderThreshold?.toString() ?? 'sin fijar',
          textAlign: TextAlign.right,
          style: it.reorderThreshold == null
              ? TextStyle(
                  fontSize: 12,
                  fontStyle: FontStyle.italic,
                  color: t.textDisabled)
              : TextStyle(fontSize: 13, color: t.textSecondary),
        ),
      ),
      // Costo.
      KuraCell.money(_cents(it.unitCost)),
      // Precio (textSecondary). Si hay costo pero no precio, se marca "sin
      // precio" (naranja): se cobrará a costo, dicho en voz alta.
      KuraCell.custom(
        sortValue: it.unitPrice ?? -1,
        build: (t) => (it.unitPrice == null && (it.unitCost ?? 0) > 0)
            ? Text('sin precio',
                textAlign: TextAlign.right,
                style: TextStyle(
                    fontSize: 12,
                    fontStyle: FontStyle.italic,
                    color: Colors.orange.shade800))
            : Text(moneyOrDash(_cents(it.unitPrice)),
                textAlign: TextAlign.right,
                style: TextStyle(fontSize: 13, color: t.textSecondary)),
      ),
      // Valor (w700).
      KuraCell.custom(
        sortValue: (it.unitCost ?? 0) * h,
        build: (t) => Text(moneyOrDash(valueCents),
            textAlign: TextAlign.right,
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: t.textPrimary)),
      ),
      // Acción rápida.
      KuraCell.custom(
        build: (t) => Align(
          alignment: Alignment.centerRight,
          child: InkWell(
            onTap: low
                ? () => _movementDialog(repo, it,
                    sign: 1,
                    title: 'Entrada / reabasto',
                    reasons: const [
                      InventoryReason.compra,
                      InventoryReason.devolucion
                    ])
                : () => _movementDialog(repo, it,
                    sign: -1,
                    title: 'Salida',
                    reasons: const [
                      InventoryReason.consumo,
                      InventoryReason.merma
                    ]),
            child: Text(low ? 'Entrada' : 'Salida',
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: t.brandPrimary)),
          ),
        ),
      ),
    ];
  }

  String _subline(InventoryItem it) {
    final sku = (it.notes ?? '').startsWith('SKU: ')
        ? it.notes!.substring(5).trim()
        : '';
    return [
      if (it.supplier != null && it.supplier!.isNotEmpty) it.supplier!,
      if (sku.isNotEmpty) sku,
    ].join(' · ');
  }

  Widget _thumb(BrandTokens t, InventoryItem it) => ClipRRect(
        borderRadius: BorderRadius.circular(7),
        child: Container(
          width: 30,
          height: 30,
          color: t.chipBg,
          alignment: Alignment.center,
          child: it.imageUrl == null
              ? Icon(
                  it.isExternal
                      ? Icons.inventory_2_outlined
                      : Icons.medical_services_outlined,
                  size: 16,
                  color: t.brandPrimary)
              : Image.network(it.imageUrl!,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => Icon(
                      Icons.image_not_supported_outlined,
                      size: 16,
                      color: t.brandPrimary)),
        ),
      );

  // ---------------- Avisos al pie ----------------
  Widget _footerNotices(BrandTokens t, DataRepository repo, String? orgId,
      {required int noThresholdCount, required bool mirrorUnified}) {
    final cards = <Widget>[
      if (noThresholdCount > 0)
        _noThresholdNotice(t, repo, orgId, noThresholdCount),
      if (mirrorUnified) _shopifyNotice(t, repo, orgId),
    ];
    if (cards.isEmpty) return const SizedBox.shrink();
    return LayoutBuilder(
      builder: (context, c) {
        final narrow = c.maxWidth < 640 || cards.length == 1;
        final w = narrow ? c.maxWidth : (c.maxWidth - 16) / 2;
        return Wrap(
          spacing: 16,
          runSpacing: 16,
          children: [for (final card in cards) SizedBox(width: w, child: card)],
        );
      },
    );
  }

  /// Fuga silenciosa: sin umbral, el artículo NUNCA entra a Reabasto aunque se
  /// agote. Tono aviso (cálido), con los colores del canvas.
  Widget _noThresholdNotice(
      BrandTokens t, DataRepository repo, String? orgId, int count) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFFFFBF3),
        border: Border.all(color: const Color(0xFFF2DCB0)),
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                    '$count artículo${count == 1 ? '' : 's'} '
                    '${count == 1 ? 'no tiene' : 'no tienen'} umbral fijado',
                    style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF8A5A0B))),
                const SizedBox(height: 3),
                const Text(
                    'Sin umbral nunca aparecen en Reabasto, aunque se agoten.',
                    style: TextStyle(fontSize: 11, color: Color(0xFFA9812F))),
              ],
            ),
          ),
          const SizedBox(width: 12),
          TextButton(
            onPressed: () => _batchThreshold(repo, orgId),
            style: TextButton.styleFrom(
              backgroundColor: const Color(0xFF8A5A0B),
              foregroundColor: Colors.white,
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('Fijarlo en lote',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  /// Estado de Shopify. NOTA: hoy no hay marca de tiempo real del último sync
  /// (no la expone el repo) → texto genérico de respaldo. Pendiente en el doc:
  /// exponer synced_at para decir "hace N min".
  Widget _shopifyNotice(BrandTokens t, DataRepository repo, String? orgId) {
    return _cardBox(
      t,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Sincronizado con Shopify',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: t.textPrimary)),
                const SizedBox(height: 3),
                Text('El stock es el mismo para todo el centro.',
                    style: TextStyle(fontSize: 11, color: t.textSecondary)),
              ],
            ),
          ),
          const SizedBox(width: 12),
          InkWell(
            onTap: _syncing ? null : () => _syncShopify(repo, orgId),
            child: _syncing
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : Text('Sincronizar',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: t.brandPrimary)),
          ),
        ],
      ),
    );
  }

  // ---- Alta de artículo ----
  Future<void> _addItem(DataRepository repo, String? orgId) async {
    if (orgId == null || _siteId == null) return;
    final kind = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.storefront_outlined),
              title: const Text('Producto de la tienda Kura+'),
              subtitle: const Text('Trae foto y precio; se puede reabastecer.'),
              onTap: () => Navigator.of(context).pop('store'),
            ),
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Producto externo (otro proveedor)'),
              subtitle: const Text('Captura manual: nombre, costo, proveedor.'),
              onTap: () => Navigator.of(context).pop('external'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (kind == null || !mounted) return;

    InventoryItem? created;
    if (kind == 'store') {
      final picked = await showShopifyProductPicker(context, repo,
          title: 'Agregar producto de la tienda al inventario');
      if (picked == null) return;
      created = await repo.addInventoryItem(
        organizationId: orgId,
        siteId: _siteId!,
        name: picked.displayName,
        shopifyProductId: picked.shopifyProductId,
        shopifyVariantId: picked.shopifyVariantId,
        imageUrl: picked.imageUrl,
        unitCost: picked.price,
        currency: picked.currency,
        createdBy: ref.read(sessionProvider).user?.id,
      );
    } else {
      created = await _externalForm(repo, orgId);
    }
    if (created == null || !mounted) return;
    setState(() {});
    // Ofrecer registrar existencia inicial.
    await _movementDialog(repo, created, sign: 1, title: 'Existencia inicial',
        reasons: const [InventoryReason.conteo, InventoryReason.compra]);
  }

  Future<InventoryItem?> _externalForm(DataRepository repo, String orgId) async {
    final nameCtrl = TextEditingController();
    final costCtrl = TextEditingController();
    final priceCtrl = TextEditingController();
    final supplierCtrl = TextEditingController();
    final thresholdCtrl = TextEditingController();
    // Una vez que el usuario toca el precio, el costo deja de autocompletarlo (si no,
    // pisa lo que capturó). Y al enfocar el precio se selecciona todo, para que escribir
    // encima REEMPLACE en vez de concatenar (120→156.00, teclear 199 daba 156.00199).
    var priceTouched = false;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
        title: const Text('Producto externo'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(labelText: 'Nombre *'),
              ),
              TextField(
                controller: supplierCtrl,
                decoration: const InputDecoration(labelText: 'Proveedor (opcional)'),
              ),
              TextField(
                controller: costCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Costo unitario (opcional)'),
                // Autocompleta el precio con el default (costo / 0.75) SOLO si el usuario no lo ha
                // tocado (si ya lo capturó, no se le pisa).
                onChanged: (v) {
                  final p = defaultSalePriceFromCost(double.tryParse(v.trim()));
                  if (p != null && !priceTouched) {
                    priceCtrl.text = p.toStringAsFixed(2);
                    setD(() {});
                  }
                },
              ),
              TextField(
                controller: priceCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                    labelText: 'Precio de venta al paciente (default: costo / 0.75)'),
                // Al enfocar/tocar, seleccionar todo → escribir encima reemplaza.
                onTap: () => priceCtrl.selection = TextSelection(
                    baseOffset: 0, extentOffset: priceCtrl.text.length),
                // El usuario ya capturó su precio: el costo ya no lo autocompleta.
                onChanged: (_) => priceTouched = true,
              ),
              TextField(
                controller: thresholdCtrl,
                keyboardType: TextInputType.number,
                decoration:
                    const InputDecoration(labelText: 'Umbral de reorden (opcional)'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Crear')),
        ],
      ),
      ),
    );
    if (ok != true || nameCtrl.text.trim().isEmpty) return null;
    return repo.addInventoryItem(
      organizationId: orgId,
      siteId: _siteId!,
      name: nameCtrl.text.trim(),
      isExternal: true,
      unitCost: double.tryParse(costCtrl.text.trim()),
      unitPrice: double.tryParse(priceCtrl.text.trim()),
      supplier: supplierCtrl.text.trim().isEmpty ? null : supplierCtrl.text.trim(),
      reorderThreshold: int.tryParse(thresholdCtrl.text.trim()),
      createdBy: ref.read(sessionProvider).user?.id,
    );
  }

  // ---- Detalle del artículo ----
  Future<void> _openItem(DataRepository repo, InventoryItem item) async {
    final isAdmin = ref.read(sessionProvider).user?.isAdmin ?? false;
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _ItemDetailSheet(
        repo: repo,
        item: item,
        onEntrada: () => _movementDialog(repo, item, sign: 1,
            title: 'Entrada / reabasto',
            reasons: const [InventoryReason.compra, InventoryReason.devolucion]),
        onSalida: () => _movementDialog(repo, item, sign: -1, title: 'Salida',
            reasons: const [InventoryReason.consumo, InventoryReason.merma]),
        onAjuste: () => _adjustDialog(repo, item),
        onEditPrices: isAdmin
            ? () {
                Navigator.of(context).pop();
                _editPrices(repo, item);
              }
            : null,
      ),
    );
    if (mounted) setState(() {});
  }

  /// Fija el umbral de reorden en LOTE para el sitio actual. Recupera al centro
  /// que cargó su inventario sin umbral (por CSV) y hoy no ve nada en Reabasto,
  /// sin tener que re-dar de alta cada artículo.
  Future<void> _batchThreshold(DataRepository? repo, String? orgId) async {
    if (repo == null || orgId == null || _siteId == null) return;
    final valueCtrl = TextEditingController();
    var onlyMissing = true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: const Text('Umbral de reorden en lote'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                  'Fija el umbral (existencia mínima) de varios artículos de '
                  'este sitio a la vez.',
                  style: TextStyle(fontSize: 13)),
              const SizedBox(height: 8),
              TextField(
                controller: valueCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Umbral'),
              ),
              RadioListTile<bool>(
                contentPadding: EdgeInsets.zero,
                value: true,
                groupValue: onlyMissing,
                title: const Text('Solo a los que no tienen umbral'),
                onChanged: (v) => setD(() => onlyMissing = v ?? true),
              ),
              RadioListTile<bool>(
                contentPadding: EdgeInsets.zero,
                value: false,
                groupValue: onlyMissing,
                title: const Text('A todos los del sitio'),
                onChanged: (v) => setD(() => onlyMissing = v ?? false),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('Cancelar')),
            FilledButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: const Text('Aplicar')),
          ],
        ),
      ),
    );
    if (ok != true) return;
    final value = int.tryParse(valueCtrl.text.trim());
    if (value == null || value < 0) return;
    final items = repo
        .listInventoryItems(organizationId: orgId, siteId: _siteId)
        .where((it) => !onlyMissing || it.reorderThreshold == null)
        .toList();
    for (final it in items) {
      await repo.updateInventoryItem(it.id, reorderThreshold: value);
    }
    if (mounted) {
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content:
              Text('Umbral $value aplicado a ${items.length} artículo(s).')));
    }
  }

  Future<void> _editPrices(DataRepository repo, InventoryItem item) async {
    final costCtrl = TextEditingController(
        text: item.unitCost == null ? '' : '${item.unitCost}');
    final priceCtrl = TextEditingController(
        text: item.unitPrice == null ? '' : '${item.unitPrice}');
    final thresholdCtrl = TextEditingController(
        text: item.reorderThreshold?.toString() ?? '');
    // Si ya hay un precio guardado, se considera "tocado": el costo NO lo pisa (antes,
    // editar el costo clobbereaba el precio real del centro con costo+30%).
    var priceTouched = priceCtrl.text.trim().isNotEmpty;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: const Text('Costo, precio y umbral'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(item.name, style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              TextField(
                controller: costCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Costo (del centro)'),
                onChanged: (v) {
                  final p = defaultSalePriceFromCost(double.tryParse(v.trim()));
                  if (p != null && !priceTouched) {
                    priceCtrl.text = p.toStringAsFixed(2);
                    setD(() {});
                  }
                },
              ),
              TextField(
                controller: priceCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                    labelText: 'Precio de venta (al paciente)'),
                onTap: () => priceCtrl.selection = TextSelection(
                    baseOffset: 0, extentOffset: priceCtrl.text.length),
                onChanged: (_) => priceTouched = true,
              ),
              TextField(
                controller: thresholdCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                    labelText: 'Umbral de reorden (existencia mínima)',
                    helperText: 'Debajo de este nivel aparece en Reabasto'),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('Cancelar')),
            FilledButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: const Text('Guardar')),
          ],
        ),
      ),
    );
    if (ok != true) return;
    // Precio por la regla única: si el usuario lo dejó en blanco pero hay costo,
    // se deriva (costo / 0.75) para no dejar el insumo con costo y sin precio.
    final editCost = double.tryParse(costCtrl.text.trim());
    final editPrice = resolveSalePrice(
        price: double.tryParse(priceCtrl.text.trim()), cost: editCost);
    await repo.updateInventoryItem(
      item.id,
      unitCost: editCost,
      unitPrice: editPrice,
      reorderThreshold: int.tryParse(thresholdCtrl.text.trim()),
    );
    if (mounted) setState(() {});
  }

  Future<void> _movementDialog(DataRepository repo, InventoryItem item,
      {required int sign,
      required String title,
      required List<InventoryReason> reasons}) async {
    final qtyCtrl = TextEditingController();
    final noteCtrl = TextEditingController();
    var reason = reasons.first;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: Text(title),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(item.name, style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              TextField(
                controller: qtyCtrl,
                keyboardType: TextInputType.number,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Cantidad (piezas)'),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<InventoryReason>(
                value: reason,
                decoration: const InputDecoration(labelText: 'Motivo'),
                items: [
                  for (final r in reasons)
                    DropdownMenuItem(value: r, child: Text(r.label)),
                ],
                onChanged: (v) => setD(() => reason = v ?? reason),
              ),
              TextField(
                controller: noteCtrl,
                decoration: const InputDecoration(labelText: 'Nota (opcional)'),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('Cancelar')),
            FilledButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: const Text('Registrar')),
          ],
        ),
      ),
    );
    if (ok != true) return;
    final qty = int.tryParse(qtyCtrl.text.trim()) ?? 0;
    if (qty <= 0) return;
    await repo.addInventoryMovement(
      item: item,
      delta: sign * qty,
      reason: reason,
      unitCost: sign > 0 ? item.unitCost : null,
      note: noteCtrl.text.trim().isEmpty ? null : noteCtrl.text.trim(),
      createdBy: ref.read(sessionProvider).user?.id,
    );
    if (mounted) setState(() {});
  }

  Future<void> _adjustDialog(DataRepository repo, InventoryItem item) async {
    final current = repo.onHandFor(item.id);
    final ctrl = TextEditingController(text: '$current');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Ajuste por conteo físico'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(item.name, style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text('Existencia actual: $current'),
            const SizedBox(height: 8),
            TextField(
              controller: ctrl,
              keyboardType: TextInputType.number,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Existencia real (conteo)'),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Ajustar')),
        ],
      ),
    );
    if (ok != true) return;
    final real = int.tryParse(ctrl.text.trim());
    if (real == null) return;
    final delta = real - current;
    if (delta == 0) return;
    await repo.addInventoryMovement(
      item: item,
      delta: delta,
      reason: InventoryReason.conteo,
      note: 'Ajuste por conteo físico',
      createdBy: ref.read(sessionProvider).user?.id,
    );
    if (mounted) setState(() {});
  }
}

/// Agrupador de miles local (para totales de la tabla en piezas).
String _grouped(int n) => n
    .toString()
    .replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (m) => ',');

class _ItemDetailSheet extends StatelessWidget {
  final DataRepository repo;
  final InventoryItem item;
  final Future<void> Function() onEntrada;
  final Future<void> Function() onSalida;
  final Future<void> Function() onAjuste;
  final VoidCallback? onEditPrices; // solo admin
  const _ItemDetailSheet({
    required this.repo,
    required this.item,
    required this.onEntrada,
    required this.onSalida,
    required this.onAjuste,
    this.onEditPrices,
  });

  String _money(double? v, [String? cur]) =>
      v == null ? '—' : '\$${v.toStringAsFixed(2)} ${cur ?? 'MXN'}';

  @override
  Widget build(BuildContext context) {
    final onHand = repo.onHandFor(item.id);
    final movements = repo.listInventoryMovements(inventoryItemId: item.id);
    final fmt = DateFormat('dd/MM/yyyy HH:mm');
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 4,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: ConstrainedBox(
        constraints:
            BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.85),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(item.name, style: const TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 2),
            Text(
              [
                item.isExternal ? 'Externo' : 'Tienda Kura+',
                if (item.supplier != null && item.supplier!.isNotEmpty) item.supplier!,
              ].join(' · '),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Costo ${_money(item.unitCost, item.currency)}   ·   '
                    'Precio ${_money(item.unitPrice, item.currency)}',
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                ),
                if (onEditPrices != null)
                  TextButton.icon(
                    icon: const Icon(Icons.edit_outlined, size: 16),
                    label: const Text('Editar'),
                    onPressed: onEditPrices,
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Text('Existencia: ',
                    style: Theme.of(context).textTheme.bodyMedium),
                Text('$onHand',
                    style: const TextStyle(
                        fontSize: 22, fontWeight: FontWeight.w800)),
                if (item.reorderThreshold != null) ...[
                  const SizedBox(width: 8),
                  Text('(umbral ${item.reorderThreshold})',
                      style: Theme.of(context).textTheme.bodySmall),
                ],
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: [
                FilledButton.tonalIcon(
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Entrada'),
                  onPressed: () async {
                    Navigator.of(context).pop();
                    await onEntrada();
                  },
                ),
                FilledButton.tonalIcon(
                  icon: const Icon(Icons.remove, size: 18),
                  label: const Text('Salida'),
                  onPressed: () async {
                    Navigator.of(context).pop();
                    await onSalida();
                  },
                ),
                OutlinedButton.icon(
                  icon: const Icon(Icons.tune, size: 18),
                  label: const Text('Ajuste'),
                  onPressed: () async {
                    Navigator.of(context).pop();
                    await onAjuste();
                  },
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Text('Movimientos', style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Flexible(
              child: movements.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.symmetric(vertical: 16),
                      child: Text('Sin movimientos.'))
                  : ListView.separated(
                      shrinkWrap: true,
                      itemCount: movements.length,
                      separatorBuilder: (_, __) => const Divider(height: 8),
                      itemBuilder: (_, i) {
                        final m = movements[i];
                        final pos = m.delta > 0;
                        return Row(
                          children: [
                            Text(pos ? '+${m.delta}' : '${m.delta}',
                                style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    color: pos
                                        ? BrandTokens.of(context).statusSuccess
                                        : BrandTokens.of(context).statusDanger)),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(m.reason.label,
                                      style: const TextStyle(fontSize: 13)),
                                  Text(
                                    '${fmt.format(m.createdAt)}'
                                    '${m.note != null && m.note!.isNotEmpty ? ' · ${m.note}' : ''}',
                                    style: const TextStyle(fontSize: 11),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
