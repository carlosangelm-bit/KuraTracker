import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:csv/csv.dart';
import 'package:file_picker/file_picker.dart';

import '../../core/design/tokens.dart';
import '../../core/design/tints.dart';
import '../../core/widgets/kura_data_table.dart';
import '../../core/widgets/kura_action_bar.dart';
import '../../core/widgets/kura_module_lock.dart';
import '../../core/widgets/kura_empty_state.dart';
import '../../core/widgets/dashed_border_box.dart';
import '../../models/note_option_catalog.dart';
import '../../services/csv_download.dart';
import '../../services/data_repository.dart';

/// Configuración del catálogo de conceptos de la nota de seguimiento (sección de
/// Administración). Salió de admin_home_screen.dart (cierre de «Admin del centro»), con
/// el mismo patrón que las etapas 1-3. Es un CUERPO de sección: NO se envuelve en
/// KuraScreen; AdminSectionsShell ya pinta el encabezado y el riel. Todo color desde
/// [BrandTokens].
class NoteCatalogScreen extends StatefulWidget {
  final DataRepository repo;
  final String? organizationId;
  const NoteCatalogScreen({super.key, required this.repo, required this.organizationId});

  @override
  State<NoteCatalogScreen> createState() => _NoteCatalogScreenState();
}

class _NoteCatalogScreenState extends State<NoteCatalogScreen> {
  NoteOptionField _selectedField = NoteOptionField.careType;
  String _search = '';

