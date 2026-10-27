/// Visual theme, taken from savepoint.co.nz's own stylesheet (its CSS
/// custom properties, read directly from the live site): warm paper
/// background, ink text, a plum header with a purple underline, yellow
/// buttons, 3px ink borders, square corners and hard offset "pixel"
/// shadows instead of blurred elevation. Chakra Petch for headings and
/// labels, Figtree for body text, both bundled (assets/fonts). See
/// Docs/gui_theming.md.
library;

import 'package:flutter/material.dart';

// Brand tokens, named as on the site.
const colorPaper = Color(0xFFF7F4EF);
const colorPaperRaised = Color(0xFFFFFFFF);
const colorPaperTint = Color(0xFFEFE8F2);
const colorInk = Color(0xFF221C27);
const colorInkSoft = Color(0xFF4A4352);
const colorPlum = Color(0xFF2B2233);
const colorPlumSoft = Color(0xFF3A2F45);
const colorOnPlum = Color(0xFFFFFFFF);
const colorOnPlumSoft = Color(0xFFE4DCEA);
const colorPurple = Color(0xFFB791C2);
const colorPurpleDeep = Color(0xFF5B3D6B);
const colorYellow = Color(0xFFEECC67);
const colorBlue = Color(0xFF699FD5);
const colorGreen = Color(0xFF82C88A);
// Not a site token: the site never shows an error. A deep red that still
// reads against paper, for wrong answers and destructive actions.
const colorDanger = Color(0xFFB3261E);

const borderWidth = 3.0;
const fontDisplay = 'ChakraPetch';
const fontBody = 'Figtree';

const inkBorder = BorderSide(color: colorInk, width: borderWidth);

/// The site's `--pixel-shadow`: a solid block offset down-right, no blur.
List<BoxShadow> pixelShadow({Color color = colorPurple, double offset = 6}) => [
      BoxShadow(color: color, offset: Offset(offset, offset)),
    ];

const _squareInk = RoundedRectangleBorder(borderRadius: BorderRadius.zero, side: inkBorder);

TextStyle _display(double size, {FontWeight weight = FontWeight.w700, Color color = colorInk}) =>
    TextStyle(fontFamily: fontDisplay, fontSize: size, fontWeight: weight, color: color, height: 1.2);

