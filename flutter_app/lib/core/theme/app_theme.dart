import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// PaperGraph design system.
///
/// Light theme = "Paper & Ink": warm academic-paper background, quiet UI,
/// and one deep-indigo accent.
/// Dark theme = "Dark Lab": a deep-navy lab canvas where graph nodes glow,
/// with one soft-cyan accent.
///
/// UI chrome stays intentionally quiet: in the graph canvas, color carries
/// meaning (the year gradient), so the interface never competes with the data.
class AppTheme {
  // ---- Brand Accents ----
  //
  // PaperGraph keeps primary actions in ink, then uses one cool blue for
  // selection, focus, and graph affordances. This keeps the academic tone
  // while giving the product a clearer interaction hierarchy.
  /// Light-theme primary — Deep zinc ink.
  static const Color primaryBlue = Color(0xFF18181B);
  static const Color lightPrimary = Color(0xFF18181B);
  static const Color uiBlue = Color(0xFF5269F4);
  static const Color uiBlueSoft = Color(0xFFEEF0FF);

  /// Dark-theme primary — Crisp off-white.
  static const Color primaryLightBlue = Color(0xFFF4F4F5);
  static const Color darkPrimary = Color(0xFFFFFFFF);
  static const Color accentCyan = Color(0xFFA1A1AA);

  /// Semantic colors, tailored to sit subtly on minimal monochrome canvas.
  static const Color accentEmerald = Color(0xFF10B981);
  static const Color accentAmber = Color(0xFFF59E0B);
  static const Color accentRose = Color(0xFFF43F5E);

  // ---- Scientific Semantic Tokens (Monochrome / Zinc) ----
  /// Action & Selection — Crisp high-contrast monochrome
  static const Color actionPurple = uiBlue;
  static const Color actionPurpleDark = Color(0xFFAAB5FF);

  /// Citation relationships and citation metrics — Crisp dark ink / zinc
  static const Color citationBlue = Color(0xFF25262C);
  static const Color citationBlueDark = Color(0xFFE4E4E7);

  /// Similarity edges and similarity metrics — Muted slate hairline
  static const Color similarityCyan = Color(0xFF71717A);
  static const Color similarityCyanDark = Color(0xFFA1A1AA);

  /// Origin / Seed paper indicator — Landmark deep ink / pure white
  static const Color originGreen = Color(0xFF18181B);
  static const Color originGreenDark = Color(0xFFFFFFFF);

  /// Neutral Node — Secondary / inactive graph elements.
  static const Color neutralNode = Color(0xFF71717A);
  static const Color neutralNodeDark = Color(0xFF3F3F46);

  // ---- Obsidian Dark Palette (From brand HTML spec: #09090B) ----
  /// Background: Deep obsidian
  static const Color darkBg = Color(0xFF09090B);

  /// Surface / Toolbars: Elevated dark surface
  static const Color darkSurface = Color(0xFF0F1013);

  /// Cards / Sheets: Dark card container
  static const Color darkCard = Color(0xFF141519);

  /// Borders: 8% white hairline border
  static const Color darkBorder = Color(0x1FFFFFFF);

  /// Text Primary: Crisp zinc off-white
  static const Color darkTextPrimary = Color(0xFFF4F4F5);

  /// Text Secondary: Muted zinc-500
  static const Color darkTextSecondary = Color(0xFF71717A);

  // ---- Paper & Ink Light Palette ----
  static const Color lightBg = Color(0xFFF5F5F7);
  static const Color lightSurface = Color(0xFFFFFFFF);
  static const Color lightCard = Color(0xFFFFFFFF);
  static const Color lightBorder = Color(0xFFE4E4E8);
  static const Color lightTextPrimary = Color(0xFF18181B);
  static const Color lightTextSecondary = Color(0xFF73747D);

  /// Instrument Serif italic brand typography helper for "PaperGraph"
  static TextStyle brandTitleStyle({
    double fontSize = 24,
    Color? color,
    FontWeight fontWeight = FontWeight.w400,
    double letterSpacing = -0.5,
  }) {
    return GoogleFonts.instrumentSerif(
      fontSize: fontSize,
      fontStyle: FontStyle.italic,
      fontWeight: fontWeight,
      color: color,
      letterSpacing: letterSpacing,
    );
  }

