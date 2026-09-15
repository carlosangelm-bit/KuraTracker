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

/// ¿Hay un riel de navegación en pantalla AHORA MISMO (con su pie de cuenta + Ayuda)? Lo
/// publica el shell que pinta el riel; TourScope (su ANCESTRO) lo observa para NO duplicar
/// el lanzador flotante de «Ayuda» cuando el riel ya la ofrece en el pie (§3). Sin riel
/// (teléfono, y el cuidador en cualquier anchura) queda en false y el flotante se mantiene.
/// El shell descendiente publica DESPUÉS del ancestro (su build corre después), así que en
/// /admin y /platform —donde AppShell no pinta riel pero su shell anidado sí— gana el true.
final railPresentProvider = StateProvider<bool>((ref) => false);

/// El shell publica si su riel está en pantalla. Misma disciplina que [publishSectionAction]:
/// post-frame, solo si cambió, y SOLO si sigue montado (al salir de /admin el shell anidado
/// se destruye en el mismo cuadro; la guardia evita el `ref` desechado).
void publishRailPresent(
  WidgetRef ref,
  bool present, {
  required bool Function() mounted,
}) {
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (!mounted()) return;
    final n = ref.read(railPresentProvider.notifier);
    if (n.state != present) n.state = present;
  });
}

/// La sección publica su acción (o null cuando no hay riel). Fuera de la fase de build
/// (post-frame), solo si cambió (no bucle), y SOLO si el widget sigue montado: si la
/// pantalla se destruye en el mismo cuadro (un redirect del router como
/// /admin → /admin/usuarios), la devolución correría sobre un `ref` desechado y Flutter
/// lanzaría «Cannot use ref after the widget was disposed» — pantalla roja. [mounted]
/// es el getter del State (`() => mounted`).
void publishSectionAction(
  WidgetRef ref,
  SectionAction? action, {
  required bool Function() mounted,
}) {
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (!mounted()) return;
    final n = ref.read(sectionActionProvider.notifier);
    if (n.state != action) n.state = action;
  });
}

/// Lo que el shell mete en `KuraContentHeader.actions`: el botón de la sección activa,
/// SOLO cuando hay riel ([hasRail], la MISMA condición que gobierna el menú de cuenta) y
/// solo si la acción publicada es de ESTA sección (su sectionKey == el último segmento
/// de la ruta). Sin riel no hay botón en el encabezado (queda el FAB).
List<Widget> sectionHeaderActions(WidgetRef ref, String currentRoute,
    {required bool hasRail}) {
  final action = ref.watch(sectionActionProvider);
  if (!hasRail || action == null) return const [];
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