  /// Carga el catalogo base curado (mismo contenido que la precarga de
  /// 0010_note_option_catalog.sql) para este centro. Pensado sobre todo
  /// para un centro nuevo, recien creado desde Plataforma por el master,
  /// que arranca con las 4 secciones completamente vacias (createOrganization()
  /// deliberadamente NO siembra catalogo, ver DataRepository) -- este boton
  /// evita tener que dar de alta uno por uno los conceptos mas comunes.
  /// Es un merge, no un reemplazo: solo agrega lo que falte, nunca duplica
  /// ni pisa conceptos ya personalizados o desactivados por el admin.
  Future<void> _loadDefaultCatalog() async {
    final organizationId = widget.organizationId;
    if (organizationId == null) return;
    try {
      final summary = await widget.repo.seedDefaultNoteOptions(organizationId: organizationId);
      if (mounted) {
        setState(() {});
        final msg = summary.added > 0
            ? 'Se agregaron ${summary.added} conceptos base al catálogo.'
            : 'El catálogo base ya estaba cargado; no se agregó nada nuevo.';
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo cargar el catálogo base: $e')),
        );
      }
    } finally {
      if (mounted) setState(() {});
    }
  }

  // Alternativa manual (preservada tal cual, sin rehacer): "Nuevo concepto"
  // sigue siendo la unica accion del FAB.
  Future<void> _addOption() async {
    final label = await _promptForLabel(context, title: 'Nuevo concepto');
    if (label == null || label.trim().isEmpty) return;
    try {
      await widget.repo.createNoteOption(
        field: _selectedField,
        label: label.trim(),
        organizationId: widget.organizationId,
      );
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo agregar: $e')),
        );
      }
    }
  }

  /// Descarga la plantilla CSV (columnas seccion,concepto,activo) con el
  /// catalogo ACTUAL del centro (las 4 secciones), para que el admin la
  /// edite en Excel/Sheets y luego la vuelva a cargar.
  Future<void> _downloadTemplate() async {
    final rows = <List<String>>[
      ['seccion', 'concepto', 'activo'],
    ];
    for (final field in NoteOptionField.values) {
      for (final o in widget.repo.listAllNoteOptions(field, organizationId: widget.organizationId)) {
        rows.add([field.csvSeccion, o.label, o.isActive ? 'true' : 'false']);
      }
    }
    final csvContent = const ListToCsvConverter().convert(rows);
    try {
      await downloadCsv('catalogo_notas_seguimiento.csv', csvContent);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo descargar la plantilla: $e')),
        );
      }
    }
  }

  /// Carga un CSV (mismas columnas de la plantilla) y hace merge en bloque
  /// de las 4 secciones via DataRepository.bulkImportNoteOptions.
  Future<void> _uploadCsv() async {
    final organizationId = widget.organizationId;
    if (organizationId == null) return;
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
      final rawRows = const CsvToListConverter(eol: '\n').convert(content);
      if (rawRows.isEmpty) {
        throw StateError('El archivo está vacío.');
      }
      // Se descarta el encabezado (fila 0); se acepta el orden
      // seccion,concepto,activo tal cual lo produce _downloadTemplate().
      final dataRows = rawRows.skip(1);
      final parsed = <NoteOptionImportRow>[];
      for (final r in dataRows) {
        if (r.isEmpty || r.every((c) => c.toString().trim().isEmpty)) continue;
        final seccion = r.isNotEmpty ? r[0].toString() : '';
        final concepto = r.length > 1 ? r[1].toString() : '';
        final activoRaw = r.length > 2 ? r[2].toString().trim().toLowerCase() : 'true';
        final activo = activoRaw == 'true' || activoRaw == '1' || activoRaw == 'si' || activoRaw == 'sí';
        parsed.add(NoteOptionImportRow(seccion: seccion, concepto: concepto, activo: activo));
      }

      final summary = await widget.repo.bulkImportNoteOptions(
        parsed,
        organizationId: organizationId,
      );

      if (mounted) {
        setState(() {});
        await showDialog<void>(
          context: context,
          builder: (dialogCtx) => AlertDialog(
            title: const Text('Resumen de importación'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Agregados: ${summary.added}'),
                Text('Actualizados: ${summary.updated}'),
                Text('Omitidos: ${summary.skipped}'),
                if (summary.errors.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  const Text('Detalle:', style: TextStyle(fontWeight: FontWeight.w600)),
                  ...summary.errors.take(10).map((e) => Text('• $e', style: const TextStyle(fontSize: 12))),
                ],
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogCtx),
                child: const Text('Cerrar'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo importar el CSV: $e')),
        );
      }
    } finally {
      if (mounted) setState(() {});
    }
  }

  Future<void> _toggleActive(NoteOptionCatalogItem item) async {
    try {
      await widget.repo.setNoteOptionActive(item.id, !item.isActive);
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo actualizar: $e')),
        );
      }
    }
  }

  /// Cambia la etiqueta kura_tag de un concepto (dropdown "Sin etiqueta" +
  /// las 9 categorias del motor Protocolo Kura+, ver
  /// 0013_note_option_catalog_kura_tag.sql). Es el puente que permite, mas
  /// adelante, que el toggle premium de la nota de seguimiento pre-marque
  /// este concepto cuando su etiqueta coincida con el regimen sugerido.
  Future<void> _setKuraTag(NoteOptionCatalogItem item, KuraTag? tag) async {
    try {
      await widget.repo.setNoteOptionKuraTag(item.id, tag);
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo actualizar la etiqueta: $e')),
        );
      }
    }
  }

  /// Borra un concepto del catalogo, previa confirmacion. Borrar solo
  /// quita el concepto de las opciones futuras (chips al capturar una
  /// nota); las notas de seguimiento ya guardadas conservan el texto
  /// del concepto tal cual, no una referencia a esta fila, asi que el
  /// historial no se ve afectado.
  //
  // IMPORTANTE (bug #8, pantalla en blanco): el dialogo de confirmacion
  // usa builder: (dialogCtx) => ... y Navigator.pop(dialogCtx, ...) -- el
  // context propio del dialogo, no el context externo de NoteCatalogScreen.
  // La app usa ShellRoute (navegador anidado): reutilizar el context
  // externo en el pop cierra la ruta de fondo en vez del dialogo, dejando
  // la pantalla en blanco sin ninguna excepcion de Dart capturable.
  Future<void> _deleteOption(NoteOptionCatalogItem item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Borrar concepto'),
        content: const Text(
          '¿Borrar este concepto? No afecta las notas ya guardadas.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogCtx, true),
            style: FilledButton.styleFrom(backgroundColor: BrandTokens.of(dialogCtx).statusDanger),
            child: const Text('Borrar'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await widget.repo.deleteNoteOption(item.id);
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo borrar: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = BrandTokens.of(context);
    final adminLocked = !widget.repo.premiumAdminFor(widget.organizationId);
    return Scaffold(
      body: ListView(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 96),
        children: [
          Text(
            'Configuración del centro',
            style: TextStyle(
                fontSize: AppType.display,
                fontWeight: AppType.extrabold,
                letterSpacing: -0.02 * AppType.display,
                color: t.textPrimary),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Lo que tu equipo ve al capturar, los protocolos que sigue y la '
            'constancia de lo que sale del expediente.',
            style: TextStyle(fontSize: AppType.body, color: t.textSecondary),
          ),
          const SizedBox(height: 26),
          _grupo1(t, adminLocked),
          const SizedBox(height: 26),
          _grupo2(t, adminLocked),
          const SizedBox(height: 26),
          _grupo3(t),
        ],
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Grupo 1 — Catálogo de la nota de seguimiento
  // -------------------------------------------------------------------------
  Widget _grupo1(BrandTokens t, bool adminLocked) {
    final all = widget.repo
        .listAllNoteOptions(_selectedField, organizationId: widget.organizationId);
    final q = _search.trim().toLowerCase();
    final options =
        q.isEmpty ? all : all.where((o) => o.label.toLowerCase().contains(q)).toList();
    final taggable = _selectedField.availableTags.isNotEmpty;

    return _groupCard(
      t,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Catálogo de la nota de seguimiento',
                      style: TextStyle(
                          fontSize: 19,
                          fontWeight: AppType.bold,
                          letterSpacing: -0.01 * 19,
                          color: t.textPrimary),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      'Los conceptos que tu personal clínico ve como opciones al '
                      'registrar una nota. Se configura una vez para todo el centro.',
                      style: TextStyle(fontSize: 13, color: t.textSecondary),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 24),
              _primaryPill(t, 'Nuevo concepto', _addOption),
              const SizedBox(width: 10),
              _herramientasMenu(t, adminLocked),
            ],
          ),
          const SizedBox(height: 20),
          KuraActionBar(
            searchHint: 'Buscar concepto',
            onSearchChanged: (v) => setState(() => _search = v),
            filters: [
              for (final f in NoteOptionField.values)
                KuraFilter(
                  label: f.label,
                  count: widget.repo
                      .listAllNoteOptions(f, organizationId: widget.organizationId)
                      .length,
                  selected: f == _selectedField,
                  onTap: () => setState(() => _selectedField = f),
                ),
            ],
            showingText: 'Mostrando ${options.length} de ${all.length}',
          ),
          const SizedBox(height: 16),
          if (options.isEmpty)
            KuraEmptyState(
              icon: Icons.list_alt_outlined,
              title: q.isEmpty ? 'Sin conceptos en esta sección' : 'Sin coincidencias',
              message: q.isEmpty
                  ? 'Agrega el primer concepto de "${_selectedField.label}", o carga el catálogo base curado por Kura+.'
                  : 'Ningún concepto coincide con "$_search".',
              primaryLabel: 'Nuevo concepto',
              onPrimary: _addOption,
              secondaryLabel: q.isEmpty ? 'Cargar catálogo base' : null,
              onSecondary: q.isEmpty ? _loadDefaultCatalog : null,
            )
          else
            KuraDataTable(
              columns: [
                KuraColumn(
                    label: 'Concepto',
                    fraction: taggable ? 0.44 : 0.71,
                    sortable: true),
                if (taggable)
                  const KuraColumn(
                      label: 'Paso del Protocolo Kura+', fraction: 0.27),
                const KuraColumn(label: 'Estado', fraction: 0.15, sortable: true),
                const KuraColumn(label: 'Acciones', fraction: 0.14, numeric: true),
              ],
              rows: [
                for (final o in options)
                  KuraRow(
                    id: o.id,
                    cells: [
                      KuraCell.custom(
                        sortValue: o.label.toLowerCase(),
                        build: (t) => Text(
                          o.label,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: AppType.semibold,
                            color: o.isActive ? t.textPrimary : t.textDisabled,
                            decoration:
                                o.isActive ? null : TextDecoration.lineThrough,
                          ),
                        ),
                      ),
                      if (taggable)
                        (o.kuraTag != null &&
                                _selectedField.availableTags.contains(o.kuraTag)
                            ? KuraCell.pill(o.kuraTag!.label)
                            : KuraCell.custom(
                                sortValue: '',
                                build: (t) => Text('Sin asignar',
                                    style: TextStyle(
                                        fontSize: 12, color: t.textDisabled)),
                              )),
                      KuraCell.custom(
                        sortValue: o.isActive ? 1 : 0,
                        build: (t) => Text(
                          o.isActive ? 'Activo' : 'Inactivo',
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: AppType.bold,
                              color:
                                  o.isActive ? t.statusSuccess : t.textDisabled),
                        ),
                      ),
                      KuraCell.custom(
                        // FittedBox: en la columna angosta (14%) "Editar · Desactivar"
                        // se encoge en vez de desbordar.
                        build: (t) => Align(
                          alignment: Alignment.centerRight,
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerRight,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                _rowAction(t, 'Editar', () => _editDialog(o)),
                                Text(' · ',
                                    style: TextStyle(
                                        fontSize: 12, color: t.textDisabled)),
                                _rowAction(
                                    t,
                                    o.isActive ? 'Desactivar' : 'Activar',
                                    () => _toggleActive(o)),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          const SizedBox(height: 10),
          _footnote(t),
        ],
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Grupo 2 — Tu propio protocolo (el módulo pagado)
  // -------------------------------------------------------------------------
  Widget _grupo2(BrandTokens t, bool adminLocked) {
    return _groupCard(
      t,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Tu propio protocolo',
              style: TextStyle(
                  fontSize: 19, fontWeight: AppType.bold, color: t.textPrimary)),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Escribe los pasos que sigue tu centro y qué producto usa en cada '
            'uno, en vez de usar el protocolo curado por Kura+.',
            style: TextStyle(fontSize: 13, color: t.textSecondary),
          ),
          const SizedBox(height: 20),
          // Banda de bloqueo: se pinta sola solo si el módulo NO está contratado.
          KuraModuleLock.band(
            repo: widget.repo,
            organizationId: widget.organizationId ?? '',
            moduleKey: 'admin',
            moduleName: 'Estas seis funciones son del módulo Administración avanzada',
            description:
                'Incluye además 3 usuarios administrativos, varias sedes y tu '
                'marca en los reportes. IVA incluido.',
          ),
          if (adminLocked) const SizedBox(height: 16),
          _reja(t, [
            _CfgTile(
              icon: Icons.auto_awesome,
              name: 'Protocolo Kura+',
              desc: 'Qué conceptos van en cada paso',
              locked: adminLocked,
              onOpen: () => context.go('/admin/protocolo-kura'),
            ),
            _CfgTile(
              icon: Icons.inventory_2_outlined,
              name: 'Productos del protocolo',
              desc: 'Qué insumo y cuánto, por paso',
              locked: adminLocked,
              onOpen: () => context.go('/admin/productos-protocolo'),
            ),
            _CfgTile(
              icon: Icons.upload_outlined,
              name: 'Cargar catálogo por CSV',
              desc: 'Sube tus conceptos en bloque',
              locked: adminLocked,
              onOpen: _uploadCsv,
            ),
            _CfgTile(
              icon: Icons.event_repeat_outlined,
              name: 'Tipo de cita para sesiones',
              desc: 'Integración con Acuity',
              locked: adminLocked,
              onOpen: () => context.go('/admin/tipo-cita-sesiones'),
            ),
            _CfgTile(
              icon: Icons.medical_information_outlined,
              name: 'Tipos de consulta',
              desc: 'Valoración o seguimiento, en Acuity',
              locked: adminLocked,
              onOpen: () => context.go('/admin/tipos-consulta'),
            ),
            _CfgTile(
              icon: Icons.cleaning_services_outlined,
              name: 'Depurar expedientes',
              desc: 'Archivar en bloque contra tu padrón',
              locked: adminLocked,
              onOpen: () => context.go('/admin/depurar-expedientes'),
            ),
          ]),
        ],
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Grupo 3 — Expediente y cumplimiento (nunca se gatea)
  // -------------------------------------------------------------------------
  Widget _grupo3(BrandTokens t) {
    return _groupCard(
      t,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Expediente y cumplimiento',
                        style: TextStyle(
                            fontSize: 19,
                            fontWeight: AppType.bold,
                            color: t.textPrimary)),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      'Lo que la ley te exige poder hacer con tu expediente. Nunca '
                      'depende de un módulo ni de que el pago esté al día.',
                      style: TextStyle(fontSize: 13, color: t.textSecondary),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: Tints.status(t.statusSuccess, t.surface, 0.12),
                  borderRadius: AppRadii.pillR,
                ),
                child: Text('Siempre incluido',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: AppType.bold,
                        color: t.statusSuccess)),
              ),
            ],
          ),
          const SizedBox(height: 20),
          _reja(t, [
            _CfgTile(
              icon: Icons.fact_check_outlined,
              name: 'Registro de divulgaciones',
              desc: 'Constancia de cada salida de datos',
              locked: false,
              onOpen: () => context.go('/admin/divulgaciones'),
            ),
            _CfgTile(
              icon: Icons.rule_folder_outlined,
              name: 'Escalas del protocolo',
              desc: 'Cuáles participan en tu centro',
              locked: false,
              onOpen: () => context.go('/admin/escalas-protocolo'),
            ),
            _CfgTile(
              icon: Icons.menu_book_outlined,
              name: 'Fuente de recomendaciones',
              desc: 'De dónde sale cada sugerencia',
              locked: false,
              onOpen: () => context.go('/admin/fuente-recomendaciones'),
            ),
            _CfgTile(
              icon: Icons.download_outlined,
              name: 'Descargar plantilla CSV',
              desc: 'Tu catálogo actual, en hoja',
              locked: false,
              onOpen: _downloadTemplate,
            ),
            _CfgTile(
              icon: Icons.playlist_add_check_outlined,
              name: 'Cargar catálogo base',
              desc: 'Los conceptos curados por Kura+',
              locked: false,
              onOpen: _loadDefaultCatalog,
            ),
            _CfgTile(
              icon: Icons.download_outlined,
              name: 'Exportar el expediente',
              desc: 'Completo, cuando lo necesites',
              locked: false,
              onOpen: () => context.go('/import-export'),
            ),
          ]),
        ],
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Helpers de presentación
  // -------------------------------------------------------------------------
  Widget _groupCard(BrandTokens t, {required Widget child}) => Container(
        decoration: BoxDecoration(
          color: t.surface,
          borderRadius: AppRadii.mdR,
          border: Border.all(color: t.border),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 26),
        child: child,
      );

  Widget _primaryPill(BrandTokens t, String label, VoidCallback onTap) => Material(
        color: t.brandPrimary,
        borderRadius: AppRadii.pillR,
        child: InkWell(
          borderRadius: AppRadii.pillR,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
            child: Text(label,
                style: TextStyle(
                    fontSize: 13, fontWeight: AppType.bold, color: t.onBrand)),
          ),
        ),
      );

  Widget _herramientasMenu(BrandTokens t, bool adminLocked) =>
      PopupMenuButton<int>(
        tooltip: 'Herramientas',
        onSelected: (i) {
          switch (i) {
            case 0:
              _loadDefaultCatalog();
            case 1:
              _downloadTemplate();
            case 2:
              adminLocked ? _openAdminSection() : _uploadCsv();
          }
        },
        itemBuilder: (_) => [
          const PopupMenuItem(value: 0, child: Text('Cargar catálogo base')),
          const PopupMenuItem(value: 1, child: Text('Descargar plantilla CSV')),
          PopupMenuItem(
            value: 2,
            child: Row(
              children: [
                if (adminLocked) ...[
                  Icon(Icons.lock_outline, size: 16, color: t.textDisabled),
                  const SizedBox(width: 6),
                ],
                const Flexible(child: Text('Cargar CSV')),
              ],
            ),
          ),
        ],
        child: Container(
          decoration:
              BoxDecoration(color: t.chipBg, borderRadius: AppRadii.pillR),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Herramientas',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: AppType.bold,
                      color: t.brandPrimary)),
              const SizedBox(width: 4),
              Icon(Icons.keyboard_arrow_down, size: 13, color: t.brandPrimary),
            ],
          ),
        ),
      );

  Widget _rowAction(BrandTokens t, String label, VoidCallback onTap) => InkWell(
        onTap: onTap,
        borderRadius: AppRadii.smR,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          child: Text(label,
              style: TextStyle(fontSize: 12, color: t.textSecondary)),
        ),
      );

  Widget _footnote(BrandTokens t) => Text.rich(
        TextSpan(
          style: TextStyle(fontSize: 11, height: 1.5, color: t.textDisabled),
          children: [
            const TextSpan(text: 'Desactivar oculta el concepto de las notas '
                'nuevas y '),
            TextSpan(
                text: 'no toca',
                style: TextStyle(
                    color: t.textSecondary, fontWeight: AppType.bold)),
            const TextSpan(
                text: ' las notas ya guardadas. El paso del protocolo es lo que '
                    'conecta cada concepto con las sugerencias de Kura+.'),
          ],
        ),
      );

  // Reja responsiva de 3 columnas (2 / 1 en anchos menores).
  Widget _reja(
    BrandTokens t,
    List<_CfgTile> tiles,
  ) =>
      LayoutBuilder(
        builder: (ctx, c) {
          final cols = c.maxWidth >= 720 ? 3 : (c.maxWidth >= 440 ? 2 : 1);
          const gap = 12.0;
          final w = (c.maxWidth - gap * (cols - 1)) / cols;
          return Wrap(
            spacing: gap,
            runSpacing: gap,
            children: [
              for (final tile in tiles)
                SizedBox(width: w, child: _tile(t, tile)),
            ],
          );
        },
      );

  Widget _tile(
    BrandTokens t,
    _CfgTile tile,
  ) {
    final locked = tile.locked;
    final inner = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: t.chipBg,
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(tile.icon,
                size: 18, color: locked ? t.textDisabled : t.brandPrimary),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(tile.name,
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: AppType.bold,
                        color: locked ? t.textSecondary : t.textPrimary)),
                const SizedBox(height: 2),
                Text(tile.desc,
                    style: TextStyle(
                        fontSize: 11, height: 1.45, color: t.textSecondary)),
              ],
            ),
          ),
        ],
      ),
    );
    if (locked) {
      return InkWell(
        borderRadius: AppRadii.mdR,
        onTap: _openAdminSection,
        child: DashedBorderBox(
          color: t.border,
          radius: AppRadii.md,
          fill: Tints.brand(t, 0.02),
          child: inner,
        ),
      );
    }
    return Material(
      color: t.surface,
      borderRadius: AppRadii.mdR,
      child: InkWell(
        borderRadius: AppRadii.mdR,
        onTap: tile.onOpen,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: AppRadii.mdR,
            border: Border.all(color: t.border),
          ),
          child: inner,
        ),
      ),
    );
  }

  // Sección completa del módulo Administración (densidad c), en diálogo. La abre la
  // acción bloqueada y las tarjetas gateadas de la reja del grupo 2.
  void _openAdminSection() {
    showDialog<void>(
      context: context,
      builder: (dialogCtx) {
        final t = BrandTokens.of(dialogCtx);
        return Dialog(
          backgroundColor: t.surface,
          shape: const RoundedRectangleBorder(borderRadius: AppRadii.mdR),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.sm),
            child: KuraModuleLock.section(
              repo: widget.repo,
              organizationId: widget.organizationId ?? '',
              moduleKey: 'admin',
              moduleName: 'Administración avanzada',
              description:
                  'Escribe los pasos que sigue tu centro y qué producto usa en '
                  'cada uno, en vez del protocolo curado por Kura+.',
            ),
          ),
        );
      },
    );
  }

  // "Editar" de una fila: la etiqueta del paso (si el campo la usa) y borrar.
  Future<void> _editDialog(NoteOptionCatalogItem item) async {
    final taggable = _selectedField.availableTags.isNotEmpty;
    await showDialog<void>(
      context: context,
      builder: (dialogCtx) {
        var sel = _selectedField.availableTags.contains(item.kuraTag)
            ? item.kuraTag
            : null;
        return StatefulBuilder(
          builder: (ctx, setLocal) => AlertDialog(
            title: Text(item.label),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (taggable) ...[
                  const Text('Paso del Protocolo Kura+',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                  DropdownButton<KuraTag?>(
                    value: sel,
                    isExpanded: true,
                    items: [
                      const DropdownMenuItem<KuraTag?>(
                          value: null, child: Text('Sin asignar')),
                      ..._selectedField.availableTags.map(
                        (tg) => DropdownMenuItem<KuraTag?>(
                            value: tg, child: Text(tg.label)),
                      ),
                    ],
                    onChanged: (v) {
                      setLocal(() => sel = v);
                      _setKuraTag(item, v);
                    },
                  ),
                  const SizedBox(height: 8),
                ] else
                  const Text('Este campo no usa paso del protocolo.',
                      style: TextStyle(fontSize: 12)),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(dialogCtx);
                  _deleteOption(item);
                },
                child: const Text('Borrar concepto'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogCtx),
                child: const Text('Listo'),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _CfgTile {
  final IconData icon;
  final String name;
  final String desc;
  final bool locked;
  final VoidCallback onOpen;
  const _CfgTile({
    required this.icon,
    required this.name,
    required this.desc,
    required this.locked,
    required this.onOpen,
  });
}

Future<String?> _promptForLabel(BuildContext context, {required String title}) {
  final ctrl = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (dialogCtx) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: ctrl,
        autofocus: true,
        decoration: const InputDecoration(labelText: 'Texto del concepto'),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogCtx),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dialogCtx, ctrl.text),
          style: FilledButton.styleFrom(backgroundColor: BrandTokens.of(dialogCtx).brandPrimary),
          child: const Text('Guardar'),
        ),
      ],
    ),
  );
}

/// Configuración de marca del centro para los reportes PDF: color principal +
/// logo. Se usa en Administración (admin) y Plataforma (master, por centro).
