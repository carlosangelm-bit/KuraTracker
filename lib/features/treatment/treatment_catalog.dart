/// Catalogo de metodos y productos para seleccion manual (paso 3), usado
/// cuando el modo premium esta desactivado o el clinico decide editar
/// manualmente. Refleja el listado de la seccion 6.2.
class TreatmentCatalog {
  static const Map<String, List<String>> methodToProducts = {
    'Desbridamiento': ['Autolítico', 'Cortante', 'Enzimático', 'Mecánico'],
    'Limpieza de la herida': ['Jabón antibacterial', 'Prontosan', 'Solución salina'],
    'Antisépticos': ['PHMB', 'Yodo povidona', 'Clorhexidina'],
    'Protección de la piel': ['Película barrera', 'Óxido de zinc', 'Crema barrera'],
    'Apósito': [
      'Espuma con borde adhesivo',
      'Alginato',
      'Hidrocoloide',
      'Hidrofibra',
      'Gasa simple',
    ],
    'Tratamiento para la infección': ['PHMB', 'Plata', 'Miel médica', 'Cadexómero de yodo'],
  };

  static List<String> get methods => methodToProducts.keys.toList();
}
