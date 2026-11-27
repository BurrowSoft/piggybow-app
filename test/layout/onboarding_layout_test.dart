import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers.dart';
import '../helpers/fonts.dart';
import 'layout_matrix.dart';

/// Onboarding in every layout case (plan §0.3, decision 43): O1 with one of
/// the longest currency names, O2 with "Pick at least one.", then with the
/// plan field and "Enter your weekly plan.", O3 with its error, and the
/// currency picker.
void main() {
  setUpAll(loadAppFonts);

  /// The checks on the whole of [screenId]'s list, scrolled top to bottom.
  Future<void> checkScrolled(
    WidgetTester tester,
    String screenId,
    String state,
  ) async {
    final list = find
        .descendant(of: byId(screenId), matching: find.byType(Scrollable))
        .first;
    final position = tester.state<ScrollableState>(list).position;
    position.jumpTo(0);
    await tester.pump();
    for (var i = 0; i < 20; i++) {
      await expectSoundLayout(
        tester,
        reason: '$state at ${position.pixels.round()}',
      );
      if (position.pixels >= position.maxScrollExtent) break;
      position.jumpTo(
        (position.pixels + position.viewportDimension * 0.7).clamp(
          0.0,
          position.maxScrollExtent,
        ),
      );
      await tester.pump();
    }
    position.jumpTo(0);
    await tester.pumpAndSettle();
  }

  Future<void> open(WidgetTester tester, LayoutCase c) async {
    setLayout(tester, c);
    // "Israeli new shekel (₪)": one of the longest currency lines.
    final app = TestApp(onboarded: false, currency: 'ILS')
      ..prefs.appearance = c.appearance;
    await tester.runAsync(app.openJournal);
    await app.pump(tester);
    await tester.pumpAndSettle();
  }

  for (final c in layoutCases) {
    testWidgets('O1 Welcome ($c)', (tester) async {
      await open(tester, c);
      tester.expectScreen('onb-welcome');
      await checkScrolled(tester, 'onb-welcome', 'O1');
    });

    testWidgets('O2 with its errors and the plan field ($c)', (tester) async {
      await open(tester, c);
      await tester.tapId('onb-start');
      await tester.tapId('onb-continue');
      expect(find.text('Pick at least one.'), findsOneWidget);
      await checkScrolled(tester, 'onb-happy', 'O2 pick one');
      await tester.tapId('onb-pick-plan');
      await tester.tapId('onb-continue');
      expect(find.text('Enter your weekly plan.'), findsOneWidget);
      await checkScrolled(tester, 'onb-happy', 'O2 plan needed');
    });

    testWidgets('O3 with its error ($c)', (tester) async {
      await open(tester, c);
      await tester.tapId('onb-start');
      await tester.tapId('onb-pick-save');
      await tester.tapId('onb-continue');
      await tester.tapId('onb-goal-start');
      expect(find.text('Give your goal a name.'), findsOneWidget);
      await checkScrolled(tester, 'onb-goal', 'O3');
    });

    testWidgets('the currency picker ($c)', (tester) async {
      await open(tester, c);
      await tester.tapId('onb-currency-change');
      tester.expectScreen('currency-screen');
      await checkScrolled(tester, 'currency-screen', 'picker');
    });
  }
}
