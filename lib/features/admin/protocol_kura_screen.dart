import 'package:flutter/material.dart';

import '../../core/theme/kura_theme.dart';
import '../../models/note_option_catalog.dart';
import '../../services/data_repository.dart';

/// Recomendación genérica del motor por categoría del protocolo (para "ver"
/// qué propone cada paso). Es descriptivo; lo que aplica el centro son sus
/// materiales asignados.
const Map<KuraTag, String> _catRecomendacion = {
  KuraTag.limpieza: 'Solución salina / Prontosan',
  KuraTag.desbridamiento: 'Cortante / autolítico / enzimático',
  KuraTag.rellenoCavidad: 'Alginato de calcio / gasa impregnada',
  KuraTag.aposito: 'Espuma con borde / alta absorción',
  KuraTag.proteccionPiel: 'Película barrera / óxido de zinc',
  KuraTag.antimicrobiano: 'PHMB / plata (antimicrobiano tópico)',
  KuraTag.compresion: 'Compresión según ABI',
  KuraTag.descarga: 'Calzado / bota / TCC',
  KuraTag.educacion: 'Material educativo + demostración',
};

NoteOptionField _fieldForTag(KuraTag t) =>
    NoteOptionField.procedureDesc.availableTags.contains(t)
        ? NoteOptionField.procedureDesc
        : NoteOptionField.materialsUsed;

/// Configuración manual del Protocolo Kura+ vista POR CATEGORÍA: por cada paso
/// del protocolo, el admin marca qué conceptos de su catálogo pertenecen (y ve
/// el producto comercial mapeado de los materiales). Internamente asigna la
/// etiqueta kura_tag del concepto; aquí se presenta protocolo-primero.
class ProtocolKuraScreen extends StatefulWidget {
  final DataRepository repo;
  final String? organizationId;
  const ProtocolKuraScreen({
    super.key,
    required this.repo,
    required this.organizationId,
  });
  @override
  State<ProtocolKuraScreen> createState() => _ProtocolKuraScreenState();
}

class _ProtocolKuraScreenState extends State<ProtocolKuraScreen> {
  DataRepository get repo => widget.repo;
  String? get orgId => widget.organizationId;

  static const _procedimiento = [
    KuraTag.limpieza,
    KuraTag.desbridamiento,
    KuraTag.educacion,
  ];
  static const _material = [
    KuraTag.rellenoCavidad,
    KuraTag.aposito,
    KuraTag.proteccionPiel,
    KuraTag.antimicrobiano,
    KuraTag.compresion,
    KuraTag.descarga,
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Protocolo Kura+')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
        children: [
          Text(
            'Asigna, por cada paso del protocolo, los conceptos de tu catálogo. '
            'Cuando el motor sugiera ese paso en una consulta, se pre-marcarán '
            'estos conceptos (siempre editable). Un concepto pertenece a un solo '
            'paso.',
            style: TextStyle(fontSize: 13, color: KuraColors.darkText.withOpacity(0.7)),
          ),
          const SizedBox(height: 16),
          _sectionLabel('Procedimiento'),
          ..._procedimiento.map(_categoryCard),
          const SizedBox(height: 8),
          _sectionLabel('Material'),
          ..._material.map(_categoryCard),
        ],
      ),
    );
  }

  Widget _sectionLabel(String s) => Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 4),
        child: Text(s,
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
      );

  Widget _categoryCard(KuraTag tag) {
    final field = _fieldForTag(tag);
    final assigned = repo
        .listNoteOptions(field, organizationId: orgId)
        .where((o) => o.kuraTag == tag)
        .toList();
    final isMaterial = field == NoteOptionField.materialsUsed;
    final premium = repo.premiumInsumosFor(orgId);

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(tag.label,
                          style: const TextStyle(
                              fontWeight: FontWeight.w700, fontSize: 15)),
                      Text('Sugiere: ${_catRecomendacion[tag] ?? ''}',
                          style: TextStyle(
                              fontSize: 12,
                              color: KuraColors.darkText.withOpacity(0.6))),
                    ],
                  ),
                ),
                TextButton.icon(
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  label: const Text('Asignar'),
                  onPressed: () => _editAssignments(tag, field),
                ),
              ],
            ),
            const SizedBox(height: 6),
            if (assigned.isEmpty)
              Text('Sin conceptos asignados a este paso.',
                  style: TextStyle(
                      fontSize: 12, color: KuraColors.darkText.withOpacity(0.5)))
            else
              ...assigned.map((o) {
                final names = isMaterial && premium
                    ? repo.commercialNamesForCenterMaterial(orgId, o.label)
                    : const <String>[];
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.check_circle,
                          size: 16, color: KuraColors.primary),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(o.label,
                                style: const TextStyle(fontSize: 13)),
                            if (names.isNotEmpty)
                              Text('→ ${names.join(', ')}',
                                  style: const TextStyle(
                                      fontSize: 12, color: KuraColors.primary)),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'Quitar',
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(Icons.close, size: 16),
                        onPressed: () => _setTag(o, null),
                      ),
                    ],
                  ),
                );
              }),
            if (isMaterial && !premium)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                    'Activa Insumos premium para ver/ligar el producto comercial.',
                    style: TextStyle(
                        fontSize: 11, color: KuraColors.darkText.withOpacity(0.5))),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _setTag(NoteOptionCatalogItem o, KuraTag? tag) async {
    try {
      await repo.setNoteOptionKuraTag(o.id, tag);
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('No se pudo actualizar: $e')));
      }
    }
  }

  /// Hoja para marcar qué conceptos del campo pertenecen a esta categoría.
  /// Marcar asigna la etiqueta a este paso (moviéndolo de otro si lo tenía);
  /// desmarcar la quita.
  Future<void> _editAssignments(KuraTag tag, NoteOptionField field) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (bctx) => StatefulBuilder(
        builder: (bctx, setSheet) {
          final options = repo.listNoteOptions(field, organizationId: orgId);
          return SafeArea(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(bctx).size.height * 0.8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 2),
                    child: Text('Conceptos para "${tag.label}"',
                        style: const TextStyle(
                            fontWeight: FontWeight.w800, fontSize: 16)),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                    child: Text(
                        'Marca los conceptos de "${field.label}" que correspondan a este paso.',
                        style: TextStyle(
                            fontSize: 12,
                            color: KuraColors.darkText.withOpacity(0.6))),
                  ),
                  Flexible(
                    child: options.isEmpty
                        ? const Padding(
                            padding: EdgeInsets.all(24),
                            child: Center(
                                child: Text(
                                    'No hay conceptos en este campo del catálogo.')))
                        : ListView(
                            shrinkWrap: true,
                            children: [
                              for (final o in options)
                                CheckboxListTile(
                                  dense: true,
                                  controlAffinity:
                                      ListTileControlAffinity.leading,
                                  value: o.kuraTag == tag,
                                  title: Text(o.label,
                                      style: const TextStyle(fontSize: 13)),
                                  subtitle: o.kuraTag != null && o.kuraTag != tag
                                      ? Text('Ahora en: ${o.kuraTag!.label}',
                                          style: const TextStyle(fontSize: 11))
                                      : null,
                                  onChanged: (v) async {
                                    await repo.setNoteOptionKuraTag(
                                        o.id, v == true ? tag : null);
                                    setSheet(() {});
                                  },
                                ),
                            ],
                          ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
    if (mounted) setState(() {});
  }
}