  // Charcoal Dark Theme
  static ThemeData get darkTheme {
    final baseTextTheme = ThemeData.dark().textTheme;
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: darkBg,
      primaryColor: primaryLightBlue,
      colorScheme: const ColorScheme.dark(
        primary: primaryLightBlue,
        secondary: accentCyan,
        surface: darkSurface,
        error: accentRose,
        onPrimary: Color(0xFF09090B),
        onSecondary: Color(0xFF09090B),
        onSurface: darkTextPrimary,
      ),
      cardTheme: CardThemeData(
        color: darkCard,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: darkBorder, width: 1),
        ),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: darkBg,
        elevation: 0,
        centerTitle: false,
        iconTheme: IconThemeData(color: darkTextPrimary),
        titleTextStyle: TextStyle(
          color: darkTextPrimary,
          fontSize: 18,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.2,
        ),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: darkSurface,
        selectedItemColor: primaryLightBlue,
        unselectedItemColor: darkTextSecondary,
        type: BottomNavigationBarType.fixed,
        elevation: 0,
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: Colors.white,
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          return states.contains(WidgetState.selected)
              ? darkBg
              : darkTextSecondary;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          return states.contains(WidgetState.selected)
              ? primaryLightBlue
              : darkBorder;
        }),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: darkSurface,
        hintStyle: const TextStyle(color: darkTextSecondary, fontSize: 14),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: darkBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: darkBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: primaryLightBlue, width: 1.5),
        ),
      ),
      textTheme: _buildAppTextTheme(baseTextTheme, darkTextPrimary),
    );
  }

  // Paper & Ink
  static ThemeData get lightTheme {
    final baseTextTheme = ThemeData.light().textTheme;
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      scaffoldBackgroundColor: lightBg,
      primaryColor: primaryBlue,
      colorScheme: const ColorScheme.light(
        primary: primaryBlue,
        secondary: Color(0xFF18181B),
        surface: lightSurface,
        error: accentRose,
        onPrimary: Colors.white,
        onSecondary: Colors.white,
        onSurface: lightTextPrimary,
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: Color(0xFF18181B),
        linearTrackColor: Color(0x14000000),
      ),
      cardTheme: CardThemeData(
        color: lightCard,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: lightBorder, width: 1),
        ),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: lightBg,
        elevation: 0,
        centerTitle: false,
        iconTheme: IconThemeData(color: lightTextPrimary),
        titleTextStyle: TextStyle(
          color: lightTextPrimary,
          fontSize: 18,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.2,
        ),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: lightSurface,
        selectedItemColor: primaryBlue,
        unselectedItemColor: lightTextSecondary,
        type: BottomNavigationBarType.fixed,
        elevation: 0,
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: const Color(0xFF18181B),
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          return states.contains(WidgetState.selected)
              ? Colors.white
              : lightTextSecondary;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          return states.contains(WidgetState.selected)
              ? primaryBlue
              : lightBorder;
        }),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: lightSurface,
        hintStyle: const TextStyle(color: lightTextSecondary, fontSize: 14),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: lightBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: lightBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: primaryBlue, width: 1.5),
        ),
      ),
      textTheme: _buildAppTextTheme(baseTextTheme, lightTextPrimary),
    );
  }

  static TextTheme _buildAppTextTheme(TextTheme base, Color color) {
    // Professional sans-serif typography scale (Inter) for optimal scientific readability
    final interBase = GoogleFonts.interTextTheme(
      base,
    ).apply(bodyColor: color, displayColor: color);

    return interBase.copyWith(
      displayLarge: interBase.displayLarge?.copyWith(
        fontWeight: FontWeight.w700,
        letterSpacing: -0.6,
      ),
      displayMedium: interBase.displayMedium?.copyWith(
        fontWeight: FontWeight.w700,
        letterSpacing: -0.5,
      ),
      displaySmall: interBase.displaySmall?.copyWith(
        fontWeight: FontWeight.w600,
        letterSpacing: -0.4,
      ),
      headlineLarge: interBase.headlineLarge?.copyWith(
        fontWeight: FontWeight.w700,
        letterSpacing: -0.4,
      ),
      headlineMedium: interBase.headlineMedium?.copyWith(
        fontWeight: FontWeight.w600,
        letterSpacing: -0.3,
      ),
      headlineSmall: interBase.headlineSmall?.copyWith(
        fontWeight: FontWeight.w600,
        letterSpacing: -0.2,
      ),
      titleLarge: interBase.titleLarge?.copyWith(
        fontWeight: FontWeight.w600,
        letterSpacing: -0.2,
      ),
      titleMedium: interBase.titleMedium?.copyWith(
        fontWeight: FontWeight.w600,
        letterSpacing: -0.1,
      ),
      titleSmall: interBase.titleSmall?.copyWith(fontWeight: FontWeight.w500),
      bodyLarge: interBase.bodyLarge?.copyWith(height: 1.5),
      bodyMedium: interBase.bodyMedium?.copyWith(height: 1.45),
      labelSmall: interBase.labelSmall?.copyWith(
        letterSpacing: 0.5,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}
