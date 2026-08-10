import 'package:flutter/material.dart';

import '../../core/theme/kura_theme.dart';
import '../../engine/kura_clinical_adjustments.dart';

/// KT-16 — Fuente ÚNICA de recomendaciones (referencia, solo lectura). Reúne en
/// un lugar los algoritmos, versiones y rangos que alimentan las sugerencias de
/// Kura+, para que el equipo clínico los consulte y verifique.
class RecommendationsReferenceScreen extends StatelessWidget {
  const RecommendationsReferenceScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Fuente de recomendaciones')),
      body: FutureBuilder<KuraClinicalAdjustments>(
        future: KuraClinicalAdjustments.loadFromAssets(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final adj = snap.data;
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
            children: [
              _intro(),
              const SizedBox(height: 16),
              _flowCard(),
              const SizedBox(height: 16),
              if (adj != null) ...[
                _abiCard(adj),
                const SizedBox(height: 16),
                _albCard(adj),
                const SizedBox(height: 16),
              ],
              _labDomainCard(),
              const SizedBox(height: 16),
              _productRulesCard(),
              const SizedBox(height: 16),
              _disclaimer(adj),
            ],
          );
        },
      ),
    );
  }

  Widget _card(String title, List<Widget> children, {String? subtitle}) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: const TextStyle(
                      fontWeight: FontWeight.w800, fontSize: 15)),
              if (subtitle != null) ...[
                const SizedBox(height: 2),
                Text(subtitle,
                    style: TextStyle(
                        fontSize: 12,
                        color: KuraColors.darkText.withValues(alpha: 0.6))),
              ],
              const SizedBox(height: 10),
              ...children,
            ],
          ),
        ),
      );

  Widget _intro() => Text(
        'Aquí vive la fuente única de las sugerencias de Kura+: de dónde salen, '
        'con qué versión y con qué rangos. Es de referencia (solo lectura); la '
        'configuración de productos por centro se hace en "Productos del protocolo".',
        style: TextStyle(
            fontSize: 12, color: KuraColors.darkText.withValues(alpha: 0.7)),
      );

  Widget _flowCard() => _card('Cómo se genera una recomendación', [
        _step('1', 'Valoración', 'Se capturan herida (etiología, medidas, lecho, '
            'exudado, infección) y factores del paciente (ABI/ITB, albúmina).'),
        _step('2', 'Motor pronóstico',
            'Calcula la probabilidad de los escenarios A/B/C y aplica ajustes '
            'clínicos por ABI y albúmina (log-odds).'),
        _step('3', 'Reglas de tratamiento',
            'Según escenario + etiología, genera el régimen (método → producto '
            'genérico) e interconsultas/alertas.'),
        _step('4', 'Producto concreto',
            'Cada paso se resuelve al producto del inventario del centro según '
            'las reglas por categoría y medida (área/volumen, exudado, zona, '
            'infección).'),
      ]);

  Widget _step(String n, String title, String desc) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
                radius: 11,
                backgroundColor: KuraColors.primary,
                child: Text(n,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w700))),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                  Text(desc, style: const TextStyle(fontSize: 12)),
                ],
              ),
            ),
          ],
        ),
      );

  Widget _abiCard(KuraClinicalAdjustments adj) => _card(
        'Perfusión (ABI / ITB)',
        subtitle:
            'Cortes: alto ≥ ${adj.itbHighMin}, moderado ≥ ${adj.itbModMin}, bajo < ${adj.itbModMin}. '
            'ITB > 1.4 (incompresible) = no interpretable.',
        [_weightTable(adj.itb)],
      );

  Widget _albCard(KuraClinicalAdjustments adj) => _card(
        'Nutrición (albúmina)',
        subtitle:
            'Cortes (g/dL): normal ≥ ${adj.albNormalMin}, leve ≥ ${adj.albMildMin}, bajo < ${adj.albMildMin}.',
        [_weightTable(adj.alb)],
      );

  Widget _weightTable(Map<String, Map<String, double>> m) {
    Widget row(String label, Map<String, double>? w) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(children: [
            Expanded(flex: 3, child: Text(label, style: const TextStyle(fontSize: 13))),
            _wc(w?['A']),
            _wc(w?['B']),
            _wc(w?['C']),
          ]),
        );
    return Column(children: [
      Row(children: const [
        Expanded(flex: 3, child: Text('Categoría', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700))),
        Expanded(child: Text('A', textAlign: TextAlign.right, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700))),
        Expanded(child: Text('B', textAlign: TextAlign.right, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700))),
        Expanded(child: Text('C', textAlign: TextAlign.right, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700))),
      ]),
      const Divider(),
      for (final e in m.entries) row(e.key, e.value),
      const SizedBox(height: 6),
      Text('Peso en log-odds que se suma al score de cada escenario (A/B/C) '
          'antes del softmax.',
          style: TextStyle(fontSize: 11, color: KuraColors.darkText.withValues(alpha: 0.5))),
    ]);
  }

  Widget _wc(double? v) => Expanded(
        child: Text(v == null ? '—' : v.toStringAsFixed(1),
            textAlign: TextAlign.right, style: const TextStyle(fontSize: 13)),
      );

  Widget _labDomainCard() => _card(
        'Dominio clínico de laboratorios (0–3)',
        subtitle: 'Cada parámetro se puntúa 0 (normal) a 3 (severo). Borrador '
            'clínico en validación (María).',
        [
          _labRow('Albúmina (g/dL)', '≥3.5 · 3.0–3.49 · 2.5–2.99 · <2.5'),
          _labRow('Prealbúmina (mg/dL)', '≥18 · 15–17.9 · 10–14.9 · <10'),
          _labRow('Proteínas totales (g/dL)', '≥6.6 · 6.0–6.5 · 5.5–5.9 · <5.5'),
          _labRow('HbA1c (%)', '<7.5 · 7.5–8.4 · 8.5–9.4 · ≥9.5'),
          _labRow('Glucosa (mg/dL)', '≤180 · 181–220 · 221–260 · >260'),
          _labRow('Hemoglobina (g/dL)', '≥12 · 10–11.9 · 8–9.9 · <8'),
          _labRow('Hematocrito (%)', '35–50 · 28–34 · <28 · >50'),
          _labRow('Plaquetas (µL)', '≥150k · 100–149k · 50–99k · <50k'),
          _labRow('PCR (mg/L)', '<10 · 10–39 · 40–99 · ≥100'),
          _labRow('TP (seg)', '≤14 · 14–18 · =18 · >18'),
          _labRow('TPP (seg)', '≤45 · 45–50 · >50'),
        ],
      );

  Widget _labRow(String name, String ranges) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(name, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            Text('0 · 1 · 2 · 3   →   $ranges',
                style: TextStyle(fontSize: 11, color: KuraColors.darkText.withValues(alpha: 0.6))),
          ],
        ),
      );

  Widget _productRulesCard() => _card('Producto por categoría y medida', [
        Text(
          'El vínculo protocolo → producto se configura por centro en "Productos '
          'del protocolo": por cada categoría (limpieza, desbridamiento, apósito, '
          'relleno, protección, antimicrobiano, compresión, descarga) se define el '
          'producto y la cantidad, con condiciones opcionales por exudado, zona '
          'anatómica, tamaño (área/volumen) e infección. La consulta elige la '
          'regla más específica que aplique a la herida.',
          style: const TextStyle(fontSize: 12),
        ),
      ]);

  Widget _disclaimer(KuraClinicalAdjustments? adj) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: KuraColors.warning.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Versiones y validación',
                style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                    color: KuraColors.darkText.withValues(alpha: 0.8))),
            const SizedBox(height: 4),
            Text(
              'Ajustes: ${adj?.adjustmentsVersion ?? '—'}. Los pesos y umbrales '
              'provienen de guía clínica, NO están calibrados con datos y deben '
              'revalidarse prospectivamente. Herramienta de apoyo a la decisión; '
              'no sustituye el juicio profesional.',
              style: TextStyle(
                  fontSize: 11, color: KuraColors.darkText.withValues(alpha: 0.7)),
            ),
          ],
        ),
      );
}
