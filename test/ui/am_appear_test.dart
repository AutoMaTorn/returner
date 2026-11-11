import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:returner/theme/am_widgets.dart';
import 'package:returner/theme/automatorn_theme.dart';

void main() {
  Future<void> pump(WidgetTester tester, {required bool animations}) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        FakeAccessibilityFeatures(disableAnimations: !animations);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await tester.pumpWidget(
      MaterialApp(
        theme: Automatorn.dark(),
        home: const Column(
          children: [
            AmAppear(child: Text('first')),
            AmAppear(order: 2, child: Text('third')),
          ],
        ),
      ),
    );
  }

  double opacity(WidgetTester tester, String text) => tester
      .widget<Opacity>(
        find.ancestor(of: find.text(text), matching: find.byType(Opacity)),
      )
      .opacity;

  double rise(WidgetTester tester, String text) => tester
      .widget<Transform>(
        find.ancestor(of: find.text(text), matching: find.byType(Transform)),
      )
      .transform
      .getTranslation()
      .y;

  testWidgets('blocks fade in and rise 4px, one after another', (
    tester,
  ) async {
    await pump(tester, animations: true);
    expect(opacity(tester, 'first'), 0);
    expect(rise(tester, 'first'), 4);

    await tester.pump(const Duration(milliseconds: 60));
    // The first block has started; the third waits for its 80 ms delay.
    expect(opacity(tester, 'first'), greaterThan(0));
    expect(opacity(tester, 'third'), 0);

    await tester.pumpAndSettle();
    expect(opacity(tester, 'first'), 1);
    expect(opacity(tester, 'third'), 1);
    expect(rise(tester, 'third'), 0);
  });

  testWidgets('with animations off the block is there at once', (
    tester,
  ) async {
    await pump(tester, animations: false);
    expect(opacity(tester, 'first'), 1);
    expect(opacity(tester, 'third'), 1);
    expect(rise(tester, 'first'), 0);
  });
}
