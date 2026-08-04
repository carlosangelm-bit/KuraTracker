import '../../models/patient_lab.dart';

/// Puntaje 0–3 del DOMINIO CLÍNICO de laboratorios (instrumento de María).
///
/// Cada parámetro se puntúa 0 (normal) a 3 (severo) según rangos. HOY es
/// INFORMATIVO: alimenta banderas de severidad en la UI, NO entra al motor de
/// cicatrización (la albúmina sí entra, pero por su propia regla en
/// kura_clinical_adjustments — independiente de este puntaje).
///
/// ⚠️ BORRADOR CLÍNICO (validación pendiente — María). Los umbrales viven aquí,
/// en código, y se ajustan por deploy. Varias filas de la tabla original tienen
/// rangos con traslapes/huecos; se encodearon con la interpretación monotónica
/// más defendible y se anotan con `draftNote`. Parámetros a revisar con María:
/// hematocrito (rangos traslapados y bilaterales), TP y TPP (fronteras
/// ambiguas), proteínas totales y plaquetas (huecos entre bandas), umbral de
/// hipoglucemia (<80 no penalizado en la tabla).

/// Severidad 0..3 con etiqueta legible.
enum LabSeverity {
  normal, // 0
  mild, // 1
  moderate, // 2
  severe, // 3
}

extension LabSeverityX on LabSeverity {
  int get score => index;
  String get label => switch (this) {
        LabSeverity.normal => 'Normal',
        LabSeverity.mild => 'Leve',
        LabSeverity.moderate => 'Moderado',
        LabSeverity.severe => 'Severo',
      };
}

/// Un parámetro puntuado (valor crudo + severidad). `severity == null` cuando el
/// parámetro no se midió (o es N/A para este paciente).
class LabParamScore {
  final String key;
  final String label;
  final String unit;
  final double? value;
  final LabSeverity? severity;
  const LabParamScore({
    required this.key,
    required this.label,
    required this.unit,
    required this.value,
    required this.severity,
  });
}

/// Resumen del dominio clínico para banderas/encabezados.
class ClinicalDomainSummary {
  final List<LabParamScore> params; // todos, medidos y no medidos
  final List<LabParamScore> measured; // solo los medidos
  const ClinicalDomainSummary(this.params, this.measured);

  /// Peor severidad entre los parámetros medidos (null si no hay ninguno).
  LabSeverity? get worst {
    LabSeverity? w;
    for (final p in measured) {
      final s = p.severity;
      if (s == null) continue;
      if (w == null || s.index > w.index) w = s;
    }
    return w;
  }

  /// Cuántos parámetros medidos están en severidad moderada/severa (≥2).
  int get highCount =>
      measured.where((p) => (p.severity?.index ?? 0) >= 2).length;

  bool get isEmpty => measured.isEmpty;
}

LabSeverity _sev(int i) => LabSeverity.values[i.clamp(0, 3)];

// ---- Rúbricas por parámetro (tabla de María). value != null garantizado. ----

// Albúmina (g/dL): 0:≥3.5, 1:3.0–3.49, 2:2.5–2.99, 3:<2.5
LabSeverity _albumin(double v) =>
    v >= 3.5 ? _sev(0) : (v >= 3.0 ? _sev(1) : (v >= 2.5 ? _sev(2) : _sev(3)));

// Prealbúmina (mg/dL): 0:≥18, 1:15–17.9, 2:10–14.9, 3:<10
LabSeverity _prealbumin(double v) =>
    v >= 18 ? _sev(0) : (v >= 15 ? _sev(1) : (v >= 10 ? _sev(2) : _sev(3)));

// Proteínas totales (g/dL): 0:≥6.6, 1:6.0–6.3, 2:5.5–5.9, 3:<5.0
// (huecos 6.3–6.6 y 5.0–5.5 → se rellenan monotónicamente hacia la banda mejor)
LabSeverity _totalProtein(double v) =>
    v >= 6.6 ? _sev(0) : (v >= 6.0 ? _sev(1) : (v >= 5.5 ? _sev(2) : _sev(3)));

// HbA1c (%): 0:<7.5, 1:7.5–8.4, 2:8.5–9.4, 3:≥9.5
LabSeverity _hba1c(double v) =>
    v < 7.5 ? _sev(0) : (v < 8.5 ? _sev(1) : (v < 9.5 ? _sev(2) : _sev(3)));

// Glucosa (mg/dL): 0:80–180, 1:181–220, 2:221–260, 3:>260
// (<80 no está en la tabla; se puntúa 0 — revisar hipoglucemia con María)
LabSeverity _glucose(double v) =>
    v <= 180 ? _sev(0) : (v <= 220 ? _sev(1) : (v <= 260 ? _sev(2) : _sev(3)));

// Hemoglobina (g/dL): 0:≥12, 1:10–11.9, 2:8–9.9, 3:<8
LabSeverity _hemoglobin(double v) =>
    v >= 12 ? _sev(0) : (v >= 10 ? _sev(1) : (v >= 8 ? _sev(2) : _sev(3)));

