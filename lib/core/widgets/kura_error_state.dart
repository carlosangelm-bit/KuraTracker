import 'package:flutter/material.dart';

import '../design/tints.dart';
import '../design/tokens.dart';

/// Error (canvas §4). Mensaje humano de QUÉ pasó, una frase de QUÉ está a salvo,
/// Reintentar, y el detalle técnico PLEGADO y cerrado por defecto. La excepción
/// cruda nunca es el mensaje: va adentro, para soporte. Todo color sale de
/// [BrandTokens]; el cuadro del ícono usa un tinte de `statusDanger`.
class KuraErrorState extends StatefulWidget {
  final String title;
  final String reassurance;
  final String detail; // e.toString() del error — oculto hasta desplegar
  final VoidCallback onRetry;
  final String retryLabel;

  const KuraErrorState({
    super.key,
    required this.title,
    required this.reassurance,
    required this.detail,
    required this.onRetry,
    this.retryLabel = 'Reintentar',
  });

  @override
  State<KuraErrorState> createState() => _KuraErrorStateState();
}

class _KuraErrorStateState extends State<KuraErrorState> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final t = BrandTokens.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 28),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: AppRadii.mdR,
        border: Border.all(color: t.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: Tints.status(t.statusDanger, t.surface, 0.12),
                  borderRadius: AppRadii.smR,
                ),
                child: Icon(Icons.error_outline,
                    size: 19, color: t.statusDanger),
              ),
              const SizedBox(width: AppSpacing.md + 2),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.title,
                      style: TextStyle(
                          fontSize: 15,
                          fontWeight: AppType.bold,
                          color: t.textPrimary),
                    ),
                    const SizedBox(height: AppSpacing.xs + 1),
                    Text(
                      widget.reassurance,
                      style: TextStyle(
                          fontSize: AppType.body - 1, // 13
                          height: 1.55,
                          color: t.textSecondary),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          Row(
            children: [
              _RetryButton(label: widget.retryLabel, onPressed: widget.onRetry),
              const SizedBox(width: AppSpacing.sm + 2),
              TextButton(
                onPressed: () => setState(() => _open = !_open),
                style: TextButton.styleFrom(
                  foregroundColor: t.textSecondary,
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text(
                  _open ? 'Ocultar detalle técnico' : 'Ver detalle técnico',
                  style: const TextStyle(
                      fontSize: AppType.label, fontWeight: AppType.semibold),
                ),
              ),
            ],
          ),
          // El texto de la excepción NO existe en el árbol hasta desplegar.
          if (_open) ...[
            const SizedBox(height: AppSpacing.md),
            Container(
              width: double.infinity,
              padding:
                  const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
              decoration: BoxDecoration(
                color: t.background,
                borderRadius: AppRadii.smR,
                border: Border.all(color: t.border),
              ),
              child: Text(
                widget.detail,
                style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: AppType.caption,
                    color: t.textSecondary),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _RetryButton extends StatelessWidget {
  final String label;
  final VoidCallback onPressed;
  const _RetryButton({required this.label, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    final t = BrandTokens.of(context);
    return Material(
      color: t.brandPrimary,
      borderRadius: AppRadii.pillR,
      child: InkWell(
        borderRadius: AppRadii.pillR,
        onTap: onPressed,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
          child: Text(
            label,
            style: TextStyle(
                fontSize: AppType.body - 1,
                fontWeight: AppType.bold,
                color: t.onBrand),
          ),
        ),
      ),
    );
  }
}
