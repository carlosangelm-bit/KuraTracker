import 'package:flutter/material.dart';

import '../../core/theme/kura_theme.dart';
import '../../engine/cie10_catalog.dart';

/// Color por relación del diagnóstico frente a la herida. Reutilizable por el
/// picker y la pantalla de diagnósticos.
Color diagnosisRelationColor(DiagnosisRelation r) {
  switch (r) {
    case DiagnosisRelation.causa:
      return KuraColors.primary;
    case DiagnosisRelation.comorbilidad:
      return KuraColors.warning;
    case DiagnosisRelation.consecuencia:
      return KuraColors.danger;
    case DiagnosisRelation.herida:
      return KuraColors.success;
  }
}

/// Hoja modal para buscar y elegir un código CIE-10 del catálogo de heridas
/// crónicas. Búsqueda por código o nombre (insensible a mayúsculas/acentos) y
/// filtro por relación. Devuelve el [Cie10Code] elegido, o null si se cerró
/// sin seleccionar.
Future<Cie10Code?> showCie10PickerSheet(
  BuildContext context,
  Cie10Catalog catalog, {
  DiagnosisRelation? initialRelation,
}) {
  return showModalBottomSheet<Cie10Code>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => _Cie10PickerBody(
      catalog: catalog,
      initialRelation: initialRelation,
    ),
  );
}

class _Cie10PickerBody extends StatefulWidget {
  final Cie10Catalog catalog;
  final DiagnosisRelation? initialRelation;
  const _Cie10PickerBody({required this.catalog, this.initialRelation});

  @override
  State<_Cie10PickerBody> createState() => _Cie10PickerBodyState();
}

class _Cie10PickerBodyState extends State<_Cie10PickerBody> {
  final _controller = TextEditingController();
  String _query = '';
  DiagnosisRelation? _relation;

  @override
  void initState() {
    super.initState();
    _relation = widget.initialRelation;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final results = widget.catalog.search(_query, relation: _relation);
    // Deja espacio para el teclado y limita la altura a ~85% de la pantalla.
    final viewInsets = MediaQuery.of(context).viewInsets.bottom;
    final maxHeight = MediaQuery.of(context).size.height * 0.85;

    return Padding(
      padding: EdgeInsets.only(bottom: viewInsets),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 4, 20, 8),
              child: Text('Buscar diagnóstico (CIE-10)',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: TextField(
                controller: _controller,
                autofocus: true,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: 'Código o nombre (ej. E11, úlcera, celulitis)',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                onChanged: (v) => setState(() => _query = v),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 44,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: ChoiceChip(
                      label: const Text('Todas'),
                      selected: _relation == null,
                      onSelected: (_) => setState(() => _relation = null),
                    ),
                  ),
                  for (final r in DiagnosisRelation.values)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: ChoiceChip(
                        label: Text(r.label),
                        selected: _relation == r,
                        selectedColor: diagnosisRelationColor(r).withOpacity(0.16),
                        onSelected: (_) => setState(() => _relation = r),
                      ),
                    ),
                ],
              ),
            ),
            const Divider(height: 1),
            Flexible(
              child: results.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.all(24),
                      child: Text('Sin resultados.'),
                    )
                  : ListView.builder(
                      itemCount: results.length,
                      itemBuilder: (context, i) {
                        final c = results[i];
                        return ListTile(
                          dense: true,
                          leading: CircleAvatar(
                            radius: 4,
                            backgroundColor: diagnosisRelationColor(c.relation),
                          ),
                          title: Text('${c.code} · ${c.name}',
                              style: const TextStyle(fontSize: 13)),
                          subtitle: Text('${c.relation.label} · ${c.subcategory}',
                              style: const TextStyle(fontSize: 11)),
                          onTap: () => Navigator.of(context).pop(c),
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
