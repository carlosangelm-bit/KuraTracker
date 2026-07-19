import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

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

class KuraTheme {
  static ThemeData get light {
    const tokens = BrandTokens.kura;
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
      extensions: const <ThemeExtension<dynamic>>[tokens],
    );

    final textTheme = GoogleFonts.nunitoTextTheme(base.textTheme).apply(
      bodyColor: KuraColors.darkText,
      displayColor: KuraColors.darkText,
    );

    return base.copyWith(
      textTheme: textTheme,
      appBarTheme: AppBarTheme(
        backgroundColor: KuraColors.lightBg,
        foregroundColor: KuraColors.darkText,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: GoogleFonts.nunito(
          color: KuraColors.darkText,
          fontSize: 20,
          fontWeight: FontWeight.w800,
        ),
      ),
      cardTheme: CardThemeData(
        color: KuraColors.surface,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: KuraColors.borderSubtle),
        ),
        margin: EdgeInsets.zero,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: KuraColors.primary,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: KuraColors.primary,
          side: const BorderSide(color: KuraColors.primary),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: KuraColors.primary),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: KuraColors.borderSubtle),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: KuraColors.borderSubtle),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: KuraColors.primary, width: 2),
        ),
      ),
      chipTheme: base.chipTheme.copyWith(
        backgroundColor: KuraColors.chipBg,
        selectedColor: KuraColors.primary.withOpacity(0.15),
        labelStyle: const TextStyle(color: KuraColors.darkText),
        side: BorderSide.none,
      ),
      dividerTheme: const DividerThemeData(color: KuraColors.borderSubtle),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: KuraColors.surface,
        selectedIconTheme: const IconThemeData(color: KuraColors.primary),
        selectedLabelTextStyle: const TextStyle(
          color: KuraColors.primary,
          fontWeight: FontWeight.w700,
        ),
        unselectedLabelTextStyle: const TextStyle(color: KuraColors.darkText),
      ),
      snackBarTheme: const SnackBarThemeData(
        backgroundColor: KuraColors.darkText,
        contentTextStyle: TextStyle(color: Colors.white),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}
