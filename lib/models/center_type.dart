/// Tipo de centro (organización). Ver 0040_center_types_memberships.sql
/// (organizations.center_type). Determina la paleta de marca (morado/azul/
/// rosa, ver BrandTokens.forCenterType) y los módulos por defecto (Fase 2).
///
/// Modelo PURO (sin Flutter): el mapeo a colores/tema vive en
/// lib/core/design/tokens.dart para no acoplar los modelos a Material.
enum CenterType {
  clinicaHeridas,
  hospital,
  cuidadores,
}

extension CenterTypeX on CenterType {
  /// Valor persistido en organizations.center_type (snake_case).
  String get dbValue {
    switch (this) {
      case CenterType.clinicaHeridas:
        return 'clinica_heridas';
      case CenterType.hospital:
        return 'hospital';
      case CenterType.cuidadores:
        return 'cuidadores';
    }
  }

  String get label {
    switch (this) {
      case CenterType.clinicaHeridas:
        return 'Clínica de heridas';
      case CenterType.hospital:
        return 'Hospital';
      case CenterType.cuidadores:
        return 'Cuidadores';
    }
  }

  String get description {
    switch (this) {
      case CenterType.clinicaHeridas:
        return 'Enfocado en tratamiento de heridas';
      case CenterType.hospital:
        return 'Hospitalario, con prevención y agenda de cuidados';
      case CenterType.cuidadores:
        return 'Cuidado en domicilio, con agenda para el cuidador';
    }
  }

  static CenterType fromDb(String? s) {
    switch (s) {
      case 'hospital':
        return CenterType.hospital;
      case 'cuidadores':
        return CenterType.cuidadores;
      case 'clinica_heridas':
      default:
        return CenterType.clinicaHeridas;
    }
  }
}
