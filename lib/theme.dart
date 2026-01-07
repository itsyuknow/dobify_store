import 'package:flutter/material.dart';

class DobifyColors {
  static const yellow = Color(0xFFFFD60A);
  static const black = Color(0xFF000000);
}

ThemeData dobifyTheme = ThemeData(
  useMaterial3: true,
  brightness: Brightness.dark,
  primaryColor: DobifyColors.yellow,
  scaffoldBackgroundColor: DobifyColors.black,
  colorScheme: const ColorScheme(
    brightness: Brightness.dark,
    primary: DobifyColors.yellow,
    onPrimary: DobifyColors.black,
    secondary: DobifyColors.yellow,
    onSecondary: DobifyColors.black,
    surface: DobifyColors.black,
    onSurface: DobifyColors.yellow,
    background: DobifyColors.black,
    onBackground: DobifyColors.yellow,
    error: DobifyColors.yellow,
    onError: DobifyColors.black,
  ),
  appBarTheme: const AppBarTheme(
    backgroundColor: DobifyColors.black,
    foregroundColor: DobifyColors.yellow,
    elevation: 0,
  ),
  textTheme: const TextTheme(
    bodyLarge: TextStyle(color: DobifyColors.yellow),
    bodyMedium: TextStyle(color: DobifyColors.yellow),
    bodySmall: TextStyle(color: DobifyColors.yellow),
    titleLarge: TextStyle(color: DobifyColors.yellow, fontWeight: FontWeight.bold),
    titleMedium: TextStyle(color: DobifyColors.yellow),
    titleSmall: TextStyle(color: DobifyColors.yellow),
  ),
  iconTheme: const IconThemeData(color: DobifyColors.yellow),
  inputDecorationTheme: InputDecorationTheme(
    filled: true,
    fillColor: DobifyColors.black,
    labelStyle: const TextStyle(color: DobifyColors.yellow),
    hintStyle: const TextStyle(color: DobifyColors.yellow),
    prefixIconColor: DobifyColors.yellow.withOpacity(0.9),
    enabledBorder: OutlineInputBorder(
      borderSide: const BorderSide(color: DobifyColors.yellow, width: 1.4),
      borderRadius: BorderRadius.circular(12),
    ),
    focusedBorder: OutlineInputBorder(
      borderSide: const BorderSide(color: DobifyColors.yellow, width: 1.8),
      borderRadius: BorderRadius.circular(12),
    ),
    border: OutlineInputBorder(
      borderSide: const BorderSide(color: DobifyColors.yellow),
      borderRadius: BorderRadius.circular(12),
    ),
  ),
  progressIndicatorTheme:
  const ProgressIndicatorThemeData(color: DobifyColors.yellow),
  filledButtonTheme: FilledButtonThemeData(
    style: ButtonStyle(
      backgroundColor: const WidgetStatePropertyAll<Color>(DobifyColors.yellow),
      foregroundColor: const WidgetStatePropertyAll<Color>(DobifyColors.black),
      overlayColor: const WidgetStatePropertyAll<Color>(DobifyColors.black),
      shape: WidgetStatePropertyAll<RoundedRectangleBorder>(
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      minimumSize: const WidgetStatePropertyAll<Size>(Size.fromHeight(48)),
    ),
  ),
  textButtonTheme: TextButtonThemeData(
    style: ButtonStyle(
      foregroundColor:
      const WidgetStatePropertyAll<Color>(DobifyColors.yellow),
      overlayColor:
      WidgetStatePropertyAll<Color>(DobifyColors.yellow.withOpacity(0.1)),
    ),
  ),
  // ✅ Updated for Flutter 3.19+: use CardThemeData instead of CardTheme
  cardTheme: CardThemeData(
    color: DobifyColors.black,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(14),
      side: const BorderSide(color: DobifyColors.yellow, width: 1.2),
    ),
    elevation: 0,
  ),
  listTileTheme: const ListTileThemeData(
    iconColor: DobifyColors.yellow,
    textColor: DobifyColors.yellow,
  ),
  dividerColor: DobifyColors.yellow,
);
