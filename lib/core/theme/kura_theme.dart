import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../models/center_type.dart';
import '../design/tokens.dart';

/// Compatibilidad hacia atrás: `KuraColors` es ahora un ALIAS DELGADO sobre los
/// tokens semánticos ([BrandTokens]/[KuraPalette], ver lib/core/design). No se
/// borra para no migrar de golpe todas las pantallas; el código nuevo debería
/// consumir `BrandTokens.of(context)` en vez de estas constantes.
///
/// Nota de disciplina de color: `primary` es el ACENTO DE MARCA y su uso
/// legítimo son las acciones (CTA/FAB/nav activo), no superficies ni
/// decoración. `success/warning/danger` son ESTADO CLÍNICO (semáforo).
class KuraColors {
  static const Color primary = KuraPalette.brandPrimary;
  static const Color darkText = KuraPalette.textPrimary;
  static const Color lightBg = KuraPalette.background;
  static const Color surface = KuraPalette.surface;

  // Escenarios pronósticos == estado clínico (mismos colores del semáforo).
  static const Color scenarioA = KuraPalette.statusSuccess;
  static const Color scenarioB = KuraPalette.statusWarning;
  static const Color scenarioC = KuraPalette.statusDanger;

  static const Color success = KuraPalette.statusSuccess;
  static const Color warning = KuraPalette.statusWarning;
  static const Color danger = KuraPalette.statusDanger;
  static const Color infoBlue = KuraPalette.info;

  static const Color borderSubtle = KuraPalette.border;
  static const Color chipBg = KuraPalette.chipBg;
}

/// Colores REALISTAS del lecho de la herida (clasificación RYB), para las
/// visualizaciones de composición del tejido. Fuente ÚNICA: antes estaban
/// duplicados e inconsistentes entre la gráfica de seguimiento y los sliders
/// de captura (la necrosis, por ejemplo, salía roja en una y gris en otra).
///
/// NO son estado clínico (semáforo `success/warning/danger`): representan el
/// aspecto real del tejido para que la gráfica se lea como el lecho mismo.
class KuraTissueColors {
  static const Color granulacion = Color(0xFFB5463C); // rojo carne
  static const Color esfacelo = Color(0xFFD8B24A); // amarillo/tostado
  static const Color necrosis = Color(0xFF2B2B2B); // negro
  static const Color epitelizacion = Color(0xFFE79AAE); // rosa
}

class KuraTheme {
  /// Tema por defecto (clínica de heridas, morado). Alias de compatibilidad
  /// hacia atrás; el código nuevo/reactivo usa [forType].
  static ThemeData get light => forType(CenterType.clinicaHeridas);

  /// Construye el tema para el tipo de centro dado. La marca (acento/hero/
  /// superficies) proviene de [BrandTokens.forCenterType]; el resto de la
  /// estructura del tema es idéntica entre tipos. Al cambiar de centro, el
  /// MaterialApp reconstruye con el tema correspondiente (paleta morado/azul/
  /// rosa). El estado clínico (semáforo) NO cambia por tipo: es clínico.
  static ThemeData forType(CenterType type) {
    final tokens = BrandTokens.forCenterType(type);
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: tokens.brandPrimary,
        primary: tokens.brandPrimary,
        surface: tokens.surface,
        brightness: Brightness.light,
      ),
      scaffoldBackgroundColor: tokens.background,
      // Tokens semánticos disponibles vía BrandTokens.of(context).
      extensions: <ThemeExtension<dynamic>>[tokens],
    );

    final textTheme = GoogleFonts.nunitoTextTheme(base.textTheme).apply(
      bodyColor: tokens.textPrimary,
      displayColor: tokens.textPrimary,
    );

    return base.copyWith(
      textTheme: textTheme,
      appBarTheme: AppBarTheme(
        backgroundColor: tokens.background,
        foregroundColor: tokens.textPrimary,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: GoogleFonts.nunito(
          color: tokens.textPrimary,
          fontSize: 20,
          fontWeight: FontWeight.w800,
        ),
      ),
      cardTheme: CardThemeData(
        color: tokens.surface,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: tokens.border),
        ),
        margin: EdgeInsets.zero,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: tokens.brandPrimary,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: tokens.brandPrimary,
          side: BorderSide(color: tokens.brandPrimary),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: tokens.brandPrimary),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: tokens.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: tokens.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: tokens.brandPrimary, width: 2),
        ),
      ),
      chipTheme: base.chipTheme.copyWith(
        backgroundColor: KuraColors.chipBg,
        selectedColor: tokens.brandPrimary.withOpacity(0.15),
        labelStyle: TextStyle(color: tokens.textPrimary),
        side: BorderSide.none,
      ),
      dividerTheme: DividerThemeData(color: tokens.border),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: tokens.surface,
        selectedIconTheme: IconThemeData(color: tokens.brandPrimary),
        selectedLabelTextStyle: TextStyle(
          color: tokens.brandPrimary,
          fontWeight: FontWeight.w700,
        ),
        unselectedLabelTextStyle: TextStyle(color: tokens.textPrimary),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: tokens.textPrimary,
        contentTextStyle: const TextStyle(color: Colors.white),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}
