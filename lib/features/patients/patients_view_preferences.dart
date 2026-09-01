import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../engine/models/kura_engine_enums.dart';
import '../../engine/sheehan_decision_style.dart';

/// Vista de la pantalla de pacientes: Lista (default, la original) o
/// Tarjeta (nueva, GridView responsivo).
enum PatientsViewMode { list, grid }

/// Filtro de estado de heridas activas, aplicado por igual a lista y
/// tarjeta (punto 4 del rediseno).
enum PatientsStatusFilter { all, withActiveWounds, withoutActiveWounds }

/// Snapshot inmutable de la vista elegida + filtros aplicados en
/// [PatientsListScreen]. Se persiste completo en shared_preferences (NO
/// localStorage -- esto es Flutter Web/movil, shared_preferences ya usa
/// el almacenamiento nativo de cada plataforma) para sobrevivir un reload
/// de pagina o un reinicio de la app.
class PatientsViewPreferences {
  final PatientsViewMode viewMode;
  final String query;
  final Set<Etiologia> etiologies;
  final PatientsStatusFilter statusFilter;
  final String? siteId;
  // "Estatus de avance" (semaforo de trayectoria, seccion checkpoint de
  // Sheehan): filtro multi-seleccion INDEPENDIENTE de statusFilter (ese es
  // "tiene/no tiene heridas activas"; este es "como va" la trayectoria de
  // cierre de las heridas activas). Vacio = sin filtrar por este criterio.
  final Set<ProgressStatus> progressStatuses;

  const PatientsViewPreferences({
    this.viewMode = PatientsViewMode.list,
    this.query = '',
    this.etiologies = const {},
    this.statusFilter = PatientsStatusFilter.all,
    this.siteId,
    this.progressStatuses = const {},
  });

  PatientsViewPreferences copyWith({
    PatientsViewMode? viewMode,
    String? query,
    Set<Etiologia>? etiologies,
    PatientsStatusFilter? statusFilter,
    Object? siteId = _unset,
    Set<ProgressStatus>? progressStatuses,
  }) {
    return PatientsViewPreferences(
      viewMode: viewMode ?? this.viewMode,
      query: query ?? this.query,
      etiologies: etiologies ?? this.etiologies,
      statusFilter: statusFilter ?? this.statusFilter,
      siteId: siteId == _unset ? this.siteId : siteId as String?,
      progressStatuses: progressStatuses ?? this.progressStatuses,
    );
  }

  bool get hasActiveFilters =>
      etiologies.isNotEmpty ||
      statusFilter != PatientsStatusFilter.all ||
      siteId != null ||
      progressStatuses.isNotEmpty;

  Map<String, dynamic> toJson() => {
        'viewMode': viewMode.name,
        'query': query,
        'etiologies': etiologies.map((e) => e.name).toList(),
        'statusFilter': statusFilter.name,
        'siteId': siteId,
        'progressStatuses': progressStatuses.map((e) => e.name).toList(),
      };

  factory PatientsViewPreferences.fromJson(Map<String, dynamic> json) {
    return PatientsViewPreferences(
      viewMode: PatientsViewMode.values.firstWhere(
        (v) => v.name == json['viewMode'],
        orElse: () => PatientsViewMode.list,
      ),
      // La busqueda de texto deliberadamente NO se persiste entre sesiones
      // (una busqueda vieja de otro paciente confundiria mas de lo que
      // ayuda al volver a abrir la pantalla); solo se restaura vista +
      // filtros estructurados.
      query: '',
      etiologies: ((json['etiologies'] as List?) ?? const [])
          .map((s) => Etiologia.values.firstWhere(
                (e) => e.name == s,
                orElse: () => Etiologia.otra,
              ))
          .toSet(),
      statusFilter: PatientsStatusFilter.values.firstWhere(
        (v) => v.name == json['statusFilter'],
        orElse: () => PatientsStatusFilter.all,
      ),
      siteId: json['siteId'] as String?,
      progressStatuses: ((json['progressStatuses'] as List?) ?? const [])
          .map((s) => ProgressStatus.values.firstWhere(
                (e) => e.name == s,
                orElse: () => ProgressStatus.noData,
              ))
          .toSet(),
    );
  }
}

const _unset = Object();

/// Persistencia en shared_preferences de [PatientsViewPreferences].
///
/// Clave unica bajo el mismo prefijo de dominio que el resto de la app
/// (ver LocalStore._keyPrefix); esta clase NO reutiliza LocalStore porque
/// no es una "coleccion" de datos clinicos sino una preferencia de UI del
/// dispositivo/usuario actual.
class PatientsViewPreferencesStore {
  static const String _key = 'kuratracker_patients_view_prefs';

  static Future<PatientsViewPreferences> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return const PatientsViewPreferences();
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      return PatientsViewPreferences.fromJson(json);
    } catch (_) {
      // Preferencia corrupta/de una version anterior incompatible: se
      // ignora y se vuelve al default en vez de romper la pantalla.
      return const PatientsViewPreferences();
    }
  }

  static Future<void> save(PatientsViewPreferences prefs) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_key, jsonEncode(prefs.toJson()));
  }

  /// Borra las preferencias persistidas (filtros/vista). Se llama al re-sembrar
  /// la demo: los datos cambian y un filtro viejo (p. ej. un estatus de avance
  /// que ya no coincide) dejaría el listado en blanco al abrir. Sobrevive a
  /// wipeAll del store porque su key no lleva el prefijo del LocalStore.
  static Future<void> clear() async {
    final sp = await SharedPreferences.getInstance();
    await sp.remove(_key);
  }
}
