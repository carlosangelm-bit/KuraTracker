import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/design/tokens.dart';
import '../../core/providers/session_provider.dart';
import '../../core/router/app_shell.dart' show UserMenuButton;
import '../../models/patient.dart';
import '../../models/vac_therapy.dart';
import '../../services/data_repository.dart';
import 'vac_therapy_form.dart';

/// Módulo Terapia VAC (Fase 1): lista de terapias del centro. La terapia sigue
/// al paciente (transversal: hospital / clínica / domicilio). Toca "+" para
/// registrar una nueva eligiendo al paciente; toca una tarjeta para ver el
/// detalle y su bitácora.
class VacTherapiesScreen extends ConsumerStatefulWidget {
  const VacTherapiesScreen({super.key});

  @override
  ConsumerState<VacTherapiesScreen> createState() =>
      _VacTherapiesScreenState();
}

class _VacTherapiesScreenState extends ConsumerState<VacTherapiesScreen> {
  @override
  Widget build(BuildContext context) {
    final repoAsync = ref.watch(dataRepositoryProvider);
    final orgId = ref.watch(sessionProvider).user?.organizationId;
    final t = BrandTokens.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Terapia VAC'),
        actions: const [UserMenuButton()],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _newTherapy(orgId),
        icon: const Icon(Icons.add),
        label: const Text('Nueva terapia'),
      ),
      body: repoAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, st) => Center(child: Text('Error: $e')),
        data: (repo) {
          final all = repo.listVacTherapies(organizationId: orgId);
          final active = all.where((x) => x.isActive).toList();
          final past = all.where((x) => !x.isActive).toList();
          if (all.isEmpty) {
            return const _Empty();
          }
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
            children: [
              if (active.isNotEmpty) ...[
                _Label('Activas (${active.length})'),
                ...active.map((x) => _TherapyCard(repo: repo, therapy: x, t: t)),
              ],
              if (past.isNotEmpty) ...[
                const SizedBox(height: 12),
                _Label('Finalizadas / suspendidas (${past.length})'),
                ...past.map((x) => _TherapyCard(repo: repo, therapy: x, t: t)),
              ],
            ],
          );
        },
      ),
    );
  }

  Future<void> _newTherapy(String? orgId) async {
    if (orgId == null) return;
    final repo = ref.read(dataRepositoryProvider).valueOrNull;
    if (repo == null) return;
    final patients = repo.listAllPatients()
        .where((p) => p.organizationId == orgId)
        .toList()
      ..sort((a, b) =>
          a.fullName.toLowerCase().compareTo(b.fullName.toLowerCase()));
    if (patients.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('No hay pacientes en este centro.')));
      return;
    }
    final patientId = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _PatientPickerSheet(repo: repo, patients: patients),
    );
    if (patientId == null || !mounted) return;
    final saved = await showVacTherapyForm(context, ref,
        orgId: orgId, patientId: patientId);
    // Refleja la terapia recién creada sin recargar la página.
    if (saved == true && mounted) setState(() {});
  }
}

class _TherapyCard extends StatelessWidget {
  final DataRepository repo;
  final VacTherapy therapy;
  final BrandTokens t;
  const _TherapyCard({required this.repo, required this.therapy, required this.t});

  @override
  Widget build(BuildContext context) {
    final patient = repo.getPatient(therapy.patientId);
    final statusColor = therapy.status == VacTherapyStatus.activa
        ? t.statusSuccess
        : therapy.status == VacTherapyStatus.suspendida
            ? t.statusDanger
            : t.textSecondary;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        onTap: () => context.push('/vac/${therapy.id}'),
        leading: CircleAvatar(
          backgroundColor: t.brandPrimary.withValues(alpha: 0.12),
          child: Icon(Icons.healing_outlined, color: t.brandPrimary),
        ),
        title: Text(patient?.fullName ?? 'Paciente',
            style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(therapy.equipment.label, style: const TextStyle(fontSize: 12)),
            if (therapy.settingsLabel.isNotEmpty)
              Text(therapy.settingsLabel,
                  style: TextStyle(fontSize: 12, color: t.textSecondary)),
            if (therapy.currentLocation != null)
              Text(therapy.currentLocation!.label,
                  style: TextStyle(fontSize: 12, color: t.textSecondary)),
          ],
        ),
        trailing: Chip(
          label: Text(therapy.status.label,
              style: TextStyle(fontSize: 11, color: statusColor)),
          backgroundColor: statusColor.withValues(alpha: 0.10),
          side: BorderSide.none,
          visualDensity: VisualDensity.compact,
        ),
      ),
    );
  }
}

