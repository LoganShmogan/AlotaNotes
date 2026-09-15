# Visual Theming

`lib/theme/theme.dart` is the single source of truth for the app's visual
design; screens reference named color constants from here rather than
hardcoding hex codes, so a future palette tweak touches one file.

## Palette

Ported directly from the earlier Python desktop app's palette, which itself
claims to match the savepoint.cc brand:

| Constant | Hex | Usage |
|---|---|---|
| `colorPurple` | `#B791C2` | Primary accent, card fills, buttons |
| `colorYellow` | `#EECC67` | Highlight/emphasis (errors, secondary state) |
| `colorBlue` | `#699FD5` | Secondary accent |
| `colorGreen` | `#82C889` | Success, selected-tab indicator |
| `colorBlack` | `#000000` | Main background |
| `colorWhite` | `#FFFFFF` | Text, borders |

**Not yet verified against the real savepoint.cc site.** A text-only fetch
during planning confirmed a retro/pixel-art aesthetic consistent in spirit
with this palette, but couldn't extract real hex codes or fonts from it.
Treat this palette as a reasonable starting point carried over from the
Python app, not a confirmed brand match. See `future_work.md`.

## Aesthetic

Dark, flat, thick borders, zero corner radius: built via `ThemeData` with
`useMaterial3: true`, `brightness: Brightness.dark`, and explicit
`CardThemeData`/`ElevatedButtonThemeData`/`InputDecorationTheme` overrides
using `RoundedRectangleBorder(borderRadius: BorderRadius.zero, side:
BorderSide(color: colorWhite, width: borderWidth))` wherever a card or button
would otherwise get rounded corners and a colored fill by default.

## Fonts

No custom font bundling yet. The app currently uses Flutter's default
Material font stack. The Python desktop app bundles Chakra Petch (headings)
and Figtree (body) with per-OS registration logic; that hasn't been ported,
partly because it depends on the same unverified brand-asset question above.
See `future_work.md`.

## Adding a new named style

Add the style to `buildAppTheme()` in `theme.dart`, referencing the palette
constants above. Don't hardcode hex codes in screen files.
