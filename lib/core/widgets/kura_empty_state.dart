import 'package:flutter/material.dart';

import '../design/tokens.dart';

/// Estado vacío (canvas §3). Ícono, título que nombra la situación, una o dos
/// frases, y SIEMPRE los botones que resuelven el vacío: la acción no es opcional
/// (un vacío sin salida es una pantalla sin pensar). El vacío es el mejor momento
/// para enseñar el producto. Todo color sale de [BrandTokens].
class KuraEmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final String primaryLabel;
  final VoidCallback onPrimary;
  final String? secondaryLabel;
  final VoidCallback? onSecondary;

  const KuraEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    required this.primaryLabel,
    required this.onPrimary,
    this.secondaryLabel,
    this.onSecondary,
  });

  @override
  Widget build(BuildContext context) {
    final t = BrandTokens.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: t.chipBg,
                borderRadius: AppRadii.mdR,
              ),
              child: Icon(icon, size: 26, color: t.brandPrimary),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 17,
                  fontWeight: AppType.bold,
                  color: t.textPrimary),
            ),
            const SizedBox(height: AppSpacing.sm),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 380),
              child: Text(
                message,
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: AppType.body - 1, // 13
                    height: 1.55,
                    color: t.textSecondary),
              ),
            ),
            const SizedBox(height: AppSpacing.lg + 2),
            Wrap(
              spacing: AppSpacing.sm + 2,
              runSpacing: AppSpacing.sm,
              alignment: WrapAlignment.center,
              children: [
                _PillButton(
                  label: primaryLabel,
                  onPressed: onPrimary,
                  background: t.brandPrimary,
                  foreground: t.onBrand,
                ),
                if (secondaryLabel != null && onSecondary != null)
                  _PillButton(
                    label: secondaryLabel!,
                    onPressed: onSecondary!,
                    background: t.chipBg,
                    foreground: t.brandPrimary,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Botón pastilla del sistema (13px w700, radius pill, padding 10×18). Compartido
/// por los estados; su color lo decide quien lo usa (siempre desde tokens).
class _PillButton extends StatelessWidget {
  final String label;
  final VoidCallback onPressed;
  final Color background;
  final Color foreground;

  const _PillButton({
    required this.label,
    required this.onPressed,
    required this.background,
    required this.foreground,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: background,
      borderRadius: AppRadii.pillR,
      child: InkWell(
        borderRadius: AppRadii.pillR,
        onTap: onPressed,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
          child: Text(
            label,
            style: TextStyle(
                fontSize: AppType.body - 1, // 13
                fontWeight: AppType.bold,
                color: foreground),
          ),
        ),
      ),
    );
  }
}
