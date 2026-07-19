import 'package:flutter/material.dart';

/// Sistema de diseño de KuraTracker basado en TOKENS SEMÁNTICOS.
///
/// Regla de oro (ver lib/core/design/README.md):
/// - El acento de marca ([BrandTokens.brandPrimary]) se reserva a acciones
///   primarias (FAB, botón principal, item de navegación activo). NO se usa
///   para superficies grandes ni como decoración.
/// - Los colores de ESTADO ([statusDanger]/[statusWarning]/[statusSuccess]/
///   [statusNeutral]) son CLÍNICOS (semáforo de trayectoria). Son los únicos
///   rojo/amarillo/verde de la app y su significado es clínico, no decorativo.
///
/// Los componentes consumen los tokens vía `BrandTokens.of(context)`, de modo
/// que agregar otra marca a futuro (p.ej. FWD/plataforma) sea cambiar los
/// valores del token, no reescribir componentes.

/// Paleta CRUDA de la marca Kura (constantes de compilación). No usar directo
/// en pantallas: consumir vía [BrandTokens]. Vive aparte para que
/// `KuraColors` (compatibilidad hacia atrás) pueda seguir siendo `const`.
class KuraPalette {
  KuraPalette._();

  static const Color brandPrimary = Color(0xFF7C3AED); // violeta Kura
  static const Color background = Color(0xFFF6F5FB); // neutro frío casi blanco
  static const Color surface = Color(0xFFFFFFFF);
  static const Color textPrimary = Color(0xFF201A2E); // slate oscuro (frío)
  static const Color border = Color(0xFFE7E4F0);
  static const Color chipBg = Color(0xFFEFEDF7);
  static const Color info = Color(0xFF3B82F6); // azul informativo (neutro)

  // Hero (banner oscuro): degradado índigo → violeta y texto sobre él.
  static const Color heroTop = Color(0xFF241B4E);
  static const Color heroBottom = Color(0xFF5B3AC7);
  static const Color onBrand = Color(0xFFFFFFFF);

  // Estado CLÍNICO (semáforo de Sheehan). Separado de la marca.
  static const Color statusSuccess = Color(0xFF1B8A5A); // avanza
  static const Color statusWarning = Color(0xFFE8A93A); // con reservas
  static const Color statusDanger = Color(0xFFC0392B); // no avanza
}

/// Tokens semánticos por MARCA. Implementado como [ThemeExtension] para que
/// cualquier componente los lea con `BrandTokens.of(context)` y una segunda
/// marca sea solo otra instancia registrada en el tema.
@immutable
class BrandTokens extends ThemeExtension<BrandTokens> {
  // Marca / acción (reservado a CTAs).
  final Color brandPrimary;
  final Color onBrand; // texto/íconos sobre el acento o el hero

  // Hero (banner oscuro con degradado).
  final Color heroTop;
  final Color heroBottom;

  // Superficies / base (neutras y calmadas).
  final Color background;
  final Color surface;
  final Color surfaceGlassHigh; // relleno translúcido del vidrio (arriba)
  final Color surfaceGlassLow; // relleno translúcido del vidrio (abajo)
  final Color glassBorder; // borde/canto claro del vidrio

  // Texto (contraste suficiente sobre superficies y sobre glass).
  final Color textPrimary;
  final Color textSecondary;
  final Color textDisabled;

  // Bordes / estado del sistema.
  final Color border;
  final Color focus;
  final Color info;

  // Estado CLÍNICO (semáforo). Único uso legítimo de rojo/amarillo/verde.
  final Color statusDanger;
  final Color statusWarning;
  final Color statusSuccess;
  final Color statusNeutral;

  const BrandTokens({
    required this.brandPrimary,
    required this.onBrand,
    required this.heroTop,
    required this.heroBottom,
    required this.background,
    required this.surface,
    required this.surfaceGlassHigh,
    required this.surfaceGlassLow,
    required this.glassBorder,
    required this.textPrimary,
    required this.textSecondary,
    required this.textDisabled,
    required this.border,
    required this.focus,
    required this.info,
    required this.statusDanger,
    required this.statusWarning,
    required this.statusSuccess,
    required this.statusNeutral,
  });

  /// Única marca implementada por ahora: Kura.
  static const BrandTokens kura = BrandTokens(
    brandPrimary: KuraPalette.brandPrimary,
    onBrand: KuraPalette.onBrand,
    heroTop: KuraPalette.heroTop,
    heroBottom: KuraPalette.heroBottom,
    background: KuraPalette.background,
    surface: KuraPalette.surface,
    // Relleno del vidrio: alto (0.72) arriba y algo más translúcido (0.55)
    // abajo, para el "sheen". Deliberadamente alto para no lavar el texto
    // clínico sobre el vidrio.
    surfaceGlassHigh: Color(0xB8FFFFFF),
    surfaceGlassLow: Color(0x8CFFFFFF),
    glassBorder: Color(0x99FFFFFF),
    textPrimary: KuraPalette.textPrimary,
    textSecondary: Color(0xFF6B6577),
    textDisabled: Color(0xFFAEA9BC),
    border: KuraPalette.border,
    focus: KuraPalette.brandPrimary,
    info: KuraPalette.info,
    statusDanger: KuraPalette.statusDanger,
    statusWarning: KuraPalette.statusWarning,
    statusSuccess: KuraPalette.statusSuccess,
    statusNeutral: Color(0xFF9E968E),
  );

