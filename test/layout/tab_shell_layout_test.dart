import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piggybow/l10n/gen/app_localizations.dart';

import '../helpers.dart';
import '../helpers/fonts.dart';
import 'layout_matrix.dart';

/// D1 (decision 43): the four tabs, each selected in turn, in every layout
/// case. Each time the screen above is sound, the selected tab says so,
/// every label is whole and on one line, and every indicator is on the bar
/// and clear of its neighbours: a selected label never crowds the others.
void main() {
  setUpAll(loadAppFonts);
  const tabs = ['home', 'timeline', 'summary', 'me'];

  Future<void> settle(WidgetTester tester, Finder f) async {
    for (var i = 0; i < 40 && f.evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.pumpAndSettle();
  }

  for (final c in layoutCases) {
    testWidgets('D1 the four tabs, each selected in turn ($c)', (tester) async {
      setLayout(tester, c);
      final app = TestApp()..prefs.appearance = c.appearance;
      await tester.runAsync(app.openJournal);
      await app.pump(tester);
      await settle(tester, byId('home-pig-line'));
      final l10n = AppLocalizations.of(tester.element(byId('home-screen')));
      final labels = {
        'home': l10n.tabHome,
        'timeline': l10n.tabTimeline,
        'summary': l10n.tabSummary,
        'me': l10n.tabMe,
      };
      Finder label(String id) => find.descendant(
        of: byId('tab-$id'),
        matching: find.text(labels[id]!),
      );

      for (final selected in tabs) {
        await tester.tapId('tab-$selected');
        await settle(tester, byId('$selected-screen'));
        final at = '$selected selected';
        expect(byId('$selected-screen'), findsOneWidget, reason: at);
        await expectSoundLayout(tester, reason: at);

        for (final id in tabs) {
          final state = tester
              .getSemantics(byId('tab-$id'))
              .flagsCollection
              .isSelected;
          expect(
            state,
            id == selected ? Tristate.isTrue : isNot(Tristate.isTrue),
            reason: 'tab-$id, $at',
          );
          // One line, all of it drawn.
          final p = tester.renderObject<RenderParagraph>(label(id));
          expect(p.didExceedMaxLines, isFalse, reason: '$id cut, $at');
          expect(
            p.size.width,
            greaterThanOrEqualTo(p.getMaxIntrinsicWidth(double.infinity) - 0.5),
            reason: '$id narrower than its text, $at',
          );
        }

        // Every indicator on the bar, and no two overlapping.
        final pills = [
          for (final id in tabs)
            tester.getRect(
              find.descendant(
                of: byId('tab-$id'),
                matching: find.byType(NavigationIndicator),
              ),
            ),
        ];
        for (var i = 0; i < tabs.length; i++) {
          expect(
            pills[i].left,
            greaterThanOrEqualTo(-0.5),
            reason: '${tabs[i]} indicator off the bar, $at',
          );
          expect(
            pills[i].right,
            lessThanOrEqualTo(c.width + 0.5),
            reason: '${tabs[i]} indicator off the bar, $at',
          );
          if (i > 0) {
            expect(
              pills[i].left,
              greaterThanOrEqualTo(pills[i - 1].right - 0.5),
              reason: '${tabs[i - 1]} and ${tabs[i]} indicators overlap, $at',
            );
          }
        }
      }
    });
  }
}
