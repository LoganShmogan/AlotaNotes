# Visual Theming

`lib/theme/theme.dart` is the single source of truth for the app's look;
`lib/theme/widgets.dart` holds the few branded building blocks a
`ThemeData` can't express. Screens use the named constants and widgets,
never raw hex codes.

## Source

The tokens are taken directly from the live savepoint.co.nz stylesheet
(its CSS custom properties, fetched in October 2026), not guessed. The site
is a light, "neo-brutalist" retro design:

| Constant | Hex | Site token | Used for |
|---|---|---|---|
| `colorPaper` | `#F7F4EF` | `--paper` | Page background |
| `colorPaperRaised` | `#FFFFFF` | `--paper-raised` | Cards, inputs |
| `colorPaperTint` | `#EFE8F2` | `--paper-tint` | Quiet fills, tracks, dividers |
| `colorInk` | `#221C27` | `--ink` | Text, 3px borders, button shadows |
| `colorInkSoft` | `#4A4352` | `--ink-soft` | Secondary text |
| `colorPlum` | `#2B2233` | `--plum` | App bar, nav bar, hero panels |
| `colorOnPlumSoft` | `#E4DCEA` | `--on-plum-soft` | Secondary text on plum |
| `colorPurple` | `#B791C2` | `--purple` | Pixel shadows, app-bar underline |
| `colorPurpleDeep` | `#5B3D6B` | `--purple-deep` | Primary accent, links, labels |
| `colorYellow` | `#EECC67` | `--yellow` | Primary buttons, selection, "due" |
| `colorBlue` | `#699FD5` | `--blue` | "Attempted", problem stats |
| `colorGreen` | `#82C88A` | `--green` | "Solved", easy, correct answers |
| `colorDanger` | `#B3261E` | (none) | Errors, wrong answers |

`colorDanger` is the only colour not on the site, which never shows an
error state.

## Shape and depth

- Square corners everywhere, with 3px ink borders (`inkBorder`).
- No blurred elevation. Depth is a solid offset "pixel shadow"
  (`pixelShadow()`, the site's `--pixel-shadow: 6px 6px 0 var(--purple)`).
- The app bar is plum with a 4px purple underline and the nav bar is plum
  with a yellow selected tab, like the site's header.
- Primary actions use `PixelButton`: yellow, ink border, 4px ink shadow,
  pressing in to 2px while held (the site's `button:hover` effect).
- `PixelCard` is a white panel with an ink border and an offset shadow. It
  wraps its content in a transparent `Material` so ink from tiles inside
  paints correctly. The shadow colour carries meaning: a yellow shadow on a
  tracker card means it's due.

## Fonts

Bundled in `assets/fonts/` (SIL OFL, licences alongside), so text never
depends on a network fetch:

- **Chakra Petch** (SemiBold, Bold): headings, app-bar titles, buttons,
  chips, pills and section labels (`fontDisplay`).
- **Figtree** (Regular, Medium, SemiBold, Bold): body text (`fontBody`, the
  theme default).

Code (problem solutions) uses the platform `monospace` family.

## Widgets in `widgets.dart`

`PixelCard`, `PixelButton`, `Pill`, `DifficultyPill`, `StatusPill`,
`StatTile`, `SectionLabel` (uppercase eyebrow text), `EmptyState`,
`RetentionMeter`.

## Adding a style

Add it to `buildAppTheme()` using the constants above, or add a small
widget to `widgets.dart` if it needs pixel shadows. Don't hardcode hex
codes in screens. There is no dark mode, matching the site.
