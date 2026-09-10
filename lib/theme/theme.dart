/// Visual theme. Colors ported directly from the Python desktop app's
/// `gui/theme.py`, which already implements the SavePoint brand palette
/// (see Docs/gui_theming.md there) -- dark background, purple card fills,
/// thick flat borders, zero corner radius, no gradients/shadows.
///
/// NOT yet verified against the live savepoint.cc site pixel-for-pixel
/// (only a text-only fetch was possible during planning) -- treat this as a
/// faithful port of what the existing app already claims, to be checked
/// against real brand assets/screenshots later.
library;

import 'package:flutter/material.dart';

const colorPurple = Color(0xFFB791C2);
const colorYellow = Color(0xFFEECC67);
const colorBlue = Color(0xFF699FD5);
const colorGreen = Color(0xFF82C889);
const colorBlack = Color(0xFF000000);
const colorWhite = Color(0xFFFFFFFF);

const borderWidth = 3.0;

ThemeData buildAppTheme() {
  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: colorBlack,
    colorScheme: const ColorScheme.dark(
      primary: colorPurple,
      secondary: colorBlue,
      surface: colorBlack,
      error: colorYellow,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: colorBlack,
      foregroundColor: colorWhite,
      elevation: 0,
      shape: Border(bottom: BorderSide(color: colorWhite, width: borderWidth)),
    ),
    cardTheme: CardThemeData(
      color: colorPurple,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.zero,
        side: BorderSide(color: colorWhite, width: borderWidth),
      ),
      margin: const EdgeInsets.all(8),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: colorPurple,
        foregroundColor: colorBlack,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.zero,
          side: BorderSide(color: colorWhite, width: borderWidth),
        ),
      ),
    ),
    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      backgroundColor: colorBlack,
      selectedItemColor: colorGreen,
      unselectedItemColor: colorWhite,
      type: BottomNavigationBarType.fixed,
    ),
    inputDecorationTheme: const InputDecorationTheme(
      filled: true,
      fillColor: colorBlack,
      border: OutlineInputBorder(borderRadius: BorderRadius.zero, borderSide: BorderSide(color: colorWhite)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.zero, borderSide: BorderSide(color: colorWhite)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.zero, borderSide: BorderSide(color: colorGreen, width: 2)),
    ),
    textTheme: const TextTheme(
      headlineMedium: TextStyle(color: colorWhite, fontWeight: FontWeight.bold),
      bodyMedium: TextStyle(color: colorWhite),
      bodyLarge: TextStyle(color: colorWhite),
    ),
  );
}
