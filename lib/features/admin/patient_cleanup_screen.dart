import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/kura_theme.dart';
import '../../models/patient.dart';
import '../../services/data_repository.dart';

/// Depuración de expedientes (0086). Caso de uso: el import histórico de Acuity
/// trajo muchos pacientes que no están en tratamiento. El admin/master pega el
/// padrón vigente (una lista de nombres), la app hace coincidencia difusa
/// (tolera acentos, orden de nombres y apellidos, y nombres intermedios de más)
/// y ARCHIVA el resto — que desaparece de listas y tableros pero conserva sus
/// datos (reversible con "Restaurar").
///
/// PII: los nombres del padrón se pegan EN VIVO por el usuario; nunca se guardan
/// en el código ni en Git. Solo viven en memoria mientras dura la pantalla.
class PatientCleanupScreen extends ConsumerStatefulWidget {
  final DataRepository repo;
  final String? organizationId;
  const PatientCleanupScreen({
    super.key,
    required this.repo,
    required this.organizationId,
  });

  @override
  ConsumerState<PatientCleanupScreen> createState() =>
      _PatientCleanupScreenState();
}

/// Normaliza un nombre para comparar: minúsculas, sin acentos, sin puntuación,
/// espacios colapsados. "María Magdalena Romero Orozco" -> "maria magdalena
/// romero orozco".
String _norm(String s) {
  const from = 'áàäâãéèëêíìïîóòöôõúùüûñç';
  const to = 'aaaaaeeeeiiiiooooouuuunc';
  final buf = StringBuffer();
  for (final ch in s.toLowerCase().trim().runes) {
    final c = String.fromCharCode(ch);
    final idx = from.indexOf(c);
    buf.write(idx >= 0 ? to[idx] : c);
  }
  return buf
      .toString()
      .replaceAll(RegExp(r'[^a-z0-9 ]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

Set<String> _tokens(String s) =>
    _norm(s).split(' ').where((t) => t.length > 1).toSet();

/// ¿El nombre del padrón [roster] y el del expediente [patient] son la misma
/// persona? Coincide si el conjunto de palabras más chico está contenido en el
/// más grande y comparten al menos 2 palabras (evita falsos positivos por un
/// solo nombre de pila común). Tolera orden distinto y nombres intermedios.
bool _sameName(Set<String> roster, Set<String> patient) {
  if (roster.isEmpty || patient.isEmpty) return false;
  final inter = roster.intersection(patient).length;
  if (inter < 2) return false;
  final smaller = roster.length <= patient.length ? roster.length : patient.length;
  return inter == smaller;
}

class _PatientCleanupScreenState extends ConsumerState<PatientCleanupScreen> {
  final _rosterCtrl = TextEditingController();
  bool _analyzed = false;
  bool _working = false;

  // Resultado del análisis (ids de expedientes vigentes del centro).
  final List<Patient> _keep = [];
  final List<Patient> _toArchive = [];
  final List<String> _unmatched = []; // líneas del padrón sin coincidencia

  @override
  void dispose() {
    _rosterCtrl.dispose();
    super.dispose();
  }

  List<Patient> get _activePatients => widget.repo
      .listAllPatients()
      .where((p) => widget.organizationId == null ||
          p.organizationId == widget.organizationId)
      .toList();

  void _analyze() {
    final lines = _rosterCtrl.text
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();
    final rosterTokens = lines.map((l) => MapEntry(l, _tokens(l))).toList();

    final patients = _activePatients;
    final keepIds = <String>{};
    final matchedLines = <String>{};

    for (final entry in rosterTokens) {
      var any = false;
      for (final p in patients) {
        if (_sameName(entry.value, _tokens(p.fullName))) {
          keepIds.add(p.id);
          any = true;
        }
      }
      if (any) matchedLines.add(entry.key);
    }

    setState(() {
      _keep
        ..clear()
        ..addAll(patients.where((p) => keepIds.contains(p.id)));
      _toArchive
        ..clear()
        ..addAll(patients.where((p) => !keepIds.contains(p.id)));
      _unmatched
        ..clear()
        ..addAll(lines.where((l) => !matchedLines.contains(l)));
      _analyzed = true;
    });
  }

  Future<void> _applyArchive() async {
    final n = _toArchive.length;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Archivar $n expediente(s)'),
        content: Text(
          'Se ocultarán $n expediente(s) que NO están en tu lista. '
          'Conservarás ${_keep.length} vigente(s).\n\n'
          'Es reversible: podrás restaurarlos desde esta misma pantalla. '
          'No se borra ningún dato.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text('Archivar $n')),
        ],
      ),
    );
    if (ok != true) return;

    setState(() => _working = true);
    var done = 0;
    final errors = <String>[];
    for (final p in List<Patient>.from(_toArchive)) {
      try {
        await widget.repo.archivePatient(p.id);
        done++;
      } catch (e) {
        errors.add(p.fullName);
      }
    }
    if (!mounted) return;
    setState(() {
      _working = false;
      _analyzed = false;
      _keep.clear();
      _toArchive.clear();
      _unmatched.clear();
    });
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(errors.isEmpty
          ? '$done expediente(s) archivado(s) ✅'
          : '$done archivado(s). ${errors.length} con error.'),
    ));
  }

  Future<void> _restore(Patient p) async {
    setState(() => _working = true);
    try {
      await widget.repo.unarchivePatient(p.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('${p.fullName} restaurado ✅')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error al restaurar: $e')));
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final archived =
        widget.repo.listArchivedPatients(organizationId: widget.organizationId);
    return Scaffold(
      appBar: AppBar(title: const Text('Depurar expedientes')),
      body: AbsorbPointer(
        absorbing: _working,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _intro(),
            const SizedBox(height: 16),
            _rosterInput(),
            if (_analyzed) ...[
              const SizedBox(height: 16),
              _preview(),
            ],
            const SizedBox(height: 24),
            _archivedSection(archived),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _intro() => Card(
        color: KuraColors.infoBlue.withValues(alpha: 0.08),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.cleaning_services_outlined,
                  color: KuraColors.infoBlue),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Pega tu padrón vigente (un nombre por línea). La app conserva '
                  'esos expedientes y ARCHIVA el resto. Archivar es reversible: '
                  'los archivados se ocultan de listas y tableros pero conservan '
                  'todos sus datos y puedes restaurarlos aquí abajo.',
                ),
              ),
            ],
          ),
        ),
      );

  Widget _rosterInput() => Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Padrón vigente',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 4),
              Text(
                'Un nombre por línea. Total de expedientes vigentes en el centro: '
                '${_activePatients.length}.',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: KuraColors.darkText.withValues(alpha: 0.6)),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _rosterCtrl,
                minLines: 6,
                maxLines: 16,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  hintText: 'Victoria Eugenia Iturbide Coca\n'
                      'Cesar Cabrales Cruz\n'
                      'Manuel Morales Muñoz\n...',
                ),
              ),
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.icon(
                  onPressed: _analyze,
                  icon: const Icon(Icons.search),
                  label: const Text('Analizar'),
                ),
              ),
            ],
          ),
        ),
      );

  Widget _preview() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Vista previa',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            _countTile(Icons.check_circle_outline, KuraColors.success,
                'Se conservan', _keep),
            _countTile(Icons.archive_outlined, KuraColors.warning,
                'Se archivarán', _toArchive),
            if (_unmatched.isNotEmpty)
              _unmatchedTile(),
            const Divider(height: 24),
            Row(
              children: [
                Expanded(
                  child: Text(
                    _toArchive.isEmpty
                        ? 'Ningún expediente por archivar con esta lista.'
                        : 'Se archivarán ${_toArchive.length} y se conservarán '
                            '${_keep.length}.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                FilledButton.icon(
                  onPressed: _toArchive.isEmpty ? null : _applyArchive,
                  style: FilledButton.styleFrom(
                      backgroundColor: KuraColors.warning),
                  icon: const Icon(Icons.archive_outlined),
                  label: Text('Archivar ${_toArchive.length}'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _countTile(
      IconData icon, Color color, String label, List<Patient> list) {
    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      leading: Icon(icon, color: color),
      title: Text('$label (${list.length})',
          style: TextStyle(fontWeight: FontWeight.w600, color: color)),
      childrenPadding: const EdgeInsets.only(left: 16, bottom: 8),
      children: list
          .map((p) => ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(p.fullName),
                subtitle: Text(p.folio),
              ))
          .toList(),
    );
  }

  Widget _unmatchedTile() => ExpansionTile(
        tilePadding: EdgeInsets.zero,
        leading: const Icon(Icons.help_outline, color: KuraColors.danger),
        title: Text('Sin coincidencia en el padrón (${_unmatched.length})',
            style: const TextStyle(
                fontWeight: FontWeight.w600, color: KuraColors.danger)),
        subtitle: const Text(
            'Estos nombres de tu lista no encontraron expediente; revisa '
            'la escritura (no se archiva a nadie por ellos).'),
        childrenPadding: const EdgeInsets.only(left: 16, bottom: 8),
        children: _unmatched
            .map((l) => ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.person_off_outlined, size: 18),
                  title: Text(l),
                ))
            .toList(),
      );

  Widget _archivedSection(List<Patient> archived) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.inventory_2_outlined),
                const SizedBox(width: 8),
                Text('Archivados actualmente (${archived.length})',
                    style: Theme.of(context).textTheme.titleMedium),
              ],
            ),
            if (archived.isEmpty) ...[
              const SizedBox(height: 8),
              Text('No hay expedientes archivados.',
                  style: Theme.of(context).textTheme.bodySmall),
            ] else
              ...archived.map((p) => ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text(p.fullName),
                    subtitle: Text(p.folio),
                    trailing: TextButton.icon(
                      onPressed: () => _restore(p),
                      icon: const Icon(Icons.unarchive_outlined, size: 18),
                      label: const Text('Restaurar'),
                    ),
                  )),
          ],
        ),
      ),
    );
  }
}
