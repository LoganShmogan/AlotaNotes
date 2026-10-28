/// Window size classes and the layout helpers built on them. The same
/// breakpoints are used by the web app; Docs/quillfin_plan.md section 5 has
/// the per-screen layout for each class.
library;

import 'package:flutter/material.dart';

/// Material 3 window size classes, by logical width.
enum WindowSize {
  /// < 600: phones in portrait.
  compact,

  /// 600-839: foldables, small tablets in portrait, phones in landscape.
  medium,

  /// 840-1199: tablets in landscape, small laptop windows.
  expanded,

  /// 1200-1599: laptops and desktops.
  large,

  /// >= 1600: large monitors.
  extraLarge;

  bool operator >=(WindowSize other) => index >= other.index;
  bool operator <(WindowSize other) => index < other.index;

  static WindowSize forWidth(double width) {
    if (width < 600) return compact;
    if (width < 840) return medium;
    if (width < 1200) return expanded;
    if (width < 1600) return large;
    return extraLarge;
  }

  /// Horizontal page padding.
  double get gutter => switch (this) {
        compact => 16,
        medium || expanded => 24,
        large || extraLarge => 32,
      };
}

/// Below this height (a phone in landscape) bottom bars and bottom sheets
/// give way to side navigation and side panels.
const shortHeight = 480.0;

/// Comfortable line length for reading and focused flows (quiz, editor).
const maxReadingWidth = 640.0;

/// Widest a page's content grows before it's centred.
const maxContentWidth = 1120.0;
const maxContentWidthXL = 1440.0;

/// List column width in list-detail layouts.
const listPaneWidth = 360.0;
const listPaneWidthLarge = 400.0;

extension WindowSizeContext on BuildContext {
  WindowSize get windowSize => WindowSize.forWidth(MediaQuery.sizeOf(this).width);

  bool get isShortHeight => MediaQuery.sizeOf(this).height < shortHeight;

  /// True when list and detail are shown side by side.
  bool get showsTwoPanes => windowSize >= WindowSize.expanded;
}

/// Horizontal padding that centres content of at most [maxWidth] inside
/// [available], never less than [gutter]. For scrolling lists, where
/// padding (unlike [ContentWidth]) keeps the scrollbar at the edge.
double centeredInset(double available, double gutter, {double maxWidth = maxReadingWidth}) =>
    available - 2 * gutter > maxWidth ? (available - maxWidth) / 2 : gutter;

/// Centres [child] and caps its width, so wide windows don't stretch text
/// and forms edge to edge.
class ContentWidth extends StatelessWidget {
  final Widget child;
  final double maxWidth;
  const ContentWidth({super.key, required this.child, this.maxWidth = maxContentWidth});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(constraints: BoxConstraints(maxWidth: maxWidth), child: child),
    );
  }
}

/// Side-by-side list and detail on expanded windows and wider; just the
/// list otherwise (the screen pushes the detail as a page instead).
class ListDetail extends StatelessWidget {
  final Widget list;

  /// The selected item's detail, or null for [emptyDetail].
  final Widget? detail;
  final Widget emptyDetail;

  const ListDetail({super.key, required this.list, required this.detail, required this.emptyDetail});

  @override
  Widget build(BuildContext context) {
    if (!context.showsTwoPanes) return list;
    final size = context.windowSize;
    final divider = Theme.of(context).dividerTheme.color;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(width: size >= WindowSize.large ? listPaneWidthLarge : listPaneWidth, child: list),
        VerticalDivider(width: 1, color: divider),
        Expanded(child: detail ?? emptyDetail),
      ],
    );
  }
}
