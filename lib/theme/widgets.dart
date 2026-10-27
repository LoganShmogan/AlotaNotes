/// Small branded building blocks the theme alone can't express: hard
/// offset "pixel" shadows, the pressed-in button effect from
/// savepoint.co.nz, badges, stat tiles and empty states.
library;

import 'package:flutter/material.dart';

import '../core/models.dart';
import 'theme.dart';

/// A white panel with an ink border and a solid offset shadow.
class PixelCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color color;
  final Color shadowColor;
  final VoidCallback? onTap;

  const PixelCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.color = colorPaperRaised,
    this.shadowColor = colorPurple,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final content = Padding(padding: padding, child: child);
    return Container(
      margin: const EdgeInsets.only(right: 6, bottom: 6),
      decoration: BoxDecoration(
        color: color,
        border: Border.all(color: colorInk, width: borderWidth),
        boxShadow: pixelShadow(color: shadowColor),
      ),
      // Its own Material, so ink from tiles/buttons inside paints above the
      // decoration instead of behind it.
      child: Material(
        type: MaterialType.transparency,
        child: onTap == null ? content : InkWell(onTap: onTap, child: content),
      ),
    );
  }
}

/// The site's primary call to action: a yellow button with a 4px ink shadow
/// that presses in (shadow shrinks, button shifts) while held.
class PixelButton extends StatefulWidget {
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;

  const PixelButton({super.key, required this.label, required this.onPressed, this.icon});

  @override
  State<PixelButton> createState() => _PixelButtonState();
}

class _PixelButtonState extends State<PixelButton> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (_pressed != value) setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null;
    final offset = !enabled ? 0.0 : (_pressed ? 2.0 : 4.0);
    final child = widget.icon == null
        ? Text(widget.label)
        : Row(mainAxisSize: MainAxisSize.min, children: [Icon(widget.icon), const SizedBox(width: 10), Text(widget.label)]);
    return Listener(
      onPointerDown: (_) => _setPressed(true),
      onPointerUp: (_) => _setPressed(false),
      onPointerCancel: (_) => _setPressed(false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 100),
        margin: const EdgeInsets.only(right: 4, bottom: 4),
        transform: Matrix4.translationValues(4 - offset, 4 - offset, 0),
        decoration: BoxDecoration(boxShadow: offset == 0 ? null : pixelShadow(color: colorInk, offset: offset)),
        child: ElevatedButton(onPressed: widget.onPressed, child: child),
      ),
    );
  }
}

/// A small square label: difficulty, status, tag.
class Pill extends StatelessWidget {
  final String label;
  final Color color;
  final Color textColor;
  const Pill(this.label, {super.key, this.color = colorPaperTint, this.textColor = colorInk});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(color: color, border: Border.all(color: colorInk, width: 2)),
      child: Text(
        label,
        style: TextStyle(fontFamily: fontDisplay, fontSize: 12, fontWeight: FontWeight.w700, color: textColor, height: 1.3),
      ),
    );
  }
}

class DifficultyPill extends StatelessWidget {
  final String difficulty;
  const DifficultyPill(this.difficulty, {super.key});

  @override
  Widget build(BuildContext context) {
    return switch (difficulty) {
      problemDifficultyEasy => const Pill('Easy', color: colorGreen),
      problemDifficultyHard => const Pill('Hard', color: colorPurpleDeep, textColor: colorOnPlum),
      _ => const Pill('Medium', color: colorYellow),
    };
  }
}

class StatusPill extends StatelessWidget {
  final ProblemStatus status;
  const StatusPill(this.status, {super.key});

  @override
  Widget build(BuildContext context) {
    return switch (status) {
      ProblemStatus.todo => const Pill('To do'),
      ProblemStatus.attempted => const Pill('Attempted', color: colorBlue),
      ProblemStatus.solved => const Pill('Solved', color: colorGreen),
    };
  }
}

/// A headline number with a label under it, for the Today dashboard.
class StatTile extends StatelessWidget {
  final String label;
  final String value;
  final Color accent;
  const StatTile({super.key, required this.label, required this.value, this.accent = colorPurple});

  @override
  Widget build(BuildContext context) {
    return PixelCard(
      shadowColor: accent,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value, style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 2),
          Text(label, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}

/// Uppercase section label, like the site's eyebrow text.
class SectionLabel extends StatelessWidget {
  final String text;
  const SectionLabel(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 20, 4, 8),
      child: Text(
        text.toUpperCase(),
        style: const TextStyle(
          fontFamily: fontDisplay,
          fontSize: 13,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.2,
          color: colorPurpleDeep,
        ),
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
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: colorPaperTint,
                border: Border.all(color: colorInk, width: borderWidth),
                boxShadow: pixelShadow(offset: 4),
              ),
              child: Icon(icon, size: 32, color: colorPurpleDeep),
            ),
            const SizedBox(height: 18),
            Text(message, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyLarge),
            if (action != null) ...[const SizedBox(height: 18), action!],
          ],
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
    final color = value >= 0.85 ? colorGreen : (value >= 0.7 ? colorYellow : colorPurple);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 48,
          height: 10,
          decoration: BoxDecoration(color: colorPaperTint, border: Border.all(color: colorInk, width: 1.5)),
          alignment: Alignment.centerLeft,
          child: FractionallySizedBox(widthFactor: value.clamp(0, 1), child: Container(color: color)),
        ),
        const SizedBox(width: 6),
        Text('${(value * 100).round()}%', style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}
