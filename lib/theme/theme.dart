/// Builds QuillFin's light and dark themes from the tokens in brand.dart:
/// calm paper background, hairline borders, soft rounded surfaces, teal
/// ("fin") primary and gold ("quill") highlights. Outfit for headings and
/// controls, Inter for body text, both bundled (assets/fonts). See
/// Docs/gui_theming.md.
library;

import 'package:flutter/material.dart';

import 'brand.dart';

export 'brand.dart';

ThemeData buildAppTheme({Brightness brightness = Brightness.light}) {
  final p = brightness == Brightness.dark ? BrandPalette.dark : BrandPalette.light;
  final scheme = ColorScheme(
    brightness: brightness,
    primary: p.fin,
    onPrimary: p.onFin,
    primaryContainer: p.surfaceTint,
    onPrimaryContainer: p.ink,
    secondary: p.quill,
    onSecondary: p.onQuill,
    secondaryContainer: p.quill,
    onSecondaryContainer: p.onQuill,
    tertiary: p.info,
    onTertiary: p.onFin,
    error: p.danger,
    onError: p.onFin,
    surface: p.paper,
    onSurface: p.ink,
    onSurfaceVariant: p.inkSoft,
    surfaceContainerLowest: p.surface,
    surfaceContainerLow: p.surface,
    surfaceContainer: p.surface,
    surfaceContainerHigh: p.surfaceTint,
    surfaceContainerHighest: p.surfaceTint,
    outline: p.line,
    outlineVariant: p.line,
    inverseSurface: p.deep,
    onInverseSurface: p.onDeep,
  );

  TextStyle display(double size, {FontWeight weight = FontWeight.w700, double height = 1.2, double spacing = -0.2}) =>
      TextStyle(fontFamily: fontDisplay, fontSize: size, fontWeight: weight, color: p.ink, height: height, letterSpacing: spacing);

  final controlShape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusControl));
  const controlPadding = EdgeInsets.symmetric(horizontal: 20, vertical: 14);
  const controlSize = Size(64, 48);
  final controlText = display(16, weight: FontWeight.w600, spacing: 0);
  OutlineInputBorder inputBorder(Color color, [double width = hairline]) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(radiusControl),
        borderSide: BorderSide(color: color, width: width),
      );

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    fontFamily: fontBody,
    scaffoldBackgroundColor: p.paper,
    extensions: [BrandColors(p)],
    visualDensity: VisualDensity.standard,
    textTheme: TextTheme(
      displaySmall: display(36, spacing: -0.6),
      headlineMedium: display(28, spacing: -0.4),
      headlineSmall: display(24, spacing: -0.3),
      titleLarge: display(20, weight: FontWeight.w600),
      titleMedium: display(17, weight: FontWeight.w600, spacing: 0),
      titleSmall: display(15, weight: FontWeight.w600, spacing: 0),
      labelLarge: display(15, weight: FontWeight.w600, spacing: 0),
      bodyLarge: TextStyle(fontSize: 16, height: 1.5, color: p.ink),
      bodyMedium: TextStyle(fontSize: 15, height: 1.5, color: p.ink),
      bodySmall: TextStyle(fontSize: 13, height: 1.4, color: p.inkSoft),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: p.paper,
      foregroundColor: p.ink,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: display(22),
      shape: Border(bottom: BorderSide(color: p.line)),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: p.surface,
      indicatorColor: p.surfaceTint,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      height: 68,
      iconTheme: WidgetStateProperty.resolveWith(
        (s) => IconThemeData(color: s.contains(WidgetState.selected) ? p.fin : p.inkSoft),
      ),
      labelTextStyle: WidgetStateProperty.resolveWith(
        (s) => display(12.5, weight: FontWeight.w600, spacing: 0)
            .copyWith(color: s.contains(WidgetState.selected) ? p.fin : p.inkSoft),
      ),
    ),
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: p.surface,
      indicatorColor: p.surfaceTint,
      selectedIconTheme: IconThemeData(color: p.fin),
      unselectedIconTheme: IconThemeData(color: p.inkSoft),
      selectedLabelTextStyle: display(12.5, weight: FontWeight.w600, spacing: 0).copyWith(color: p.fin),
      unselectedLabelTextStyle: display(12.5, weight: FontWeight.w600, spacing: 0).copyWith(color: p.inkSoft),
    ),
    cardTheme: CardThemeData(
      color: p.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusCard), side: BorderSide(color: p.line)),
      margin: const EdgeInsets.symmetric(vertical: 5),
      clipBehavior: Clip.antiAlias,
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: p.fin,
        foregroundColor: p.onFin,
        disabledBackgroundColor: p.surfaceTint,
        disabledForegroundColor: p.inkSoft,
        elevation: 0,
        shape: controlShape,
        padding: controlPadding,
        minimumSize: controlSize,
        textStyle: controlText,
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: p.fin,
        foregroundColor: p.onFin,
        shape: controlShape,
        padding: controlPadding,
        minimumSize: controlSize,
        textStyle: controlText,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: p.ink,
        backgroundColor: p.surface,
        side: BorderSide(color: p.line),
        shape: controlShape,
        padding: controlPadding,
        minimumSize: controlSize,
        textStyle: controlText,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: p.fin, shape: controlShape, textStyle: controlText),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: p.fin,
      foregroundColor: p.onFin,
      elevation: 2,
      highlightElevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: p.surface,
      labelStyle: TextStyle(color: p.inkSoft),
      hintStyle: TextStyle(color: p.inkSoft),
      floatingLabelStyle: TextStyle(color: p.fin, fontWeight: FontWeight.w600),
      border: inputBorder(p.line),
      enabledBorder: inputBorder(p.line),
      focusedBorder: inputBorder(p.fin, 2),
      errorBorder: inputBorder(p.danger),
      focusedErrorBorder: inputBorder(p.danger, 2),
      disabledBorder: inputBorder(p.line),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: p.surface,
      selectedColor: p.surfaceTint,
      checkmarkColor: p.fin,
      side: BorderSide(color: p.line),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusPill)),
      labelStyle: display(14, weight: FontWeight.w500, spacing: 0),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    ),
    listTileTheme: ListTileThemeData(
      iconColor: p.inkSoft,
      titleTextStyle: TextStyle(fontFamily: fontBody, fontSize: 16, fontWeight: FontWeight.w600, color: p.ink),
      subtitleTextStyle: TextStyle(fontFamily: fontBody, fontSize: 14, color: p.inkSoft),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusControl)),
    ),
    dividerTheme: DividerThemeData(color: p.line, thickness: hairline, space: 1),
    dialogTheme: DialogThemeData(
      backgroundColor: p.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      titleTextStyle: display(20, weight: FontWeight.w600),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: p.paper,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
      dragHandleColor: p.line,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: p.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusControl), side: BorderSide(color: p.line)),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: p.deep,
      contentTextStyle: TextStyle(fontFamily: fontBody, color: p.onDeep, fontSize: 15),
      behavior: SnackBarBehavior.floating,
      width: null,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusControl)),
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(color: p.deep, borderRadius: BorderRadius.circular(8)),
      textStyle: TextStyle(fontFamily: fontBody, color: p.onDeep, fontSize: 13),
      waitDuration: const Duration(milliseconds: 400),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(color: p.fin, linearTrackColor: p.surfaceTint),
    sliderTheme: SliderThemeData(activeTrackColor: p.fin, inactiveTrackColor: p.surfaceTint, thumbColor: p.fin),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? p.onFin : p.inkSoft),
      trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? p.fin : p.surfaceTint),
      trackOutlineColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? p.fin : p.line),
    ),
    radioTheme: RadioThemeData(fillColor: WidgetStatePropertyAll(p.fin)),
    checkboxTheme: CheckboxThemeData(fillColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? p.fin : null)),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: SegmentedButton.styleFrom(
        selectedBackgroundColor: p.surfaceTint,
        selectedForegroundColor: p.fin,
        side: BorderSide(color: p.line),
        textStyle: display(14, weight: FontWeight.w600, spacing: 0),
      ),
    ),
  );
}
