import 'package:flutter/material.dart';

/// RoadResQ Material 3 Theme Configuration
/// Responsive for Mobile + Tablet
class AppTheme {
  AppTheme._();

  // ──────────── Brand Colors ────────────
  static const Color primaryRed = Color(0xFFD32F2F);
  static const Color primaryBlue = Color(0xFF0D47A1);
  static const Color accentOrange = Color(0xFFFF7043);
  static const Color accentGreen = Color(0xFF2E7D32);
  static const Color surfaceLight = Color(0xFFF7F9FC);
  static const Color surfaceDark = Color(0xFF121212);
  static const Color textPrimary = Color(0xFF212121);
  static const Color textSecondary = Color(0xFF757575);

  // ──────────── Light Theme ────────────
  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      scaffoldBackgroundColor: surfaceLight,
      colorScheme: ColorScheme.fromSeed(
        seedColor: primaryRed,
        primary: primaryRed,
        secondary: primaryBlue,
        tertiary: accentOrange,
        surface: Colors.white,
        error: Colors.red,
        brightness: Brightness.light,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: primaryRed,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryRed,
          foregroundColor: Colors.white,
          elevation: 2,
          minimumSize: const Size(double.infinity, 54),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          textStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: primaryRed,
          side: const BorderSide(color: primaryRed),
          minimumSize: const Size(double.infinity, 54),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFFF3F4F6),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: primaryRed, width: 1.2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Colors.red, width: 1.2),
        ),
        labelStyle: const TextStyle(color: textSecondary),
      ),
      cardTheme: CardThemeData(
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
        ),
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        selectedItemColor: primaryRed,
        unselectedItemColor: textSecondary,
        type: BottomNavigationBarType.fixed,
        elevation: 8,
      ),
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
    );
  }

// Dark-mode surface tones
  // ──────────── Dark palette ────────────
  // A cool, layered set rather than pure black and one flat grey: background,
  // elevated card, field, border and muted text each need a distinct step or
  // the screen reads as a single dark slab (which is how the old dark mode
  // looked).
  static const Color darkBackground = Color(0xFF0F1420);
  static const Color darkSurface = Color(0xFF171E2B);
  static const Color darkSurfaceHigh = Color(0xFF1E2735);
  static const Color darkField = Color(0xFF232D3D);
  static const Color darkBorder = Color(0xFF2C3849);
  static const Color darkText = Color(0xFFE9EEF6);
  static const Color darkMuted = Color(0xFF9BA8BA);

  static const Color onDark = darkText;

  // ──────────── Dark Theme ────────────
  static ThemeData get darkTheme {
    final ColorScheme scheme = ColorScheme.fromSeed(
      seedColor: primaryRed,
      primary: const Color(0xFFEF5350),
      onPrimary: Colors.white,
      secondary: const Color(0xFF64B5F6),
      onSecondary: const Color(0xFF06121F),
      tertiary: accentOrange,
      surface: darkSurface,
      onSurface: darkText,
      surfaceContainerHighest: darkSurfaceHigh,
      error: const Color(0xFFEF9A9A),
      onError: const Color(0xFF2B0A0A),
      outline: darkBorder,
      brightness: Brightness.dark,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: darkBackground,
      colorScheme: scheme,
      textTheme: Typography.material2021(platform: TargetPlatform.android)
          .white
          .apply(bodyColor: darkText, displayColor: darkText),
      appBarTheme: const AppBarTheme(
        backgroundColor: darkSurface,
        foregroundColor: darkText,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: TextStyle(
          color: darkText,
          fontSize: 19,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.2,
        ),
      ),
      cardTheme: CardThemeData(
        color: darkSurfaceHigh,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: const BorderSide(color: darkBorder, width: 1),
        ),
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: darkSurfaceHigh,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: const TextStyle(
          color: darkText,
          fontSize: 18,
          fontWeight: FontWeight.w700,
        ),
        contentTextStyle: const TextStyle(color: darkMuted, height: 1.4),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
          side: const BorderSide(color: darkBorder),
        ),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: darkSurface,
        surfaceTintColor: Colors.transparent,
        modalBackgroundColor: darkSurface,
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: darkSurface,
        selectedItemColor: Color(0xFFEF5350),
        unselectedItemColor: darkMuted,
        selectedLabelStyle: TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
        unselectedLabelStyle: TextStyle(fontSize: 11),
        type: BottomNavigationBarType.fixed,
        elevation: 0,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: darkSurface,
        indicatorColor: const Color(0xFFEF5350).withAlpha((0.18 * 255).round()),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return TextStyle(
            fontSize: 11,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            color: selected ? const Color(0xFFEF5350) : darkMuted,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(
            color: selected ? const Color(0xFFEF5350) : darkMuted,
          );
        }),
      ),
      dividerTheme: const DividerThemeData(color: darkBorder, thickness: 1),
      chipTheme: ChipThemeData(
        backgroundColor: darkSurfaceHigh,
        side: const BorderSide(color: darkBorder),
        labelStyle: const TextStyle(color: darkText, fontSize: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: darkField,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        hintStyle: const TextStyle(color: darkMuted),
        labelStyle: const TextStyle(color: darkMuted),
        prefixIconColor: darkMuted,
        suffixIconColor: darkMuted,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: darkBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: darkBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Color(0xFFEF5350), width: 1.6),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFFEF5350),
          foregroundColor: Colors.white,
          elevation: 0,
          minimumSize: const Size(double.infinity, 54),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: const Color(0xFFEF9A9A),
          side: const BorderSide(color: darkBorder),
          minimumSize: const Size(double.infinity, 54),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
      snackBarTheme: const SnackBarThemeData(
        backgroundColor: darkSurfaceHigh,
        contentTextStyle: TextStyle(color: darkText),
        behavior: SnackBarBehavior.floating,
      ),
      listTileTheme: const ListTileThemeData(
        iconColor: darkMuted,
        textColor: darkText,
      ),
    );
  }

  /// Mirrors ThemeMode for the shared RQ widgets, which are static helpers
  /// without a BuildContext. Kept in sync by ThemeController.
  static bool isDarkMode = false;

  static Color get surfaceDynamic => isDarkMode ? darkSurfaceHigh : Colors.white;
  static Color get textDynamic =>
      isDarkMode ? darkText : const Color(0xFF14181D);
  static Color get mutedDynamic =>
      isDarkMode ? darkMuted : const Color(0xFF5F6B78);
  static Color get borderDynamic =>
      isDarkMode ? darkBorder : const Color(0xFFE3E8EE);

  /// Theme-aware surface helpers.
  ///
  /// Screens used to hardcode `Colors.white` cards and `Colors.black54` text.
  /// With those literals, dark mode produced white-on-white labels and light
  /// cards floating on black — the "unprofessional dark" report. These getters
  /// keep one source of truth for both modes.
  static Color surfaceOf(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? darkSurfaceHigh
          : Colors.white;

  static Color backgroundOf(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? darkBackground
          : surfaceLight;

  static Color textOf(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? darkText
          : const Color(0xFF14181D);

  static Color mutedOf(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? darkMuted
          : const Color(0xFF5F6B78);

  static Color borderOf(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? darkBorder
          : const Color(0xFFE3E8EE);

  static Color fieldOf(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? darkField
          : const Color(0xFFF3F4F6);

}
