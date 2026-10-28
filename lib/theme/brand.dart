/// QuillFin's brand tokens: the one file to edit when the real logo,
/// colours and fonts arrive (see Docs/quillfin_plan.md, "Visual identity").
/// Everything else reads colours through [BrandColors] (`context.brand`),
/// so light and dark mode both follow from here.
library;

import 'package:flutter/material.dart';

const brandName = 'QuillFin';
const brandOwner = 'Save Point';
const brandTagline = 'Notes, quizzes and practice that remember for you.';

const fontDisplay = 'Outfit';
const fontBody = 'Inter';

/// Corner radii and hairline width, shared by the theme and custom widgets.
const radiusCard = 14.0;
const radiusControl = 12.0;
const radiusPill = 999.0;
const hairline = 1.0;

class BrandPalette {
  /// Main text.
  final Color ink;

  /// Secondary text, icons.
  final Color inkSoft;

  /// Page background.
  final Color paper;

  /// Cards, sheets, inputs.
  final Color surface;

  /// Quiet fills: chips, tracks, selected rows.
  final Color surfaceTint;

  /// Hairline borders and dividers.
  final Color line;

  /// Primary: buttons, links, selection.
  final Color fin;
  final Color onFin;

  /// Deep accent for hero panels and headers.
  final Color deep;
  final Color onDeep;
  final Color onDeepSoft;

  /// Highlight accent: "due", streaks, the suggested rating.
  final Color quill;
  final Color onQuill;

  final Color success;
  final Color info;
  final Color danger;

  const BrandPalette({
    required this.ink,
    required this.inkSoft,
    required this.paper,
    required this.surface,
    required this.surfaceTint,
    required this.line,
    required this.fin,
    required this.onFin,
    required this.deep,
    required this.onDeep,
    required this.onDeepSoft,
    required this.quill,
    required this.onQuill,
    required this.success,
    required this.info,
    required this.danger,
  });

  static const light = BrandPalette(
    ink: Color(0xFF12212E),
    inkSoft: Color(0xFF4C5C69),
    paper: Color(0xFFF7F6F2),
    surface: Color(0xFFFFFFFF),
    surfaceTint: Color(0xFFEEF3F2),
    line: Color(0xFFDCE3E4),
    fin: Color(0xFF0F8A7E),
    onFin: Color(0xFFFFFFFF),
    deep: Color(0xFF0E3B4F),
    onDeep: Color(0xFFFFFFFF),
    onDeepSoft: Color(0xFFB9D3DC),
    quill: Color(0xFFF2B33D),
    onQuill: Color(0xFF2A1D00),
    success: Color(0xFF2F9E5C),
    info: Color(0xFF3B78C4),
    danger: Color(0xFFC2412D),
  );

  static const dark = BrandPalette(
    ink: Color(0xFFE8EEF2),
    inkSoft: Color(0xFFA9B6C0),
    paper: Color(0xFF0D1821),
    surface: Color(0xFF15232F),
    surfaceTint: Color(0xFF1C2E3B),
    line: Color(0xFF2A3D4B),
    fin: Color(0xFF3CC3B3),
    onFin: Color(0xFF00201C),
    deep: Color(0xFF123447),
    onDeep: Color(0xFFE8EEF2),
    onDeepSoft: Color(0xFF9EC3D0),
    quill: Color(0xFFF5C561),
    onQuill: Color(0xFF2A1D00),
    success: Color(0xFF6DD69A),
    info: Color(0xFF8AB8F0),
    danger: Color(0xFFFF8A73),
  );
}

/// The palette as a theme extension, so widgets get the right one for the
/// current brightness.
class BrandColors extends ThemeExtension<BrandColors> {
  final BrandPalette palette;
  const BrandColors(this.palette);

  @override
  BrandColors copyWith({BrandPalette? palette}) => BrandColors(palette ?? this.palette);

  // Palettes swap at the midpoint of a theme animation rather than
  // blending: every token is a deliberate pair, not a gradient.
  @override
  BrandColors lerp(BrandColors? other, double t) => t < 0.5 || other == null ? this : other;
}

extension BrandContext on BuildContext {
  /// The current palette. Falls back to the one matching the theme's
  /// brightness when the theme wasn't built by `buildAppTheme` (a bare
  /// `MaterialApp`, as in widget tests).
  BrandPalette get brand {
    final theme = Theme.of(this);
    return theme.extension<BrandColors>()?.palette ??
        (theme.brightness == Brightness.dark ? BrandPalette.dark : BrandPalette.light);
  }
}
