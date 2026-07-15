import 'package:flutter/material.dart';

import '../../core/theme/kura_theme.dart';
import '../../engine/models/kura_engine_enums.dart';
import '../../engine/sheehan_decision_style.dart';
import '../../models/site.dart';
import 'patients_view_preferences.dart';

/// Barra/panel de filtros compartido por la vista Lista y la vista
/// Tarjeta (punto 4 del rediseno): busqueda de texto (nombre/folio),
/// etiologia (multi-seleccion via chips), estado (heridas activas / sin
/// heridas activas / todos) y sitio. Un solo widget para que ambas vistas
/// se comporten IDENTICO frente a los mismos filtros.
class PatientsFilterBar extends StatefulWidget {
  final String query;
  final ValueChanged<String> onQueryChanged;
  final Set<Etiologia> selectedEtiologies;
  final ValueChanged<Set<Etiologia>> onEtiologiesChanged;
  final PatientsStatusFilter statusFilter;
  final ValueChanged<PatientsStatusFilter> onStatusFilterChanged;
  final List<Site> sites;
  final String? siteId;
  final ValueChanged<String?> onSiteChanged;
  // "Estatus de avance" (semaforo de trayectoria, checkpoint de Sheehan):
  // multi-seleccion, independiente del filtro statusFilter de arriba.
  final Set<ProgressStatus> selectedProgressStatuses;
  final ValueChanged<Set<ProgressStatus>> onProgressStatusesChanged;
  final VoidCallback onClearFilters;
  final bool hasActiveFilters;

  const PatientsFilterBar({
    super.key,
    required this.query,
    required this.onQueryChanged,
    required this.selectedEtiologies,
    required this.onEtiologiesChanged,
    required this.statusFilter,
    required this.onStatusFilterChanged,
    required this.sites,
    required this.siteId,
    required this.onSiteChanged,
    required this.selectedProgressStatuses,
    required this.onProgressStatusesChanged,
    required this.onClearFilters,
    required this.hasActiveFilters,
  });

  @override
  State<PatientsFilterBar> createState() => _PatientsFilterBarState();
}

class _PatientsFilterBarState extends State<PatientsFilterBar> {
  late final TextEditingController _queryController =
      TextEditingController(text: widget.query);

  @override
  void didUpdateWidget(PatientsFilterBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Solo resincroniza el controller si el valor externo cambio por una
    // via distinta a este mismo campo (p.ej. "Limpiar filtros"), para no
    // pisar la posicion del cursor mientras el usuario esta escribiendo.
    if (widget.query != _queryController.text) {
      _queryController.text = widget.query;
    }
  }

  @override
  void dispose() {
    _queryController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _queryController,
            decoration: const InputDecoration(
              hintText: 'Buscar por nombre o folio (EXP2025-...)',
              prefixIcon: Icon(Icons.search),
              isDense: true,
            ),
            onChanged: widget.onQueryChanged,
          ),
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _StatusFilterChip(
                  value: widget.statusFilter,
                  onChanged: widget.onStatusFilterChanged,
                ),
                const SizedBox(width: 8),
                if (widget.sites.isNotEmpty) ...[
                  _SiteFilterChip(
                    sites: widget.sites,
                    value: widget.siteId,
                    onChanged: widget.onSiteChanged,
                  ),
                  const SizedBox(width: 8),
                ],
                for (final etiologia in Etiologia.values) ...[
                  FilterChip(
                    label: Text(etiologia.label),
                    selected: widget.selectedEtiologies.contains(etiologia),
                    onSelected: (selected) {
                      final next = Set<Etiologia>.from(widget.selectedEtiologies);
                      if (selected) {
                        next.add(etiologia);
                      } else {
                        next.remove(etiologia);
                      }
                      widget.onEtiologiesChanged(next);
                    },
                    selectedColor: KuraColors.primary.withOpacity(0.16),
                    checkmarkColor: KuraColors.primary,
                  ),
                  const SizedBox(width: 8),
                ],
                for (final progressStatus in ProgressStatus.values) ...[
                  FilterChip(
                    avatar: Icon(progressStatus.icon,
                        size: 16, color: progressStatus.color),
                    label: Text(progressStatus.shortLabel),
                    selected: widget.selectedProgressStatuses.contains(progressStatus),
                    onSelected: (selected) {
                      final next = Set<ProgressStatus>.from(widget.selectedProgressStatuses);
                      if (selected) {
                        next.add(progressStatus);
                      } else {
                        next.remove(progressStatus);
                      }
                      widget.onProgressStatusesChanged(next);
                    },
                    selectedColor: progressStatus.color.withOpacity(0.16),
                    checkmarkColor: progressStatus.color,
                  ),
                  const SizedBox(width: 8),
                ],
                if (widget.hasActiveFilters)
                  TextButton.icon(
                    onPressed: widget.onClearFilters,
                    icon: const Icon(Icons.filter_alt_off_outlined, size: 16),
                    label: const Text('Limpiar filtros'),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusFilterChip extends StatelessWidget {
  final PatientsStatusFilter value;
  final ValueChanged<PatientsStatusFilter> onChanged;

  const _StatusFilterChip({required this.value, required this.onChanged});

  String _label(PatientsStatusFilter v) {
    switch (v) {
      case PatientsStatusFilter.all:
        return 'Estado: todos';
      case PatientsStatusFilter.withActiveWounds:
        return 'Con heridas activas';
      case PatientsStatusFilter.withoutActiveWounds:
        return 'Sin heridas activas';
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<PatientsStatusFilter>(
      initialValue: value,
      onSelected: onChanged,
      itemBuilder: (context) => PatientsStatusFilter.values
          .map((v) => PopupMenuItem(value: v, child: Text(_label(v))))
          .toList(),
      child: Chip(
        avatar: const Icon(Icons.healing_outlined, size: 16),
        label: Text(_label(value)),
        backgroundColor:
            value != PatientsStatusFilter.all ? KuraColors.primary.withOpacity(0.1) : null,
      ),
    );
  }
}

class _SiteFilterChip extends StatelessWidget {
  final List<Site> sites;
  final String? value;
  final ValueChanged<String?> onChanged;

  const _SiteFilterChip({required this.sites, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final label = value == null
        ? 'Sitio: todos'
        : (sites.where((s) => s.id == value).map((s) => s.name).firstOrNull ?? 'Sitio');
    return PopupMenuButton<String?>(
      initialValue: value,
      onSelected: onChanged,
      itemBuilder: (context) => [
        const PopupMenuItem<String?>(value: null, child: Text('Sitio: todos')),
        for (final s in sites) PopupMenuItem<String?>(value: s.id, child: Text(s.name)),
      ],
      child: Chip(
        avatar: const Icon(Icons.location_on_outlined, size: 16),
        label: Text(label),
        backgroundColor: value != null ? KuraColors.primary.withOpacity(0.1) : null,
      ),
    );
  }
}

extension _FirstOrNullExt<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