// PCR (mg/L): 0:<10, 1:10–39, 2:40–99, 3:≥100
LabSeverity _crp(double v) =>
    v < 10 ? _sev(0) : (v < 40 ? _sev(1) : (v < 100 ? _sev(2) : _sev(3)));

// TP (seg): 0:10–14, 1:14–18, 2:18, 3:>18 (fronteras ambiguas → monotónico)
LabSeverity _pt(double v) =>
    v <= 14 ? _sev(0) : (v < 18 ? _sev(1) : (v <= 18 ? _sev(2) : _sev(3)));

// Hematocrito (%): 0:35–50, 1:28–39, 2:39–45, 3:>50 (bilateral e inconsistente)
// Interpretación defendible: normal 35–50 → 0; leve bajo 28–35 → 1;
// severo bajo <28 → 2; alto >50 → 3. REVISAR con María.
LabSeverity _hematocrit(double v) {
  if (v > 50) return _sev(3);
  if (v >= 35) return _sev(0);
  if (v >= 28) return _sev(1);
  return _sev(2);
}

// Plaquetas (µL): 0:150k–400k, 1:100k–149k, 2:<100k, 3:<50k
// (>400k trombocitosis no penalizada en la tabla → 0; revisar con María)
LabSeverity _platelets(double v) => v >= 150000
    ? _sev(0)
    : (v >= 100000 ? _sev(1) : (v >= 50000 ? _sev(2) : _sev(3)));

// TPP (seg): 0:25–45, 1:36–50, 2:>50, 3:NA (sin banda 3 → máx 2)
LabSeverity _ptt(double v) =>
    v > 50 ? _sev(2) : (v > 45 ? _sev(1) : _sev(0));

// Wrappers PÚBLICOS por parámetro, para la vista previa de severidad en vivo
// del formulario (un solo lugar mantiene los umbrales).
LabSeverity sevAlbumin(double v) => _albumin(v);
LabSeverity sevPrealbumin(double v) => _prealbumin(v);
LabSeverity sevTotalProtein(double v) => _totalProtein(v);
LabSeverity sevHba1c(double v) => _hba1c(v);
LabSeverity sevGlucose(double v) => _glucose(v);
LabSeverity sevHemoglobin(double v) => _hemoglobin(v);
LabSeverity sevHematocrit(double v) => _hematocrit(v);
LabSeverity sevPlatelets(double v) => _platelets(v);
LabSeverity sevCrp(double v) => _crp(v);
LabSeverity sevPt(double v) => _pt(v);
LabSeverity sevPtt(double v) => _ptt(v);

/// Puntúa todo el dominio clínico a partir de un [PatientLab].
///
/// El parámetro glucémico usa HbA1c si está presente (paciente diabético), y
/// si no, la glucosa; si no hay ninguno queda sin puntaje (N/A).
ClinicalDomainSummary scoreClinicalDomain(PatientLab lab) {
  LabParamScore p(String key, String label, String unit, double? v,
          LabSeverity Function(double) fn) =>
      LabParamScore(
        key: key,
        label: label,
        unit: unit,
        value: v,
        severity: v == null ? null : fn(v),
      );

  // Glucémico combinado (HbA1c preferente).
  final glyc = lab.hba1cPct != null
      ? LabParamScore(
          key: 'glycemic',
          label: 'HbA1c',
          unit: '%',
          value: lab.hba1cPct,
          severity: _hba1c(lab.hba1cPct!),
        )
      : LabParamScore(
          key: 'glycemic',
          label: 'Glucosa',
          unit: 'mg/dL',
          value: lab.glucoseMgDl,
          severity:
              lab.glucoseMgDl == null ? null : _glucose(lab.glucoseMgDl!),
        );

  final params = <LabParamScore>[
    p('albumin', 'Albúmina', 'g/dL', lab.albuminGdl, _albumin),
    p('prealbumin', 'Prealbúmina', 'mg/dL', lab.prealbuminMgDl, _prealbumin),
    p('total_protein', 'Proteínas totales', 'g/dL', lab.totalProteinGdl,
        _totalProtein),
    glyc,
    p('hemoglobin', 'Hemoglobina', 'g/dL', lab.hemoglobinGdl, _hemoglobin),
    p('hematocrit', 'Hematocrito', '%', lab.hematocritPct, _hematocrit),
    p('platelets', 'Plaquetas', 'µL', lab.plateletsUl, _platelets),
    p('crp', 'PCR', 'mg/L', lab.crpMgL, _crp),
    p('pt', 'TP', 'seg', lab.ptSeconds, _pt),
    p('ptt', 'TPP', 'seg', lab.pttSeconds, _ptt),
  ];
  final measured = params.where((x) => x.value != null).toList();
  return ClinicalDomainSummary(params, measured);
}