ThemeData buildAppTheme() {
  const scheme = ColorScheme.light(
    primary: colorPurpleDeep,
    onPrimary: colorOnPlum,
    primaryContainer: colorPaperTint,
    onPrimaryContainer: colorInk,
    secondary: colorYellow,
    onSecondary: colorInk,
    secondaryContainer: colorYellow,
    onSecondaryContainer: colorInk,
    tertiary: colorBlue,
    surface: colorPaper,
    onSurface: colorInk,
    onSurfaceVariant: colorInkSoft,
    surfaceContainerLowest: colorPaperRaised,
    surfaceContainerLow: colorPaperRaised,
    surfaceContainer: colorPaperRaised,
    surfaceContainerHigh: colorPaperTint,
    surfaceContainerHighest: colorPaperTint,
    outline: colorInk,
    outlineVariant: colorInkSoft,
    error: colorDanger,
  );

  final buttonText = _display(17, weight: FontWeight.w700);
  const buttonPadding = EdgeInsets.symmetric(horizontal: 20, vertical: 14);

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    fontFamily: fontBody,
    scaffoldBackgroundColor: colorPaper,
    splashFactory: NoSplash.splashFactory,
    textTheme: TextTheme(
      displaySmall: _display(34),
      headlineMedium: _display(28),
      headlineSmall: _display(24),
      titleLarge: _display(21),
      titleMedium: _display(17, weight: FontWeight.w600),
      titleSmall: _display(15, weight: FontWeight.w600),
      labelLarge: _display(15, weight: FontWeight.w600),
      bodyLarge: const TextStyle(fontSize: 16, height: 1.5, color: colorInk),
      bodyMedium: const TextStyle(fontSize: 15, height: 1.5, color: colorInk),
      bodySmall: const TextStyle(fontSize: 13, height: 1.4, color: colorInkSoft),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: colorPlum,
      foregroundColor: colorOnPlum,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: _display(22, color: colorOnPlum),
      shape: const Border(bottom: BorderSide(color: colorPurple, width: 4)),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: colorPlum,
      indicatorColor: colorYellow,
      indicatorShape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      surfaceTintColor: Colors.transparent,
      height: 68,
      iconTheme: WidgetStateProperty.resolveWith(
        (states) => IconThemeData(color: states.contains(WidgetState.selected) ? colorInk : colorOnPlumSoft),
      ),
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => _display(
          13,
          weight: FontWeight.w600,
          color: states.contains(WidgetState.selected) ? colorYellow : colorOnPlumSoft,
        ),
      ),
    ),
    cardTheme: const CardThemeData(
      color: colorPaperRaised,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: _squareInk,
      margin: EdgeInsets.symmetric(vertical: 6),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: colorYellow,
        foregroundColor: colorInk,
        disabledBackgroundColor: colorPaperTint,
        disabledForegroundColor: colorInkSoft,
        elevation: 0,
        shape: _squareInk,
        padding: buttonPadding,
        minimumSize: const Size(64, 50),
        textStyle: buttonText,
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: colorPlum,
        foregroundColor: colorOnPlum,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero, side: BorderSide(color: colorPlum, width: borderWidth)),
        padding: buttonPadding,
        minimumSize: const Size(64, 50),
        textStyle: buttonText,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: colorInk,
        backgroundColor: colorPaperRaised,
        side: inkBorder,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
        padding: buttonPadding,
        minimumSize: const Size(64, 50),
        textStyle: buttonText,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: colorPurpleDeep,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
        textStyle: _display(15, weight: FontWeight.w700),
      ),
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: colorYellow,
      foregroundColor: colorInk,
      elevation: 0,
      focusElevation: 0,
      hoverElevation: 0,
      highlightElevation: 0,
      shape: _squareInk,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: colorPaperRaised,
      labelStyle: const TextStyle(color: colorInkSoft),
      floatingLabelStyle: _display(15, weight: FontWeight.w600, color: colorPurpleDeep),
      border: const OutlineInputBorder(borderRadius: BorderRadius.zero, borderSide: BorderSide(color: colorInk, width: 2)),
      enabledBorder:
          const OutlineInputBorder(borderRadius: BorderRadius.zero, borderSide: BorderSide(color: colorInk, width: 2)),
      focusedBorder: const OutlineInputBorder(
        borderRadius: BorderRadius.zero,
        borderSide: BorderSide(color: colorPurpleDeep, width: borderWidth),
      ),
      disabledBorder:
          const OutlineInputBorder(borderRadius: BorderRadius.zero, borderSide: BorderSide(color: colorInkSoft)),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: colorPaperRaised,
      selectedColor: colorYellow,
      checkmarkColor: colorInk,
      side: const BorderSide(color: colorInk, width: 2),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      labelStyle: _display(14, weight: FontWeight.w600),
    ),
    listTileTheme: ListTileThemeData(
      iconColor: colorPurpleDeep,
      titleTextStyle: const TextStyle(fontFamily: fontBody, fontSize: 16, fontWeight: FontWeight.w600, color: colorInk),
      subtitleTextStyle: const TextStyle(fontFamily: fontBody, fontSize: 14, color: colorInkSoft),
    ),
    dividerTheme: const DividerThemeData(color: colorPaperTint, thickness: 2),
    dialogTheme: DialogThemeData(
      backgroundColor: colorPaperRaised,
      surfaceTintColor: Colors.transparent,
      shape: _squareInk,
      titleTextStyle: _display(21),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: colorPaper,
      surfaceTintColor: Colors.transparent,
      shape: Border(top: BorderSide(color: colorInk, width: borderWidth)),
    ),
    popupMenuTheme: const PopupMenuThemeData(color: colorPaperRaised, shape: _squareInk),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: colorPlum,
      contentTextStyle: const TextStyle(fontFamily: fontBody, color: colorOnPlum, fontSize: 15),
      behavior: SnackBarBehavior.floating,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero, side: BorderSide(color: colorPurple, width: 2)),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(color: colorPurpleDeep, linearTrackColor: colorPaperTint),
    sliderTheme: const SliderThemeData(
      activeTrackColor: colorPurpleDeep,
      inactiveTrackColor: colorPaperTint,
      thumbColor: colorYellow,
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? colorYellow : colorInkSoft),
      trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? colorPlum : colorPaperTint),
      trackOutlineColor: const WidgetStatePropertyAll(colorInk),
    ),
    radioTheme: const RadioThemeData(fillColor: WidgetStatePropertyAll(colorPurpleDeep)),
  );
}
