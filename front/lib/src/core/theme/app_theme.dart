import 'package:flutter/material.dart';

class AppTheme {
  static ThemeData light() {
    const seed = Color(0xFF0F766E);

    final colorScheme = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: Brightness.light,
    );

    return ThemeData(
      colorScheme: colorScheme,
      useMaterial3: true,
      scaffoldBackgroundColor: const Color(0xFFF6F7F9),
      appBarTheme: const AppBarTheme(centerTitle: false),
      cardTheme: CardThemeData(
        color: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 0.8,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
    );
  }
}
