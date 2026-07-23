import 'center_type.dart';

/// Módulos que el master/admin puede encender o apagar por centro/sitio/usuario
/// (Fase 2, ver 0041_module_settings.sql). `dashboard` va siempre encendido y
/// `admin`/`platform` se gatean por rol (no son módulos configurables).
///
/// Apagar un módulo SOLO lo oculta del menú/rutas; los datos permanecen.
enum ModuleKey {
  patients,
  agenda,
  prevention,
  reports,
  ekare,
}

extension ModuleKeyX on ModuleKey {
  String get dbValue {
    switch (this) {
      case ModuleKey.patients:
        return 'patients';
      case ModuleKey.agenda:
        return 'agenda';
      case ModuleKey.prevention:
        return 'prevention';
      case ModuleKey.reports:
        return 'reports';
      case ModuleKey.ekare:
        return 'ekare';
    }
  }

  String get label {
    switch (this) {
      case ModuleKey.patients:
        return 'Pacientes';
      case ModuleKey.agenda:
        return 'Agenda';
      case ModuleKey.prevention:
        return 'Prevención';
      case ModuleKey.reports:
        return 'Reportes';
      case ModuleKey.ekare:
        return 'eKare';
    }
  }

  /// Ruta de navegación de nivel superior asociada al módulo (para gatear el
  /// nav y los redirects del router).
  String get route {
    switch (this) {
      case ModuleKey.patients:
        return '/patients';
      case ModuleKey.agenda:
        return '/agenda';
      case ModuleKey.prevention:
        return '/risk';
      case ModuleKey.reports:
        return '/reports';
      case ModuleKey.ekare:
        return '/import-export';
    }
  }

  /// Estado por defecto del módulo según el tipo de centro. Es SOLO una
  /// sugerencia inicial: el master puede sobreescribirlo (p.ej. encender
  /// Prevención en una clínica de heridas). Prevención se apaga por defecto en
  /// clínica de heridas (enfoque en tratamiento) y se enciende en hospital y
  /// cuidadores; reportes/eKare se apagan por defecto en cuidadores.
  bool defaultFor(CenterType type) {
    switch (type) {
      case CenterType.clinicaHeridas:
        return this != ModuleKey.prevention;
      case CenterType.hospital:
        return true;
      case CenterType.cuidadores:
        return this == ModuleKey.patients ||
            this == ModuleKey.agenda ||
            this == ModuleKey.prevention;
    }
  }

  static ModuleKey? fromDb(String? s) {
    for (final m in ModuleKey.values) {
      if (m.dbValue == s) return m;
    }
    return null;
  }

  /// Módulo asociado a una ruta de nivel superior, o null si la ruta no
  /// corresponde a un módulo configurable (dashboard/admin/platform).
  static ModuleKey? forRoute(String location) {
    for (final m in ModuleKey.values) {
      if (location == m.route || location.startsWith('${m.route}/')) return m;
    }
    return null;
  }
}
