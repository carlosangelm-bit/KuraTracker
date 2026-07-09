import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Paleta y tipografia de marca Kura+ (seccion 9).
class KuraColors {
  static const Color primary = Color(0xFFEC0244); // magenta/rojo
  static const Color darkText = Color(0xFF211813);
  static const Color lightBg = Color(0xFFFBF5EC);
  static const Color surface = Colors.white;

  // Escenarios pronosticos
  static const Color scenarioA = Color(0xFF1B8A5A); // verde - cierre rapido
  static const Color scenarioB = Color(0xFFE8A93A); // ambar - cierre asistido
  static const Color scenarioC = Color(0xFFC0392B); // rojo - no cierre

  static const Color success = Color(0xFF1B8A5A);
  static const Color warning = Color(0xFFE8A93A);
  static const Color danger = Color(0xFFC0392B);
  static const Color infoBlue = Color(0xFF2E6E9E);

  static const Color borderSubtle = Color(0xFFE4D9C9);
  static const Color chipBg = Color(0xFFF3E9DA);
}

class KuraTheme {
  static ThemeData get light {
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: KuraColors.primary,
        primary: KuraColors.primary,
        surface: KuraColors.surface,
        brightness: Brightness.light,
      ),
      scaffoldBackgroundColor: KuraColors.lightBg,
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
