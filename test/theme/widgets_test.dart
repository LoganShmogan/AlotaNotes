import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quizapp/core/models.dart';
import 'package:quizapp/theme/theme.dart';
import 'package:quizapp/theme/widgets.dart';

void main() {
  Future<void> pump(WidgetTester tester, Widget child) =>
      tester.pumpWidget(MaterialApp(theme: buildAppTheme(), home: Scaffold(body: Center(child: child))));

  group('PixelButton', () {
    double? shadowOffset(WidgetTester tester) {
      final decoration = tester.widget<AnimatedContainer>(find.byType(AnimatedContainer)).decoration as BoxDecoration;
      return decoration.boxShadow?.single.offset.dx;
    }

    testWidgets('presses in while held and springs back on release or cancel', (tester) async {
      var taps = 0;
      await pump(tester, PixelButton(label: 'Go', icon: Icons.play_arrow, onPressed: () => taps++));
      expect(find.byIcon(Icons.play_arrow), findsOneWidget);
      expect(shadowOffset(tester), 4);

      final gesture = await tester.startGesture(tester.getCenter(find.text('Go')));
      await tester.pump();
      expect(shadowOffset(tester), 2);
      await gesture.up();
      await tester.pump();
      expect((shadowOffset(tester), taps), (4, 1));

      final cancelled = await tester.startGesture(tester.getCenter(find.text('Go')));
      await tester.pump();
      await cancelled.cancel();
      await tester.pump();
      expect((shadowOffset(tester), taps), (4, 1));
    });

    testWidgets('disabled: no shadow', (tester) async {
      await pump(tester, const PixelButton(label: 'Nope', onPressed: null));
      expect(shadowOffset(tester), isNull);
    });
  });

  testWidgets('PixelCard is tappable when given onTap', (tester) async {
    var taps = 0;
    await pump(tester, PixelCard(onTap: () => taps++, child: const Text('card')));
    await tester.tap(find.text('card'));
    expect(taps, 1);
  });

  testWidgets('pills label difficulty and status', (tester) async {
    await pump(
      tester,
      const Column(children: [
        DifficultyPill(problemDifficultyEasy),
        DifficultyPill(problemDifficultyMedium),
        DifficultyPill(problemDifficultyHard),
        StatusPill(ProblemStatus.todo),
        StatusPill(ProblemStatus.attempted),
        StatusPill(ProblemStatus.solved),
      ]),
    );
    for (final label in ['Easy', 'Medium', 'Hard', 'To do', 'Attempted', 'Solved']) {
      expect(find.text(label), findsOneWidget, reason: label);
    }
  });

  testWidgets('RetentionMeter shows a percentage, coloured by how safe it is', (tester) async {
    Color fill(double value) {
      final bar = tester.widget<FractionallySizedBox>(find.byType(FractionallySizedBox)).child! as Container;
      return bar.color!;
    }

    await pump(tester, const RetentionMeter(0.92));
    expect(find.text('92%'), findsOneWidget);
    expect(fill(0.92), colorGreen);
    await pump(tester, const RetentionMeter(0.75));
    expect(fill(0.75), colorYellow);
    await pump(tester, const RetentionMeter(0.4));
    expect(fill(0.4), colorPurple);
  });

  testWidgets('EmptyState shows its action', (tester) async {
    await pump(tester, EmptyState(icon: Icons.inbox, message: 'Nothing', action: TextButton(onPressed: () {}, child: const Text('Add'))));
    expect(find.text('Nothing'), findsOneWidget);
    expect(find.text('Add'), findsOneWidget);
  });
}
