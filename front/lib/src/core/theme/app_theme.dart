import 'package:flutter/material.dart';

class AppPalette {
  const AppPalette._();

  static const primary = Color(0xFF0B7468);
  static const ink = Color(0xFF14201F);
  static const muted = Color(0xFF5B6B6A);
  static const border = Color(0xFFD9E3E3);
  static const background = Color(0xFFF5F8F9);
  static const loginBackground = Color(0xFFD3E8E5);

  static const mint = Color(0xFFC9F2E8);
  static const mintBorder = Color(0xFF8FDCCB);
  static const sky = Color(0xFFDFF1F8);
  static const skyBorder = Color(0xFFA9D8EA);
  static const blush = Color(0xFFFDE8E6);
  static const blushBorder = Color(0xFFF3B8B2);
  static const danger = Color(0xFFB42318);
  static const online = Color(0xFF3CB371);

  /// Fondos pastel para los avatares de apps, se eligen de forma estable por id.
  static const tileColors = <Color>[
    Color(0xFFB4EEDF),
    Color(0xFFC6E6FA),
    Color(0xFFFCE3B4),
    Color(0xFFE5D9FB),
    Color(0xFFFBD5DC),
  ];

  static Color tileColorFor(String seed) {
    final hash = seed.codeUnits.fold<int>(0, (acc, unit) => acc + unit);
    return tileColors[hash % tileColors.length];
  }
}

class AppTheme {
  static ThemeData light() {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: AppPalette.primary,
      brightness: Brightness.light,
      primary: AppPalette.primary,
      secondary: const Color(0xFF2563EB),
      tertiary: const Color(0xFF7C3AED),
      error: AppPalette.danger,
      surface: Colors.white,
      onSurface: AppPalette.ink,
      onSurfaceVariant: AppPalette.muted,
      outlineVariant: AppPalette.border,
    );

    final inputBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: AppPalette.border),
    );

    return ThemeData(
      colorScheme: colorScheme,
      useMaterial3: true,
      scaffoldBackgroundColor: AppPalette.background,
      dividerTheme: const DividerThemeData(
        color: AppPalette.border,
        thickness: 1,
        space: 1,
      ),
      appBarTheme: const AppBarTheme(
        centerTitle: false,
        backgroundColor: AppPalette.background,
        foregroundColor: AppPalette.ink,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        titleTextStyle: TextStyle(
          color: AppPalette.ink,
          fontSize: 18,
          fontWeight: FontWeight.w700,
        ),
      ),
      cardTheme: CardThemeData(
        color: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AppPalette.border),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        hintStyle: const TextStyle(
          color: AppPalette.muted,
          fontWeight: FontWeight.w600,
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        border: inputBorder,
        enabledBorder: inputBorder,
        focusedBorder: inputBorder.copyWith(
          borderSide: const BorderSide(color: AppPalette.primary, width: 2),
        ),
        errorBorder: inputBorder.copyWith(
          borderSide: const BorderSide(color: AppPalette.danger),
        ),
        focusedErrorBorder: inputBorder.copyWith(
          borderSide: const BorderSide(color: AppPalette.danger, width: 2),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppPalette.primary,
          foregroundColor: Colors.white,
          minimumSize: const Size.fromHeight(52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          backgroundColor: const Color(0xFFEEF2F4),
          foregroundColor: AppPalette.ink,
          minimumSize: const Size.fromHeight(48),
          side: const BorderSide(color: AppPalette.border),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }
}
