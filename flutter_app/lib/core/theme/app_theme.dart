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
  // ---- Brand accents ----
  /// Light-theme primary — Paper & Ink deep indigo.
  static const Color primaryBlue = Color(0xFF3730A3);
  /// Dark-theme primary — Dark Lab soft cyan.
  static const Color primaryLightBlue = Color(0xFF4AC6E3);
  static const Color accentCyan = Color(0xFF4AC6E3);
  /// Semantic colors, muted to sit well on both themes.
  static const Color accentEmerald = Color(0xFF2E7D5B);
  static const Color accentAmber = Color(0xFFB45309);
  static const Color accentRose = Color(0xFFC2404D);

  // ---- Dark Lab palette ----
  static const Color darkBg = Color(0xFF0B1220);
  static const Color darkSurface = Color(0xFF121C31);
  static const Color darkCard = Color(0xFF152238);
  static const Color darkBorder = Color(0xFF22304F);
  static const Color darkTextPrimary = Color(0xFFE6EDF7);
  static const Color darkTextSecondary = Color(0xFF93A3BE);

  // ---- Paper & Ink palette ----
  static const Color lightBg = Color(0xFFFAFAF7);
  static const Color lightSurface = Color(0xFFFFFFFF);
  static const Color lightCard = Color(0xFFFFFFFF);
  static const Color lightBorder = Color(0xFFE7E4DC);
  static const Color lightTextPrimary = Color(0xFF1B2432);
  static const Color lightTextSecondary = Color(0xFF667085);

  // Dark Lab
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
        onPrimary: Color(0xFF062631),
        onSecondary: Color(0xFF062631),
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
      appBarTheme: AppBarTheme(
        backgroundColor: darkBg,
        elevation: 0,
        centerTitle: false,
        iconTheme: const IconThemeData(color: darkTextPrimary),
        titleTextStyle: GoogleFonts.playfairDisplay(
          textStyle: const TextStyle(
            color: darkTextPrimary,
            fontSize: 22,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: darkSurface,
        selectedItemColor: primaryLightBlue,
        unselectedItemColor: darkTextSecondary,
        type: BottomNavigationBarType.fixed,
        elevation: 8,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: darkSurface,
        hintStyle: const TextStyle(color: darkTextSecondary, fontSize: 14),
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: darkBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: darkBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: primaryLightBlue, width: 2),
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
        secondary: accentEmerald,
        surface: lightSurface,
        error: accentRose,
        onPrimary: Colors.white,
        onSecondary: Colors.white,
        onSurface: lightTextPrimary,
      ),
      cardTheme: CardThemeData(
        color: lightCard,
        elevation: 2,
        shadowColor: Colors.black.withAlpha(8),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: lightBorder, width: 1),
        ),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: lightBg,
        elevation: 0,
        centerTitle: false,
        iconTheme: const IconThemeData(color: lightTextPrimary),
        titleTextStyle: GoogleFonts.playfairDisplay(
          textStyle: const TextStyle(
            color: lightTextPrimary,
            fontSize: 22,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: lightSurface,
        selectedItemColor: primaryBlue,
        unselectedItemColor: lightTextSecondary,
        type: BottomNavigationBarType.fixed,
        elevation: 8,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: lightSurface,
        hintStyle: const TextStyle(color: lightTextSecondary, fontSize: 14),
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: lightBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: lightBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: primaryBlue, width: 2),
        ),
      ),
      textTheme: _buildAppTextTheme(baseTextTheme, lightTextPrimary),
    );
  }

  static TextTheme _buildAppTextTheme(TextTheme base, Color color) {
    final interBase = GoogleFonts.interTextTheme(base).apply(
      bodyColor: color,
      displayColor: color,
    );

    return interBase.copyWith(
      displayLarge: GoogleFonts.playfairDisplay(
        textStyle: interBase.displayLarge?.copyWith(fontWeight: FontWeight.bold),
      ),
      displayMedium: GoogleFonts.playfairDisplay(
        textStyle: interBase.displayMedium?.copyWith(fontWeight: FontWeight.bold),
      ),
      displaySmall: GoogleFonts.playfairDisplay(
        textStyle: interBase.displaySmall?.copyWith(fontWeight: FontWeight.bold),
      ),
      headlineLarge: GoogleFonts.playfairDisplay(
        textStyle: interBase.headlineLarge?.copyWith(fontWeight: FontWeight.w700),
      ),
      headlineMedium: GoogleFonts.playfairDisplay(
        textStyle: interBase.headlineMedium?.copyWith(fontWeight: FontWeight.w700),
      ),
      headlineSmall: GoogleFonts.playfairDisplay(
        textStyle: interBase.headlineSmall?.copyWith(fontWeight: FontWeight.w600),
      ),
      titleLarge: GoogleFonts.playfairDisplay(
        textStyle: interBase.titleLarge?.copyWith(fontWeight: FontWeight.w600),
      ),
    );
  }
}
