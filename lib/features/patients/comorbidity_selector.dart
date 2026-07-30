import 'package:flutter/material.dart';

import '../../core/theme/kura_theme.dart';
import '../../engine/models/kura_engine_enums.dart';

String comorbilidadEstadoLabel(ComorbilidadEstado e) {
  switch (e) {
    case ComorbilidadEstado.presente:
      return 'Presente';
    case ComorbilidadEstado.negado:
      return 'Negado';
    case ComorbilidadEstado.noEvaluado:
      return 'No evaluado';
  }
}

/// Selector reutilizable de comorbilidades (APP): por cada comorbilidad del
/// catálogo, un selector de estado (Presente / Negado / No evaluado). Solo las
/// marcadas como `presente` cuentan para el motor (n_comorb_struct). Se usa en
/// el alta del paciente y en la pantalla de gestión de comorbilidades.
class ComorbidityStatusSelector extends StatelessWidget {
  /// Estado actual por comorbilidad (las ausentes = no evaluado).
  final Map<Comorbilidad, ComorbilidadEstado> values;
  final void Function(Comorbilidad code, ComorbilidadEstado status) onChanged;

  const ComorbidityStatusSelector({
    super.key,
    required this.values,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      // Tabaquismo se captura como APNP (Tabaquismo) en el expediente, no como
      // comorbilidad, para no duplicarlo. Se excluye del catálogo aquí.
      children: Comorbilidad.values
          .where((c) => c != Comorbilidad.tabaquismoActivo)
          .map((code) {
        final current = values[code] ?? ComorbilidadEstado.noEvaluado;
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(code.label,
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                children: ComorbilidadEstado.values.map((estado) {
                  final selected = current == estado;
                  final color = estado == ComorbilidadEstado.presente
                      ? KuraColors.danger
                      : estado == ComorbilidadEstado.negado
                          ? KuraColors.success
                          : KuraColors.darkText;
                  return ChoiceChip(
                    label: Text(comorbilidadEstadoLabel(estado)),
                    selected: selected,
                    selectedColor: color.withOpacity(0.16),
                    labelStyle: TextStyle(
                      color: selected ? color : null,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.normal,
                      fontSize: 12,
                    ),
                    onSelected: (_) => onChanged(code, estado),
                  );
                }).toList(),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}
