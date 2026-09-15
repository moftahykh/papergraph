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

  /// Dark-theme primary — Luminous Electric Cyan that radiates on charcoal.
  static const Color primaryLightBlue = Color(0xFF38BDF8);
  static const Color accentCyan = Color(0xFF38BDF8);

  /// Semantic colors, tailored to sit vibrantly on charcoal and light themes.
  static const Color accentEmerald = Color(0xFF10B981);
  static const Color accentAmber = Color(0xFFF59E0B);
  static const Color accentRose = Color(0xFFF43F5E);

  // ---- Scientific Semantic Tokens ----
  /// Action & Selection Purple — Reserved for user interaction, selected nodes, and active filters.
  static const Color actionPurple = Color(0xFF6366F1);
  static const Color actionPurpleDark = Color(0xFF818CF8);

  /// Citation Blue — Solid directional citation relationships and citation metrics.
  static const Color citationBlue = Color(0xFF2563EB);
  static const Color citationBlueDark = Color(0xFF3B82F6);

  /// Similarity Cyan — Dashed semantic similarity edges and similarity metrics.
  static const Color similarityCyan = Color(0xFF0891B2);
  static const Color similarityCyanDark = Color(0xFF06B6D4);

  /// Origin / Seed Green — Landmark origin paper indicator.
  static const Color originGreen = Color(0xFF059669);
  static const Color originGreenDark = Color(0xFF10B981);

  /// Neutral Node — Secondary / inactive graph elements.
  static const Color neutralNode = Color(0xFF64748B);
  static const Color neutralNodeDark = Color(0xFF334155);

  // ---- Charcoal Grey Palette (Refined matte charcoal with balanced contrast) ----
  /// Background: Deep matte charcoal grey
  static const Color darkBg = Color(0xFF111215);

  /// Surface / Toolbars: Neutral elevated charcoal
  static const Color darkSurface = Color(0xFF18191E);

  /// Cards / Sheets: High-contrast charcoal card container
  static const Color darkCard = Color(0xFF202229);

  /// Borders: Subtle refined charcoal border
  static const Color darkBorder = Color(0xFF2D3039);

  /// Text Primary: Crisp soft off-white for effortless readability
  static const Color darkTextPrimary = Color(0xFFF3F4F6);

  /// Text Secondary: Neutral muted silver-grey
  static const Color darkTextSecondary = Color(0xFF9CA3AF);

  // ---- Paper & Ink palette ----
  static const Color lightBg = Color(0xFFF9FAFB);
  static const Color lightSurface = Color(0xFFFFFFFF);
  static const Color lightCard = Color(0xFFFFFFFF);
  static const Color lightBorder = Color(0xFFE5E7EB);
  static const Color lightTextPrimary = Color(0xFF111827);
  static const Color lightTextSecondary = Color(0xFF4B5563);

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
        onPrimary: Color(0xFF111215),
        onSecondary: Color(0xFF111215),
        onSurface: darkTextPrimary,
      ),
      cardTheme: CardThemeData(
        color: darkCard,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
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
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: darkBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: darkBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
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
        secondary: accentEmerald,
        surface: lightSurface,
        error: accentRose,
        onPrimary: Colors.white,
        onSecondary: Colors.white,
        onSurface: lightTextPrimary,
      ),
      cardTheme: CardThemeData(
        color: lightCard,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
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
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: lightBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: lightBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
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
