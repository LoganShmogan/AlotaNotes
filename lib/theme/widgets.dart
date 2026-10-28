/// Small branded building blocks shared across screens: cards, the primary
/// button, badges, stat tiles, empty states, the recall meter and the
/// QuillFin mark. Colours always come from `context.brand`, so every
/// widget works in light and dark mode.
library;

import 'package:flutter/material.dart';

import '../core/models.dart';
import 'brand.dart';

/// A surface panel with a hairline border. [accent] draws a coloured bar
/// down the leading edge (used to flag "due" items).
class BrandCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? color;
  final Color? accent;
  final VoidCallback? onTap;

  const BrandCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.color,
    this.accent,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    Widget content = Padding(padding: padding, child: child);
    if (accent != null) {
      content = IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [Container(width: 4, color: accent), Expanded(child: content)],
        ),
      );
    }
    return Material(
      color: color ?? b.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radiusCard),
        side: BorderSide(color: color == null ? b.line : Colors.transparent),
      ),
      clipBehavior: Clip.antiAlias,
      child: onTap == null ? content : InkWell(onTap: onTap, child: content),
    );
  }
}

/// The main call to action on a screen: a filled fin-coloured button,
/// optionally with a leading icon.
class PrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;

  /// Gold instead of fin, for the single most important action on a dark
  /// hero panel (start quiz, upgrade).
  final bool highlight;

  const PrimaryButton({super.key, required this.label, required this.onPressed, this.icon, this.highlight = false});

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    final style = highlight ? FilledButton.styleFrom(backgroundColor: b.quill, foregroundColor: b.onQuill) : null;
    return icon == null
        ? FilledButton(onPressed: onPressed, style: style, child: Text(label))
        : FilledButton.icon(onPressed: onPressed, style: style, icon: Icon(icon), label: Text(label));
  }
}

/// A small rounded label: difficulty, status, tag.
class Pill extends StatelessWidget {
  final String label;
  final Color? color;
  final Color? textColor;
  const Pill(this.label, {super.key, this.color, this.textColor});

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(color: color ?? b.surfaceTint, borderRadius: BorderRadius.circular(radiusPill)),
      child: Text(
        label,
        style: TextStyle(
          fontFamily: fontDisplay,
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: textColor ?? b.ink,
          height: 1.3,
        ),
      ),
    );
  }
}

/// A [Pill] tinted from [base]: a light wash of the colour, with text mixed
/// towards ink so it stays readable in both themes.
Pill tintedPill(BuildContext context, String label, Color base) =>
    Pill(label, color: base.withValues(alpha: 0.16), textColor: Color.lerp(base, context.brand.ink, 0.3));

class DifficultyPill extends StatelessWidget {
  final String difficulty;
  const DifficultyPill(this.difficulty, {super.key});

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    return switch (difficulty) {
      problemDifficultyEasy => tintedPill(context, 'Easy', b.success),
      problemDifficultyHard => tintedPill(context, 'Hard', b.danger),
      _ => tintedPill(context, 'Medium', b.quill),
    };
  }
}

class StatusPill extends StatelessWidget {
  final ProblemStatus status;
  const StatusPill(this.status, {super.key});

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    return switch (status) {
      ProblemStatus.todo => const Pill('To do'),
      ProblemStatus.attempted => tintedPill(context, 'Attempted', b.info),
      ProblemStatus.solved => tintedPill(context, 'Solved', b.success),
    };
  }
}

/// A headline number with an icon and a label, for the Today dashboard.
class StatTile extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color? accent;
  const StatTile({super.key, required this.label, required this.value, required this.icon, this.accent});

  @override
  Widget build(BuildContext context) {
    return BrandCard(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: accent ?? context.brand.fin),
          const SizedBox(height: 8),
          Text(value, style: Theme.of(context).textTheme.headlineSmall),
          Text(label, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}

/// Small heading above a group of content, with an optional trailing
/// action.
class SectionLabel extends StatelessWidget {
  final String text;
  final Widget? trailing;
  const SectionLabel(this.text, {super.key, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 22, 2, 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontFamily: fontDisplay,
                fontSize: 14,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.2,
                color: context.brand.inkSoft,
              ),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  final IconData icon;
  final String message;
  final Widget? action;
  const EmptyState({super.key, required this.icon, required this.message, this.action});

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: b.surfaceTint, shape: BoxShape.circle),
                child: Icon(icon, size: 30, color: b.fin),
              ),
              const SizedBox(height: 18),
              Text(message, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyLarge),
              if (action != null) ...[const SizedBox(height: 18), action!],
            ],
          ),
        ),
      ),
    );
  }
}

/// How likely you are to remember something right now (0-1), as a short
/// bar plus a percentage.
class RetentionMeter extends StatelessWidget {
  final double value;
  const RetentionMeter(this.value, {super.key});

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    final color = value >= 0.85 ? b.success : (value >= 0.7 ? b.quill : b.danger);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(radiusPill),
          child: Container(
            width: 48,
            height: 6,
            color: b.surfaceTint,
            alignment: Alignment.centerLeft,
            child: FractionallySizedBox(widthFactor: value.clamp(0, 1), child: Container(color: color)),
          ),
        ),
        const SizedBox(width: 6),
        Text('${(value * 100).round()}%', style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}

/// The placeholder QuillFin mark: a quill nib whose feather sweeps into a
/// fin. Drawn in code (same geometry as assets/brand/quillfin-mark.svg) so
/// it stays crisp at any size without an SVG dependency.
class QuillFinMark extends StatelessWidget {
  final double size;
  final Color? color;
  const QuillFinMark({super.key, this.size = 32, this.color});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(size: Size.square(size), painter: MarkPainter(color ?? context.brand.fin));
  }
}

@visibleForTesting
class MarkPainter extends CustomPainter {
  final Color color;
  MarkPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    // Designed on a 64-unit grid.
    canvas.scale(size.width / 64, size.height / 64);
    final feather = Path()
      ..moveTo(12, 54)
      ..cubicTo(12, 32, 28, 12, 54, 8)
      ..cubicTo(52, 22, 46, 32, 36, 38)
      ..lineTo(42, 40)
      ..cubicTo(34, 48, 24, 52, 12, 54)
      ..close();
    canvas.drawPath(feather, Paint()..color = color);
    // The shaft: a cut from the nib up into the feather.
    final shaft = Paint()
      ..color = color
      ..strokeWidth = 3.2
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    canvas.drawLine(const Offset(8, 58), const Offset(30, 36), shaft);
  }

  @override
  bool shouldRepaint(MarkPainter oldDelegate) => oldDelegate.color != color;
}

/// Mark plus wordmark, for headers, the sidebar and the sign-in screen.
class BrandLockup extends StatelessWidget {
  final double size;
  final bool showOwner;
  final Color? color;
  const BrandLockup({super.key, this.size = 28, this.showOwner = false, this.color});

  @override
  Widget build(BuildContext context) {
    final b = context.brand;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        QuillFinMark(size: size * 1.1, color: color),
        SizedBox(width: size * 0.35),
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              brandName,
              style: TextStyle(
                fontFamily: fontDisplay,
                fontSize: size,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.4,
                color: color ?? b.ink,
                height: 1.05,
              ),
            ),
            if (showOwner)
              Text('by $brandOwner', style: TextStyle(fontSize: size * 0.42, color: color ?? b.inkSoft, height: 1.3)),
          ],
        ),
      ],
    );
  }
}
