import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'kura_back_button.dart';
import '../design/tints.dart';
import '../design/tokens.dart';
import '../format/money.dart';
import '../../services/data_repository.dart';
import 'dashed_border_box.dart';

/// Pantalla completa de bloqueo del módulo Administración avanzada: la usan las
/// pantallas hijas gateadas cuando se abren SIN el módulo (segunda capa, además del
/// candado del botón: con URL propia el botón ya no es la única entrada).
Widget adminModuleLockedScaffold(
  BuildContext context, {
  required DataRepository repo,
  required String? organizationId,
  required String title,
  required String description,
}) =>
    Scaffold(
      // La rama bloqueada también es una hija profunda de /admin: lleva su regreso a
      // Configuración (§13.1), si no, un centro sin el módulo queda varado en el candado.
      appBar: AppBar(
        leading: const KuraBackButton(fallback: '/admin/configuracion'),
        title: Text(title),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: KuraModuleLock.section(
            repo: repo,
            organizationId: organizationId ?? '',
            moduleKey: 'admin',
            moduleName: 'Administración avanzada',
            description: description,
          ),
        ),
      ),
    );

/// Igual que [adminModuleLockedScaffold] pero SIN Scaffold/AppBar: para las pantallas
/// hijas de /admin que ahora se abren DENTRO del shell (riel visible). El título y la
/// navegación los pone el shell; aquí solo va el contenido del candado (que DICE EL
/// PRECIO). Sin volver propio: el riel es la salida.
Widget adminModuleLockedBody({
  required DataRepository repo,
  required String? organizationId,
  required String description,
}) =>
    Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: KuraModuleLock.section(
          repo: repo,
          organizationId: organizationId ?? '',
          moduleKey: 'admin',
          moduleName: 'Administración avanzada',
          description: description,
        ),
      ),
    );

enum _Density { band, action, section }

/// Bloqueo de módulo (canvas §2). Un solo componente, tres densidades — banda en
/// línea, acción bloqueada y sección completa. Las tres DICEN EL PRECIO (leído de
/// billing_catalog vía `repo.unitAmountCents`, nunca a mano) y LLEVAN A LICENCIAS
/// (`context.go('/admin')`). Ninguna dice "solicítalo a tu administrador": quien lee
/// es quien puede comprar. Si el módulo YA está contratado, no rinde nada. Color
/// desde [BrandTokens]: el candado y el CTA salen del acento de la marca del centro.
class KuraModuleLock extends StatelessWidget {
  final DataRepository repo;
  final String organizationId;
  final String moduleKey; // 'insumos' | 'comercial' | 'admin'
  final String moduleName; // "Insumos", "Administración avanzada"
  final String description; // qué incluye / qué se gana
  final String? actionLabel; // solo densidad "acción"
  final VoidCallback? onPressed; // solo densidad "acción": qué hace CON el módulo
  final IconData? icon; // solo densidad "acción": ícono del botón normal
  final _Density _density;

  /// Banda en línea — cuando el resto de la pantalla sí funciona.
  const KuraModuleLock.band({
    super.key,
    required this.repo,
    required this.organizationId,
    required this.moduleKey,
    required this.moduleName,
    required this.description,
  })  : actionLabel = null,
        onPressed = null,
        icon = null,
        _density = _Density.band;

  /// Acción bloqueada. A diferencia de band/section, NO se desvanece con el módulo:
  /// con el módulo rinde el botón NORMAL (dispara [onPressed]); sin él se ve apagado
  /// y al tocarlo abre la sección completa en un diálogo (nunca un snackbar).
  const KuraModuleLock.action({
    super.key,
    required this.repo,
    required this.organizationId,
    required this.moduleKey,
    required this.moduleName,
    required this.description,
    required this.actionLabel,
    required this.onPressed,
    this.icon,
  }) : _density = _Density.action;

  /// Sección completa — cuando el módulo ES la pantalla.
  const KuraModuleLock.section({
    super.key,
    required this.repo,
    required this.organizationId,
    required this.moduleKey,
    required this.moduleName,
    required this.description,
  })  : actionLabel = null,
        onPressed = null,
        icon = null,
        _density = _Density.section;

  int? get _priceCents =>
      repo.unitAmountCents('module', moduleKey, 'month');

  String get _priceText => moneyOrDash(_priceCents);

  void _goToLicenses(BuildContext context) => context.go('/admin');

