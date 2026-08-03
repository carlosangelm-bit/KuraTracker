import 'package:flutter/material.dart';
import '../../../core/theme/kura_theme.dart';

/// Sliders para composicion del lecho (granulacion/esfacelo/necrosis/
/// epitelizacion) con validacion de suma = 100% y barra de total en vivo
/// (seccion 6.1). El aviso de "capturar ANTES de curar/desbridar" se
/// muestra siempre visible arriba de los sliders.
class BedCompositionSliders extends StatelessWidget {
  final double granulacion;
  final double esfacelo;
  final double necrosis;
  final double epitelizacion;
  final ValueChanged<double> onGranulacionChanged;
  final ValueChanged<double> onEsfaceloChanged;
  final ValueChanged<double> onNecrosisChanged;
  final ValueChanged<double> onEpitelizacionChanged;
  final bool capturedBeforeDebridement;
  final ValueChanged<bool> onCapturedBeforeDebridementChanged;

  const BedCompositionSliders({
    super.key,
    required this.granulacion,
    required this.esfacelo,
    required this.necrosis,
    required this.epitelizacion,
    required this.onGranulacionChanged,
    required this.onEsfaceloChanged,
    required this.onNecrosisChanged,
    required this.onEpitelizacionChanged,
    required this.capturedBeforeDebridement,
    required this.onCapturedBeforeDebridementChanged,
  });

  double get total => granulacion + esfacelo + necrosis + epitelizacion;

  @override
  Widget build(BuildContext context) {
    final isOver = total > 100.01;
    final isUnder = total < 99.99;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0x1AE8A93A),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: KuraColors.warning.withOpacity(0.4)),
          ),
          child: Row(
            children: [
              const Icon(Icons.info_outline, color: KuraColors.warning, size: 20),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'Regla de captura clínica: registra la composición del lecho '
                  'ANTES de curar o desbridar la herida.',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          value: capturedBeforeDebridement,
          activeColor: KuraColors.primary,
          title: const Text(
            'Confirmo que esta composición se capturó antes de curar/desbridar',
            style: TextStyle(fontSize: 13),
          ),
          onChanged: (v) => onCapturedBeforeDebridementChanged(v ?? true),
        ),
        const SizedBox(height: 8),
        _BedSlider(
          label: 'Granulación',
          value: granulacion,
          color: KuraTissueColors.granulacion,
          onChanged: onGranulacionChanged,
        ),
        _BedSlider(
          label: 'Esfacelo',
          value: esfacelo,
          color: KuraTissueColors.esfacelo,
          onChanged: onEsfaceloChanged,
        ),
        _BedSlider(
          label: 'Necrosis',
          value: necrosis,
          color: KuraTissueColors.necrosis,
          onChanged: onNecrosisChanged,
        ),
        _BedSlider(
          label: 'Epitelización',
          value: epitelizacion,
          color: KuraTissueColors.epitelizacion,
          onChanged: onEpitelizacionChanged,
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  value: (total / 100).clamp(0, 1),
                  minHeight: 10,
                  backgroundColor: KuraColors.chipBg,
                  color: isOver ? KuraColors.danger : KuraColors.primary,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Text(
              '${total.toStringAsFixed(0)}%',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                color: isOver ? KuraColors.danger : KuraColors.darkText,
              ),
            ),
          ],
        ),
        if (isOver)
          const Padding(
            padding: EdgeInsets.only(top: 6),
            child: Text(
              'La suma no puede superar 100%. Ajusta los valores.',
              style: TextStyle(color: KuraColors.danger, fontSize: 12),
            ),
          )
        else if (isUnder)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              'Falta ${(100 - total).toStringAsFixed(0)}% para completar el 100%.',
              style: TextStyle(color: KuraColors.darkText.withOpacity(0.5), fontSize: 12),
            ),
          ),
      ],
    );
  }
}

class _BedSlider extends StatelessWidget {
  final String label;
  final double value;
  final Color color;
  final ValueChanged<double> onChanged;

  const _BedSlider({
    required this.label,
    required this.value,
    required this.color,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 110,
            child: Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          ),
          Expanded(
            child: Slider(
              value: value.clamp(0, 100),
              min: 0,
              max: 100,
              divisions: 100,
              activeColor: color,
              label: '${value.round()}%',
              onChanged: onChanged,
            ),
          ),
          SizedBox(
            width: 44,
            child: Text('${value.round()}%',
                textAlign: TextAlign.right,
                style: const TextStyle(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }
}
