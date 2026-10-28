import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quillfin/core/models.dart';
import 'package:quillfin/theme/theme.dart';
import 'package:quillfin/theme/widgets.dart';

void main() {
  Future<void> pump(WidgetTester tester, Widget child, {Brightness brightness = Brightness.light}) => tester.pumpWidget(
        MaterialApp(theme: buildAppTheme(brightness: brightness), home: Scaffold(body: Center(child: child))),
      );

  group('theme', () {
    test('light and dark themes carry their own palette', () {
      expect(buildAppTheme().extension<BrandColors>()!.palette, same(BrandPalette.light));
      final dark = buildAppTheme(brightness: Brightness.dark);
      expect(dark.extension<BrandColors>()!.palette, same(BrandPalette.dark));
      expect(dark.colorScheme.primary, BrandPalette.dark.fin);
      expect(dark.scaffoldBackgroundColor, BrandPalette.dark.paper);
    });

    test('BrandColors swaps palettes halfway through a theme animation', () {
      const light = BrandColors(BrandPalette.light);
      const dark = BrandColors(BrandPalette.dark);
      expect(light.lerp(dark, 0.4), same(light));
      expect(light.lerp(dark, 0.6), same(dark));
      expect(light.lerp(null, 0.9), same(light));
      expect(light.copyWith(palette: BrandPalette.dark).palette, same(BrandPalette.dark));
      expect(light.copyWith().palette, same(BrandPalette.light));
    });

    testWidgets('context.brand follows the theme, falling back by brightness', (tester) async {
      late BrandPalette seen;
      Widget probe() => Builder(builder: (context) {
            seen = context.brand;
            return const SizedBox();
          });
      await tester.pumpWidget(MaterialApp(theme: buildAppTheme(brightness: Brightness.dark), home: probe()));
      expect(seen.paper, BrandPalette.dark.paper);
      await tester.pumpWidget(MaterialApp(theme: ThemeData(brightness: Brightness.dark), home: probe()));
      await tester.pumpAndSettle();
      expect(seen.paper, BrandPalette.dark.paper);
      await tester.pumpWidget(MaterialApp(home: probe()));
      await tester.pumpAndSettle(); // MaterialApp animates between themes
      expect(seen.paper, BrandPalette.light.paper);
    });

    testWidgets('switch and checkbox colours follow selection', (tester) async {
      final theme = buildAppTheme();
      final selected = {WidgetState.selected};
      expect(theme.switchTheme.thumbColor!.resolve(selected), BrandPalette.light.onFin);
      expect(theme.switchTheme.thumbColor!.resolve({}), BrandPalette.light.inkSoft);
      expect(theme.switchTheme.trackColor!.resolve(selected), BrandPalette.light.fin);
      expect(theme.switchTheme.trackColor!.resolve({}), BrandPalette.light.surfaceTint);
      expect(theme.switchTheme.trackOutlineColor!.resolve(selected), BrandPalette.light.fin);
      expect(theme.switchTheme.trackOutlineColor!.resolve({}), BrandPalette.light.line);
      expect(theme.checkboxTheme.fillColor!.resolve(selected), BrandPalette.light.fin);
      expect(theme.checkboxTheme.fillColor!.resolve({}), isNull);
      expect(theme.navigationBarTheme.iconTheme!.resolve(selected)!.color, BrandPalette.light.fin);
      expect(theme.navigationBarTheme.labelTextStyle!.resolve({})!.color, BrandPalette.light.inkSoft);
    });
  });

  group('PrimaryButton', () {
    testWidgets('plain, with an icon, and highlighted', (tester) async {
      var taps = 0;
      await pump(tester, PrimaryButton(label: 'Go', onPressed: () => taps++));
      await tester.tap(find.text('Go'));
      expect(taps, 1);

      await pump(tester, PrimaryButton(label: 'Start', icon: Icons.play_arrow, highlight: true, onPressed: () {}));
      expect(find.byIcon(Icons.play_arrow), findsOneWidget);
      final button = tester.widget<ButtonStyleButton>(find.byWidgetPredicate((w) => w is ButtonStyleButton));
      expect(button.style!.backgroundColor!.resolve({}), BrandPalette.light.quill);
    });
  });

  group('BrandCard', () {
    testWidgets('is tappable when given onTap, and can carry an accent bar', (tester) async {
      var taps = 0;
      await pump(tester, BrandCard(onTap: () => taps++, accent: Colors.amber, child: const Text('card')));
      await tester.tap(find.text('card'));
      expect(taps, 1);
      expect(find.byWidgetPredicate((w) => w is Container && w.color == Colors.amber), findsOneWidget);
    });

    testWidgets('a coloured card has no border', (tester) async {
      await pump(tester, const BrandCard(color: Colors.teal, child: Text('x')));
      final material = tester.widget<Material>(find.descendant(of: find.byType(BrandCard), matching: find.byType(Material)));
      expect((material.shape! as RoundedRectangleBorder).side.color, Colors.transparent);
    });
  });

  testWidgets('pills label difficulty and status, in both themes', (tester) async {
    for (final brightness in Brightness.values) {
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
        brightness: brightness,
      );
      for (final label in ['Easy', 'Medium', 'Hard', 'To do', 'Attempted', 'Solved']) {
        expect(find.text(label), findsOneWidget, reason: '$label ($brightness)');
      }
    }
  });

  testWidgets('RetentionMeter shows a percentage, coloured by how safe it is', (tester) async {
    Color fill() {
      final bar = tester.widget<FractionallySizedBox>(find.byType(FractionallySizedBox)).child! as Container;
      return bar.color!;
    }

    await pump(tester, const RetentionMeter(0.92));
    expect(find.text('92%'), findsOneWidget);
    expect(fill(), BrandPalette.light.success);
    await pump(tester, const RetentionMeter(0.75));
    expect(fill(), BrandPalette.light.quill);
    await pump(tester, const RetentionMeter(0.4));
    expect(fill(), BrandPalette.light.danger);
  });

  testWidgets('EmptyState, SectionLabel and StatTile render their content', (tester) async {
    await pump(
      tester,
      Column(children: [
        EmptyState(icon: Icons.inbox, message: 'Nothing', action: TextButton(onPressed: () {}, child: const Text('Add'))),
        const SectionLabel('Section', trailing: Text('more')),
        const SizedBox(width: 200, child: StatTile(label: 'Due', value: '3', icon: Icons.quiz)),
      ]),
    );
    for (final text in ['Nothing', 'Add', 'Section', 'more', 'Due', '3']) {
      expect(find.text(text), findsOneWidget, reason: text);
    }
  });

  testWidgets('the QuillFin mark and lockup', (tester) async {
    await pump(tester, const Column(children: [QuillFinMark(size: 48), BrandLockup(showOwner: true)]));
    expect(find.text(brandName), findsOneWidget);
    expect(find.text('by $brandOwner'), findsOneWidget);
    final painter = tester.widget<CustomPaint>(find.descendant(of: find.byType(QuillFinMark).first, matching: find.byType(CustomPaint))).painter! as MarkPainter;
    expect(painter.color, BrandPalette.light.fin);
    expect(painter.shouldRepaint(MarkPainter(BrandPalette.light.fin)), isFalse);
    expect(painter.shouldRepaint(MarkPainter(Colors.red)), isTrue);
  });
}
