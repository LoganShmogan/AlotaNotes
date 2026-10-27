import 'package:flutter/material.dart';

import '../../core/models.dart';
import '../../core/scheduling.dart';
import '../../theme/theme.dart';

/// The four FSRS grades as a row of buttons, each labelled with when that
/// grade would bring the item back ("Good · 3d"). [highlighted] (the
/// suggested or currently chosen grade) is drawn filled.
class RatingButtons extends StatelessWidget {
  final Map<ReviewRating, DateTime> previews;
  final DateTime now;
  final ReviewRating? highlighted;
  final ValueChanged<ReviewRating>? onSelected;

  const RatingButtons({
    super.key,
    required this.previews,
    required this.now,
    required this.onSelected,
    this.highlighted,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (final rating in ReviewRating.values) ...[
          if (rating != ReviewRating.again) const SizedBox(width: 8),
          Expanded(child: _button(context, rating)),
        ],
      ],
    );
  }

  Widget _button(BuildContext context, ReviewRating rating) {
    final selected = rating == highlighted;
    final interval = formatInterval(previews[rating]!.difference(now));
    final style = OutlinedButton.styleFrom(
      backgroundColor: selected ? colorYellow : colorPaperRaised,
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
      minimumSize: const Size(0, 58),
    );
    return Container(
      decoration: BoxDecoration(boxShadow: selected ? pixelShadow(color: colorInk, offset: 3) : null),
      child: OutlinedButton(
        key: ValueKey('rating-${rating.name}'),
        style: style,
        onPressed: onSelected == null ? null : () => onSelected!(rating),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(rating.label),
            Text(interval, style: const TextStyle(fontFamily: fontBody, fontSize: 12, fontWeight: FontWeight.w500)),
          ],
        ),
      ),
    );
  }
}
