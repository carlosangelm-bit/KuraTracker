import 'package:flutter/material.dart';

import '../../core/theme/kura_theme.dart';
import '../../engine/models/kura_engine_enums.dart';
import '../../models/wound.dart';

/// Bottom sheet para elegir a que herida ACTIVA se dirige el "Seguimiento"
/// cuando el paciente tiene mas de una (punto 3 del rediseno). Si solo hay
/// una herida activa, el llamador debe navegar directo sin abrir este
/// selector -- ver `_goToFollowUp` en PatientsListScreen/PatientCard.
///
/// Devuelve la [Wound] elegida, o null si el usuario cancelo (cerro el
/// sheet sin seleccionar).
Future<Wound?> showWoundPickerSheet(BuildContext context, List<Wound> activeWounds) {
  return showModalBottomSheet<Wound>(
    context: context,
    showDragHandle: true,
    builder: (context) {
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 4, 20, 8),
              child: Text(
                '¿Seguimiento de qué herida?',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
              ),
            ),
            for (final wound in activeWounds)
              ListTile(
                leading: const Icon(Icons.healing_outlined, color: KuraColors.primary),
                title: Text(wound.etiology.label),
                subtitle: Text(wound.bodyLocationPrimary.replaceAll('_', ' ')),
                onTap: () => Navigator.of(context).pop(wound),
              ),
            const SizedBox(height: 8),
          ],
        ),
      );
    },
  );
}
