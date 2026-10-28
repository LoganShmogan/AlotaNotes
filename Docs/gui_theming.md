# Visual Theming

QuillFin's real logo, colours and fonts are still to come. Until then a
placeholder identity lives in **one token file**,
`lib/theme/brand.dart`, so the real brand is a token swap. Everything else
reads colours through `context.brand`, so light and dark mode both follow
from that file.

- `lib/theme/brand.dart`: the name, fonts, radii and the light and dark
  `BrandPalette`s (exposed as the `BrandColors` theme extension).
- `lib/theme/theme.dart`: builds the light and dark `ThemeData` from the
  palette.
- `lib/theme/widgets.dart`: shared branded widgets.
- `lib/layout/breakpoints.dart`: window size classes and the layout helpers
  (see the per-screen layouts in `quillfin_plan.md` section 5).

## Palette (placeholder)

| Token | Light | Dark | Use |
|---|---|---|---|
| `ink` | `#12212E` | `#E8EEF2` | text |
| `inkSoft` | `#4C5C69` | `#A9B6C0` | secondary text, icons |
| `paper` | `#F7F6F2` | `#0D1821` | page background |
| `surface` | `#FFFFFF` | `#15232F` | cards, sheets, inputs |
| `surfaceTint` | `#EEF3F2` | `#1C2E3B` | quiet fills, selection |
| `line` | `#DCE3E4` | `#2A3D4B` | hairline borders |
| `fin` | `#0F8A7E` | `#3CC3B3` | primary: buttons, links, selection |
| `deep` | `#0E3B4F` | `#123447` | hero panels, sign-in brand panel |
| `quill` | `#F2B33D` | `#F5C561` | highlight: "due", the key call to action |
| `success` / `info` / `danger` | `#2F9E5C` / `#3B78C4` / `#C2412D` | `#6DD69A` / `#8AB8F0` / `#FF8A73` | status |

If a theme wasn't built by `buildAppTheme` (a bare `MaterialApp` in a
widget test), `context.brand` falls back to the palette matching the
theme's brightness.

## Type and shape

- **Outfit** (Medium, SemiBold, Bold) for headings, numbers, buttons and
  labels; **Inter** (Regular to Bold) for body text. Both are SIL OFL and
  bundled in `assets/fonts/`, so nothing is fetched at runtime.
- Problem solutions use the platform `monospace` font.
- Shape: 14 px card radius, 12 px controls, 1 px hairline borders, no
  heavy shadows.

## Mark

`QuillFinMark` draws the placeholder mark (a quill nib whose feather sweeps
into a fin) in code. The same geometry is in
`assets/brand/quillfin-mark.svg`, and `assets/brand/quillfin-app-icon.svg`
is a placeholder app icon. `BrandLockup` is the mark plus the wordmark, with
an optional "by Save Point".

## Widgets in `widgets.dart`

- `BrandCard`, with an optional leading accent bar used to flag due items.
- `PrimaryButton`, with a `highlight` variant in gold.
- `Pill`, `tintedPill()`, `DifficultyPill` and `StatusPill`.
- `StatTile`, `SectionLabel`, `EmptyState` and `RetentionMeter`.
- `QuillFinMark` and `BrandLockup`.

## Light and dark

The theme follows the system, with an override in Settings > Appearance
(`ThemeController`, saved as `AppSettings.themeMode`).
