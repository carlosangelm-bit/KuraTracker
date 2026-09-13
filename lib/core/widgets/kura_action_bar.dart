import 'package:flutter/material.dart';

import '../design/tokens.dart';

/// Una acción pesada del menú "Más acciones" (con su nombre COMPLETO).
class KuraMenuAction {
  final String label;
  final IconData? icon;
  final VoidCallback onSelected;
  const KuraMenuAction({required this.label, required this.onSelected, this.icon});
}

/// Una pastilla de filtro con su conteo ("Bajo umbral · 7").
class KuraFilter {
  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;
  const KuraFilter({
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
  });
}

/// Barra de acciones (canvas §5): buscador que ocupa el espacio libre, UNA sola
/// acción primaria, "Más acciones" con nombres completos, y una fila de filtros con
/// conteo por pastilla más el "Mostrando N de M". Reemplaza los once botones en fila
/// de Configuración y los IconButton sin etiqueta de Inventario. Color desde tokens.
class KuraActionBar extends StatelessWidget {
  final String searchHint;
  final ValueChanged<String>? onSearchChanged;
  final TextEditingController? searchController;

  final String? primaryLabel;
  final IconData? primaryIcon;
  final VoidCallback? onPrimary;

  final List<KuraMenuAction> moreActions;
  final List<KuraFilter> filters;
  final String? showingText;

  const KuraActionBar({
    super.key,
    required this.searchHint,
    this.onSearchChanged,
    this.searchController,
    this.primaryLabel,
    this.primaryIcon,
    this.onPrimary,
    this.moreActions = const [],
    this.filters = const [],
    this.showingText,
  });

  @override
  Widget build(BuildContext context) {
    final t = BrandTokens.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: _search(t)),
            if (primaryLabel != null && onPrimary != null) ...[
              const SizedBox(width: AppSpacing.md),
              _primary(t),
            ],
            if (moreActions.isNotEmpty) ...[
              const SizedBox(width: AppSpacing.md),
              _moreMenu(t),
            ],
          ],
        ),
        if (filters.isNotEmpty || showingText != null) ...[
          const SizedBox(height: AppSpacing.md),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Wrap(
                  spacing: 9,
                  runSpacing: 9,
                  children: [for (final f in filters) _filterChip(t, f)],
                ),
              ),
              if (showingText != null) ...[
                const SizedBox(width: AppSpacing.md),
                Text(
                  showingText!,
                  style: TextStyle(
                      fontSize: AppType.label, color: t.textDisabled),
                ),
              ],
            ],
          ),
        ],
      ],
    );
  }

  Widget _search(BrandTokens t) {
    return Container(
      decoration: BoxDecoration(
        color: t.background,
        borderRadius: AppRadii.pillR,
        border: Border.all(color: t.border),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 17, vertical: 2),
      child: Row(
        children: [
          Icon(Icons.search, size: 16, color: t.textDisabled),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: TextField(
              controller: searchController,
              onChanged: onSearchChanged,
              style: TextStyle(fontSize: AppType.body - 1, color: t.textPrimary),
              cursorColor: t.brandPrimary,
              decoration: InputDecoration(
                isDense: true,
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
                hintText: searchHint,
                hintStyle: TextStyle(
                    fontSize: AppType.body - 1, color: t.textDisabled),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _primary(BrandTokens t) => Material(
        color: t.brandPrimary,
        borderRadius: AppRadii.pillR,
        child: InkWell(
          borderRadius: AppRadii.pillR,
          onTap: onPrimary,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (primaryIcon != null) ...[
                  Icon(primaryIcon, size: 16, color: t.onBrand),
                  const SizedBox(width: 6),
                ],
                Text(
                  primaryLabel!,
                  style: TextStyle(
                      fontSize: AppType.body - 1,
                      fontWeight: AppType.bold,
                      color: t.onBrand),
                ),
              ],
            ),
          ),
        ),
      );

  Widget _moreMenu(BrandTokens t) => PopupMenuButton<int>(
        tooltip: 'Más acciones',
        onSelected: (i) => moreActions[i].onSelected(),
        itemBuilder: (_) => [
          for (var i = 0; i < moreActions.length; i++)
            PopupMenuItem<int>(
              value: i,
              child: Row(
                children: [
                  if (moreActions[i].icon != null) ...[
                    Icon(moreActions[i].icon, size: 18, color: t.textSecondary),
                    const SizedBox(width: AppSpacing.sm),
                  ],
                  // Flexible: los nombres COMPLETOS envuelven en vez de desbordar.
                  Flexible(child: Text(moreActions[i].label)),
                ],
              ),
            ),
        ],
        child: Container(
          decoration: BoxDecoration(
            color: t.chipBg,
            borderRadius: AppRadii.pillR,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Más acciones',
                style: TextStyle(
                    fontSize: AppType.body - 1,
                    fontWeight: AppType.bold,
                    color: t.brandPrimary),
              ),
              const SizedBox(width: 4),
              Icon(Icons.keyboard_arrow_down, size: 13, color: t.brandPrimary),
            ],
          ),
        ),
      );

  Widget _filterChip(BrandTokens t, KuraFilter f) {
    final bg = f.selected ? t.brandPrimary : t.chipBg;
    final fg = f.selected ? t.onBrand : t.textPrimary;
    return Material(
      color: bg,
      borderRadius: AppRadii.pillR,
      child: InkWell(
        borderRadius: AppRadii.pillR,
        onTap: f.onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          child: Text(
            '${f.label} · ${f.count}',
            style: TextStyle(
                fontSize: AppType.label, fontWeight: AppType.bold, color: fg),
          ),
        ),
      ),
    );
  }
}