  @override
  Widget build(BuildContext context) {
    final t = BrandTokens.of(context);
    final contracted = repo.hasModuleEntitlement(organizationId, moduleKey);
    // La acción NO se desvanece: con módulo es el botón normal, sin él el apagado.
    if (_density == _Density.action) return _action(context, t, contracted);
    // band/section sí se desvanecen cuando el módulo ya está contratado.
    if (contracted) return const SizedBox.shrink();
    return _density == _Density.band ? _band(context, t) : _section(context, t);
  }

  // a) Banda en línea.
  Widget _band(BuildContext context, BrandTokens t) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Tints.brand(t, 0.035),
        borderRadius: AppRadii.mdR,
        border: Border.all(color: t.border),
      ),
      child: Row(
        children: [
          Icon(Icons.lock_outline, size: 18, color: t.brandPrimary),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$moduleName · $_priceText/mes',
                  style: TextStyle(
                      fontSize: AppType.body - 1,
                      fontWeight: AppType.bold,
                      color: t.textPrimary),
                ),
                Text(
                  description,
                  style: TextStyle(
                      fontSize: AppType.caption, color: t.textSecondary),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          _cta(t, 'Ver Licencias', () => _goToLicenses(context)),
        ],
      ),
    );
  }

  // b) Acción bloqueada. Con módulo: botón NORMAL (tonal) que dispara onPressed.
  // Sin módulo: apagada antes de tocarla; al tocar abre (c) en diálogo.
  Widget _action(BuildContext context, BrandTokens t, bool contracted) {
    if (contracted) {
      return Material(
        color: t.chipBg,
        borderRadius: AppRadii.pillR,
        child: InkWell(
          borderRadius: AppRadii.pillR,
          onTap: onPressed,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 9),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 16, color: t.brandPrimary),
                  const SizedBox(width: 6),
                ],
                Text(
                  actionLabel ?? moduleName,
                  style: TextStyle(
                      fontSize: AppType.label,
                      fontWeight: AppType.bold,
                      color: t.brandPrimary),
                ),
              ],
            ),
          ),
        ),
      );
    }
    return InkWell(
      borderRadius: AppRadii.pillR,
      onTap: () => _openDialog(context),
      child: DashedBorderBox(
        color: t.border,
        radius: AppRadii.pill,
        fill: t.background,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 9),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.lock_outline, size: 13, color: t.textDisabled),
              const SizedBox(width: 6),
              Text(
                actionLabel ?? moduleName,
                style: TextStyle(fontSize: AppType.label, color: t.textDisabled),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _openDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (dialogCtx) {
        final t = BrandTokens.of(dialogCtx);
        // Sin fondo/forma locales: el dialogTheme del centro los provee (§13.2).
        return Dialog(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.sm),
            child: _section(dialogCtx, t),
          ),
        );
      },
    );
  }

  // c) Sección completa.
  Widget _section(BuildContext context, BrandTokens t) {
    return DashedBorderBox(
      color: t.border,
      radius: AppRadii.md,
      fill: t.background,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: t.chipBg,
                borderRadius: AppRadii.smR,
              ),
              child: Icon(Icons.lock_outline, size: 19, color: t.brandPrimary),
            ),
            const SizedBox(height: AppSpacing.sm + 2),
            Text(
              moduleName,
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: AppType.body, // 14
                  fontWeight: AppType.bold,
                  color: t.textPrimary),
            ),
            const SizedBox(height: AppSpacing.xs + 1),
            Text(
              description,
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: AppType.label,
                  height: 1.5,
                  color: t.textSecondary),
            ),
            const SizedBox(height: AppSpacing.sm + 2),
            _cta(
              t,
              _priceCents == null
                  ? 'Ver Licencias'
                  : 'Agregar por ${pesosFromCents(_priceCents!)} al mes',
              () => _goToLicenses(context),
            ),
          ],
        ),
      ),
    );
  }

  Widget _cta(BrandTokens t, String label, VoidCallback onTap) => Material(
        color: t.brandPrimary,
        borderRadius: AppRadii.pillR,
        child: InkWell(
          borderRadius: AppRadii.pillR,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(
              label,
              style: TextStyle(
                  fontSize: AppType.label,
                  fontWeight: AppType.bold,
                  color: t.onBrand),
            ),
          ),
        ),
      );
}