class _Label extends StatelessWidget {
  final String text;
  const _Label(this.text);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
        child: Text(text,
            style: TextStyle(
                fontWeight: FontWeight.w700,
                color: BrandTokens.of(context).textSecondary)),
      );
}

/// Selector de paciente para crear una terapia: busca por nombre / piso / área
/// / cama y filtra por piso y área (ubicación del internamiento activo).
class _PatientPickerSheet extends StatefulWidget {
  final DataRepository repo;
  final List<Patient> patients;
  const _PatientPickerSheet({required this.repo, required this.patients});
  @override
  State<_PatientPickerSheet> createState() => _PatientPickerSheetState();
}

class _PatientPickerSheetState extends State<_PatientPickerSheet> {
  String _q = '';
  String? _floor;
  String? _area;
  final _floorOf = <String, String?>{};
  final _areaOf = <String, String?>{};
  final _locOf = <String, String>{};
  final _searchOf = <String, String>{};
  List<String> _floors = const [];
  List<String> _areas = const [];

  static String _fold(String s) {
    s = s.toLowerCase().trim();
    const from = 'áàäâãéèëêíìïîóòöôõúùüûñ';
    const to = 'aaaaaeeeeiiiiooooouuuun';
    final b = StringBuffer();
    for (final ch in s.runes) {
      final c = String.fromCharCode(ch);
      final i = from.indexOf(c);
      b.write(i >= 0 ? to[i] : c);
    }
    return b.toString();
  }

  @override
  void initState() {
    super.initState();
    for (final p in widget.patients) {
      final adm = widget.repo.activeAdmission(p.id);
      _floorOf[p.id] = adm?.floor;
      _areaOf[p.id] = adm?.area;
      _locOf[p.id] = adm?.locationLabel ?? '';
      _searchOf[p.id] = _fold(
          '${p.fullName} ${adm?.floor ?? ''} ${adm?.area ?? ''} ${adm?.bed ?? ''}');
    }
    _floors = _floorOf.values.whereType<String>().toSet().toList()..sort();
    _areas = _areaOf.values.whereType<String>().toSet().toList()..sort();
  }

  @override
  Widget build(BuildContext context) {
    final q = _fold(_q);
    final list = widget.patients.where((p) {
      if (_floor != null && _floorOf[p.id] != _floor) return false;
      if (_area != null && _areaOf[p.id] != _area) return false;
      if (q.isNotEmpty && !(_searchOf[p.id] ?? '').contains(q)) return false;
      return true;
    }).toList();

    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 4,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: ConstrainedBox(
        constraints:
            BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.85),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Paciente para la terapia',
                style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            TextField(
              autofocus: true,
              onChanged: (v) => setState(() => _q = v),
              decoration: const InputDecoration(
                isDense: true,
                hintText: 'Buscar por nombre, piso, área o cama…',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
              ),
            ),
            if (_floors.isNotEmpty || _areas.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (_floors.isNotEmpty)
                    _filter('Piso', _floor, _floors,
                        (v) => setState(() => _floor = v)),
                  if (_areas.isNotEmpty)
                    _filter('Área', _area, _areas,
                        (v) => setState(() => _area = v)),
                ],
              ),
            ],
            const SizedBox(height: 8),
            Flexible(
              child: list.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.all(24),
                      child: Center(child: Text('Sin coincidencias.')))
                  : ListView.separated(
                      shrinkWrap: true,
                      itemCount: list.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (_, i) {
                        final p = list[i];
                        final loc = _locOf[p.id] ?? '';
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(p.fullName),
                          subtitle: loc.isEmpty
                              ? const Text('Sin internamiento',
                                  style: TextStyle(fontSize: 12))
                              : Text(loc, style: const TextStyle(fontSize: 12)),
                          onTap: () => Navigator.of(context).pop(p.id),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _filter(String label, String? value, List<String> options,
      ValueChanged<String?> onChanged) {
    return DropdownButton<String?>(
      value: value,
      hint: Text(label, style: const TextStyle(fontSize: 13)),
      underline: const SizedBox.shrink(),
      items: [
        DropdownMenuItem<String?>(
            value: null, child: Text('$label: todos', style: const TextStyle(fontSize: 13))),
        ...options.map((o) => DropdownMenuItem<String?>(
            value: o, child: Text(o, style: const TextStyle(fontSize: 13)))),
      ],
      onChanged: onChanged,
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty();
  @override
  Widget build(BuildContext context) => const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.healing_outlined, size: 40),
              SizedBox(height: 10),
              Text('Sin terapias VAC registradas.\nToca "Nueva terapia" para empezar.',
                  textAlign: TextAlign.center),
            ],
          ),
        ),
      );
}