  /// Acceso desde cualquier widget. Cae a [kura] si el tema no registró la
  /// extensión (p.ej. en tests que arman un MaterialApp mínimo).
  static BrandTokens of(BuildContext context) =>
      Theme.of(context).extension<BrandTokens>() ?? kura;

  @override
  BrandTokens copyWith({
    Color? brandPrimary,
    Color? onBrand,
    Color? heroTop,
    Color? heroBottom,
    Color? background,
    Color? surface,
    Color? surfaceGlassHigh,
    Color? surfaceGlassLow,
    Color? glassBorder,
    Color? textPrimary,
    Color? textSecondary,
    Color? textDisabled,
    Color? border,
    Color? focus,
    Color? info,
    Color? statusDanger,
    Color? statusWarning,
    Color? statusSuccess,
    Color? statusNeutral,
  }) {
    return BrandTokens(
      brandPrimary: brandPrimary ?? this.brandPrimary,
      onBrand: onBrand ?? this.onBrand,
      heroTop: heroTop ?? this.heroTop,
      heroBottom: heroBottom ?? this.heroBottom,
      background: background ?? this.background,
      surface: surface ?? this.surface,
      surfaceGlassHigh: surfaceGlassHigh ?? this.surfaceGlassHigh,
      surfaceGlassLow: surfaceGlassLow ?? this.surfaceGlassLow,
      glassBorder: glassBorder ?? this.glassBorder,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textDisabled: textDisabled ?? this.textDisabled,
      border: border ?? this.border,
      focus: focus ?? this.focus,
      info: info ?? this.info,
      statusDanger: statusDanger ?? this.statusDanger,
      statusWarning: statusWarning ?? this.statusWarning,
      statusSuccess: statusSuccess ?? this.statusSuccess,
      statusNeutral: statusNeutral ?? this.statusNeutral,
    );
  }

  @override
  BrandTokens lerp(ThemeExtension<BrandTokens>? other, double t) {
    if (other is! BrandTokens) return this;
    return BrandTokens(
      brandPrimary: Color.lerp(brandPrimary, other.brandPrimary, t)!,
      onBrand: Color.lerp(onBrand, other.onBrand, t)!,
      heroTop: Color.lerp(heroTop, other.heroTop, t)!,
      heroBottom: Color.lerp(heroBottom, other.heroBottom, t)!,
      background: Color.lerp(background, other.background, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceGlassHigh: Color.lerp(surfaceGlassHigh, other.surfaceGlassHigh, t)!,
      surfaceGlassLow: Color.lerp(surfaceGlassLow, other.surfaceGlassLow, t)!,
      glassBorder: Color.lerp(glassBorder, other.glassBorder, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      textDisabled: Color.lerp(textDisabled, other.textDisabled, t)!,
      border: Color.lerp(border, other.border, t)!,
      focus: Color.lerp(focus, other.focus, t)!,
      info: Color.lerp(info, other.info, t)!,
      statusDanger: Color.lerp(statusDanger, other.statusDanger, t)!,
      statusWarning: Color.lerp(statusWarning, other.statusWarning, t)!,
      statusSuccess: Color.lerp(statusSuccess, other.statusSuccess, t)!,
      statusNeutral: Color.lerp(statusNeutral, other.statusNeutral, t)!,
    );
  }
}

/// Escala de espaciado (múltiplos de 4). App-level (no varía por marca).
class AppSpacing {
  AppSpacing._();
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;
}

/// Escala de radios de esquina.
class AppRadii {
  AppRadii._();
  static const double sm = 8;
  static const double md = 16;
  static const double lg = 24;
  static const double pill = 30;

  static const BorderRadius smR = BorderRadius.all(Radius.circular(sm));
  static const BorderRadius mdR = BorderRadius.all(Radius.circular(md));
  static const BorderRadius lgR = BorderRadius.all(Radius.circular(lg));
  static const BorderRadius pillR = BorderRadius.all(Radius.circular(pill));
}

/// Sombras/elevación. La sombra de tarjeta es EN CAPAS (contacto cercano +
/// profundidad amplia), reutilizada por el vidrio; la de marca se usa para el
/// FAB (glow del acento). Colores precomputados (ARGB) para poder ser `const`.
class AppShadows {
  AppShadows._();

  /// Sombra en capas para tarjetas/vidrio (textPrimary a ~7% y ~10%).
  static const List<BoxShadow> card = [
    BoxShadow(color: Color(0x12211813), blurRadius: 6, offset: Offset(0, 2)),
    BoxShadow(color: Color(0x1A211813), blurRadius: 24, offset: Offset(0, 12)),
  ];

  /// Sombra en capas del FAB (brandPrimary a ~30% y ~22%).
  static const List<BoxShadow> brandFab = [
    BoxShadow(color: Color(0x4CEC0244), blurRadius: 8, offset: Offset(0, 3)),
    BoxShadow(color: Color(0x38EC0244), blurRadius: 22, offset: Offset(0, 12)),
  ];
}

/// Escala tipográfica (tamaños/pesos). La FUENTE la aplica el tema
/// (GoogleFonts.nunito, ver KuraTheme) — estos tokens estandarizan tamaños y
/// pesos para que los componentes no usen literales sueltos.
class AppType {
  AppType._();
  static const double display = 28;
  static const double headline = 22;
  static const double title = 16;
  static const double body = 14;
  static const double label = 12;
  static const double caption = 11;

  static const FontWeight regular = FontWeight.w400;
  static const FontWeight medium = FontWeight.w500;
  static const FontWeight semibold = FontWeight.w600;
  static const FontWeight bold = FontWeight.w700;
  static const FontWeight extrabold = FontWeight.w800;
}
