import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quillfin/layout/breakpoints.dart';

void main() {
  group('WindowSize.forWidth', () {
    for (final (width, size) in [
      (360.0, WindowSize.compact),
      (599.0, WindowSize.compact),
      (600.0, WindowSize.medium),
      (839.0, WindowSize.medium),
      (840.0, WindowSize.expanded),
      (1199.0, WindowSize.expanded),
      (1200.0, WindowSize.large),
      (1599.0, WindowSize.large),
      (1600.0, WindowSize.extraLarge),
      (2560.0, WindowSize.extraLarge),
    ]) {
      test('$width -> $size', () => expect(WindowSize.forWidth(width), size));
    }
  });

  test('size classes compare in order, and widen their gutters', () {
    expect(WindowSize.large >= WindowSize.expanded, isTrue);
    expect(WindowSize.compact < WindowSize.medium, isTrue);
    expect(WindowSize.values.map((s) => s.gutter), [16, 24, 24, 32, 32]);
  });

  test('centeredInset centres wide content and never goes below the gutter', () {
    expect(centeredInset(1000, 16, maxWidth: 600), 200);
    expect(centeredInset(500, 16, maxWidth: 600), 16);
    expect(centeredInset(630, 16, maxWidth: 600), 16); // 600 + 2*16 > 630
  });

  Future<void> sized(WidgetTester tester, Size size, Widget child) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: child)));
  }

  testWidgets('context helpers read the window', (tester) async {
    late BuildContext ctx;
    await sized(tester, const Size(1300, 400), Builder(builder: (c) {
      ctx = c;
      return const SizedBox();
    }));
    expect((ctx.windowSize, ctx.isShortHeight, ctx.showsTwoPanes), (WindowSize.large, true, true));
  });

  group('ListDetail', () {
    Widget layout({Widget? detail}) => ListDetail(
          list: const Text('list'),
          detail: detail,
          emptyDetail: const Text('empty'),
        );

    testWidgets('compact shows only the list', (tester) async {
      await sized(tester, const Size(400, 800), layout(detail: const Text('detail')));
      expect(find.text('list'), findsOneWidget);
      expect(find.text('detail'), findsNothing);
    });

    testWidgets('expanded shows list and detail, or the empty placeholder', (tester) async {
      await sized(tester, const Size(1000, 800), layout());
      expect(find.text('empty'), findsOneWidget);
      expect(tester.getSize(find.ancestor(of: find.text('list'), matching: find.byType(SizedBox)).first).width, listPaneWidth);

      await sized(tester, const Size(1000, 800), layout(detail: const Text('detail')));
      expect(find.text('detail'), findsOneWidget);
    });

    testWidgets('large widens the list pane', (tester) async {
      await sized(tester, const Size(1400, 800), layout());
      expect(tester.getSize(find.ancestor(of: find.text('list'), matching: find.byType(SizedBox)).first).width, listPaneWidthLarge);
    });
  });

  testWidgets('ContentWidth caps the width', (tester) async {
    await sized(tester, const Size(1400, 800), const ContentWidth(maxWidth: 500, child: SizedBox(height: 10, width: double.infinity)));
    expect(tester.getSize(find.byType(ConstrainedBox).last).width, 500);
  });
}
