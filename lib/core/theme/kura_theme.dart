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
      // Interruptores tokenizados en los CUATRO estados (antes solo el encendido, vía
      // activeColor: suelto; el apagado caía en los grises de Material —contorno oscuro,
      // pulgar gris fuerte— que no siguen la marca y pesan MÁS que el encendido). El
      // apagado usa el token de BORDE (azul en hospital, rosa en cuidadores): sutil y de
      // marca. Se hereda en toda la app; nadie tiene que poner activeColor a mano.
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          final on = states.contains(WidgetState.selected);
          if (states.contains(WidgetState.disabled)) {
            return on ? tokens.onBrand : tokens.textDisabled;
          }
          return on ? tokens.onBrand : tokens.textSecondary;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          final on = states.contains(WidgetState.selected);
          if (states.contains(WidgetState.disabled)) {
            return on ? tokens.brandPrimary.withValues(alpha: 0.35) : tokens.chipBg;
          }
          return on ? tokens.brandPrimary : tokens.surface;
        }),
        trackOutlineColor: WidgetStateProperty.resolveWith((states) {
          // Encendido: track relleno de marca, sin contorno. Apagado: contorno = token de
          // BORDE (no el outline gris por defecto de Material).
          if (states.contains(WidgetState.selected)) return Colors.transparent;
          return tokens.border;
        }),
      ),
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
        // R2: eleva el snackbar flotante por encima de la barra de navegación
        // flotante (~64 px de kFloatingNavBarHeight) para que en móvil no quede
        // sobre la barra ni sobre la última tarjeta, ni intercepte sus toques.
        // No se puede usar MediaQuery aquí (contexto de tema), así que es una
        // constante; en escritorio (rail lateral) solo lo sube un poco.
        insetPadding: const EdgeInsets.only(left: 12, right: 12, bottom: 80),
      ),
      // Diálogos y hojas inferiores VESTIDOS desde el tema (no en los ~87 sitios de
      // llamada): sin esto caían en los defaults de Material 3 —radio 28, tinte de
      // elevación, tipografía por omisión— que chocan con las tarjetas (radio 16, borde de
      // token, sin tinte). Al vivir en el tema, el diálogo cambia de morado a azul o rosa
      // con el tipo de centro sin que nadie lo pida. Mismo lenguaje que cardTheme.
      // copyWith sobre el tema base (no el constructor FooThemeData) para NO depender del
      // nombre de la clase: entre Flutter 3.27 (CI) y el local cambió DialogTheme →
      // DialogThemeData; copyWith devuelve el tipo que use cada versión.
      dialogTheme: base.dialogTheme.copyWith(
        backgroundColor: tokens.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadii.mdR,
          side: BorderSide(color: tokens.border),
        ),
        titleTextStyle: GoogleFonts.nunito(
          color: tokens.textPrimary,
          fontSize: 20,
          fontWeight: FontWeight.w800,
        ),
        contentTextStyle: textTheme.bodyMedium?.copyWith(color: tokens.textPrimary),
      ),
      bottomSheetTheme: base.bottomSheetTheme.copyWith(
        backgroundColor: tokens.surface,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius:
              BorderRadius.vertical(top: Radius.circular(AppRadii.lg)),
        ),
      ),
    );
  }
}
