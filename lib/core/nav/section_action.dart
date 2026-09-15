import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../design/tokens.dart';

/// La acción PRINCIPAL de una sección, para pintarla en el ENCABEZADO a ≥900 px (donde
/// no hay flotantes) en vez de un FAB. La sección la publica; el shell (que es su
/// ANCESTRO y dueño del KuraContentHeader) la lee. Se identifica por [sectionKey] —el
/// último segmento de la ruta: 'usuarios', 'sitios'…— para no filtrarse a otra sección
/// (funciona igual bajo /admin/<x> y /platform/<x>).
class SectionAction {
  final String sectionKey;
  final String label;
  final IconData icon;
  final VoidCallback? onPressed; // null = deshabilitado (p.ej. sin centro resuelto)
  final bool locked; // Sitios sin módulo: candado sólido que abre la venta (7.1)
  const SectionAction({
    required this.sectionKey,
    required this.label,
    required this.icon,
    this.onPressed,
    this.locked = false,
  });

  // == por FORMA (no por identidad del closure): así republicar en cada build no hace
  // churn si nada cambió. La habilidad se compara por (onPressed == null).
  @override
  bool operator ==(Object o) =>
      o is SectionAction &&
      o.sectionKey == sectionKey &&
      o.label == label &&
      o.icon == icon &&
      o.locked == locked &&
      (o.onPressed == null) == (onPressed == null);

  @override
  int get hashCode => Object.hash(sectionKey, label, icon, locked, onPressed == null);
}

/// La acción de la sección activa (o null). La sección la fija; el shell la observa.
final sectionActionProvider = StateProvider<SectionAction?>((ref) => null);

/// La sección publica su acción (o null a <900 px). Fuera de la fase de build (post
/// frame) y solo si cambió, para no escribir el provider durante el build ni hacer bucle.
void publishSectionAction(WidgetRef ref, SectionAction? action) {
  WidgetsBinding.instance.addPostFrameCallback((_) {
    final n = ref.read(sectionActionProvider.notifier);
    if (n.state != action) n.state = action;
  });
}

/// Lo que el shell mete en `KuraContentHeader.actions`: el botón de la sección activa,
/// SOLO a ≥900 px y solo si la acción publicada es de ESTA sección (su sectionKey == el
/// último segmento de la ruta). A <900 no hay botón en el encabezado (queda el FAB).
List<Widget> sectionHeaderActions(
    BuildContext context, WidgetRef ref, String currentRoute) {
  final wide = MediaQuery.of(context).size.width >= 900;
  final action = ref.watch(sectionActionProvider);
  if (!wide || action == null) return const [];
  final segs = currentRoute.split('/').where((s) => s.isNotEmpty).toList();
  final key = segs.isEmpty ? null : segs.last;
  if (action.sectionKey != key) return const [];
  return [SectionActionButton(action)];
}

/// El botón de la acción en el encabezado: SÓLIDO, con el brandPrimary del centro y su
/// rótulo COMPLETO (§5) — el elemento más llamativo del encabezado, no un icono más ni
/// un enlace. Con candado si [SectionAction.locked] (mismo camino de venta que el FAB).
class SectionActionButton extends StatelessWidget {
  final SectionAction action;
  const SectionActionButton(this.action, {super.key});

  @override
  Widget build(BuildContext context) {
    final t = BrandTokens.of(context);
    return FilledButton.icon(
      onPressed: action.onPressed,
      icon: Icon(action.locked ? Icons.lock_outline : action.icon, size: 18),
      label: Text(action.label),
      style: FilledButton.styleFrom(
        backgroundColor: t.brandPrimary,
        foregroundColor: t.onBrand,
      ),
    );
  }
}
