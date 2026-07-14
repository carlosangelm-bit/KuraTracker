/// Catalogo de metodos y productos para seleccion manual (paso 3), usado
/// cuando el modo premium esta desactivado o el clinico decide editar
/// manualmente. Refleja el listado de la seccion 6.2.
///
/// IMPORTANTE (fix bug #6, 14-jul-2026): esta es la UNICA fuente de verdad
/// de nombres de metodo/producto para el UI del paso 3. Los nombres aqui
/// deben coincidir EXACTAMENTE (incluyendo acentos) con los literales que
/// emite `KuraTreatmentRulesEngine` (lib/engine/rules/kura_treatment_rules_engine.dart),
/// para que al activar "Utilizar protocolo Kura+" el dropdown de
/// Metodo/Producto pueda preseleccionar la sugerencia del motor en vez de
/// quedar en blanco. Si se agrega o cambia un metodo/producto en el motor,
/// se debe reflejar aqui tambien. Como red de seguridad adicional, el
/// dropdown en treatment_step_screen.dart tambien inyecta como opcion
/// cualquier metodo/producto sugerido que no este en este catalogo (para
/// que ninguna sugerencia del protocolo quede vacia aunque este archivo se
/// desactualice).
class TreatmentCatalog {
  static const Map<String, List<String>> methodToProducts = {
    'Limpieza de la herida': [
      'Solución salina / Prontosan',
      'Jabón antibacterial',
      'Prontosan',
      'Solución salina',
    ],
    'Desbridamiento': [
      'Cortante / combinado',
      'Autolítico / enzimático / mecánico',
      'Autolítico',
      'Cortante',
      'Enzimático',
      'Mecánico',
    ],
    'Relleno de cavidad': [
      'Alginato de calcio / gasa impregnada',
    ],
    'Apósito': [
      'Espuma con borde adhesivo / alta absorción',
      'Espuma con borde adhesivo',
      'Alginato',
      'Hidrocoloide',
      'Hidrofibra',
      'Gasa simple',
    ],
    'Protección de la piel': [
      'Película barrera / óxido de zinc',
      'Película barrera',
      'Óxido de zinc',
      'Crema barrera',
    ],
    'Antisépticos': ['PHMB', 'Yodo povidona', 'Clorhexidina'],
    'Tratamiento para la infección': [
      'PHMB / plata',
      'PHMB',
      'Plata',
      'Miel médica',
      'Cadexómero de yodo',
    ],
    'Educación al paciente/cuidador': [
      'Material educativo + demostración práctica',
    ],
    // ---- Pie diabético ----
    'Dispositivo de descarga': [
      'Calzado terapéutico / plantilla de descarga',
      'Bota walker removible (descarga parcial)',
      'TCC (Total Contact Cast) o bota walker con descarga total',
      'Descarga total + valoración quirúrgica urgente',
    ],
    'Manejo neuropático': [
      'Evaluación de sensibilidad + control glucémico estrecho',
    ],
    // ---- Vascular ----
    'Terapia compresiva': [
      'Compresión fuerte (30-40 mmHg)',
      'Compresión reducida (18-25 mmHg), supervisión estrecha',
      'No aplica (isquemia crítica)',
      'Compresión moderada (20-30 mmHg) — confirmar ABI antes de iniciar',
    ],
    // ---- Quirúrgica ----
    'Manejo de herida quirúrgica': [
      'Vigilancia + cuidado de herida estándar',
      'Manejo local intensivo + reevaluación en 48-72h',
      'Manejo local intensivo + interconsulta a cirugía',
      'Manejo urgente: dehiscencia/infección grave',
    ],
    // ---- Traumática ----
    'Manejo de herida por mordedura': [
      'Profilaxis antibiótica + lavado abundante',
    ],
    'Manejo de herida por arma de fuego': [
      'Exploración quirúrgica + descarte de lesión profunda',
    ],
    'Manejo de herida por aplastamiento': [
      'Vigilancia de síndrome compartimental + manejo de tejidos',
    ],
    'Manejo de herida punzocortante': [
      'Exploración de estructuras profundas + cierre según caso',
    ],
    'Manejo de herida traumática': [
      'Según evaluación clínica del mecanismo de lesión',
    ],
  };

  static List<String> get methods => methodToProducts.keys.toList();
}
