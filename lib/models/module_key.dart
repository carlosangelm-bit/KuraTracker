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
  insumos,
  comercial,
  vac,
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
      case ModuleKey.insumos:
        return 'insumos';
      case ModuleKey.comercial:
        return 'comercial';
      case ModuleKey.vac:
        return 'vac';
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
        return 'Importar expedientes';
      case ModuleKey.insumos:
        return 'Insumos';
      case ModuleKey.comercial:
        return 'Comercial';
      case ModuleKey.vac:
        return 'Terapia VAC';
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
      case ModuleKey.insumos:
        return '/insumos';
      case ModuleKey.comercial:
        return '/comercial';
      case ModuleKey.vac:
        return '/vac';
    }
  }

  /// Estado por defecto del módulo según el tipo de centro. Es SOLO una
  /// sugerencia inicial: el master puede sobreescribirlo (p.ej. encender
  /// Prevención en una clínica de heridas). Prevención se apaga por defecto en
  /// clínica de heridas (enfoque en tratamiento) y se enciende en hospital y
  /// cuidadores; reportes se apagan por defecto en cuidadores.
  bool defaultFor(CenterType type) {
    // Importar expedientes (interoperabilidad): APAGADO por defecto en todo tipo
    // de centro. Es un caso raro (un cliente que llega con historia en otra
    // herramienta); el master lo enciende por centro cuando hace falta, sin
    // clavar el nombre de ninguna clínica en el código.
    if (this == ModuleKey.ekare) return false;
    // Insumos/Tienda y Comercial: por default SOLO en clínica de heridas
    // (segmento objetivo). El master puede encenderlos en otro tipo de centro.
    if (this == ModuleKey.insumos || this == ModuleKey.comercial) {
      return type == CenterType.clinicaHeridas;
    }
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

  /// Si el módulo APLICA a este tipo de centro. Un módulo no disponible no se
  /// ofrece en la configuración y queda apagado aunque exista un ajuste previo.
  ///
  /// Todos los módulos están disponibles en todo tipo de centro; el que no deba
  /// verse arranca APAGADO por defecto (ver [defaultFor]) y el master lo
  /// enciende donde haga falta. (Importar expedientes usaba antes un caso
  /// especial para excluirse del hospital; ya no hace falta al arrancar apagado
  /// en todos.)
  bool availableFor(CenterType type) {
    return true;
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
