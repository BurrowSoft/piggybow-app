@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piggybow/features/start/journal_too_new_app.dart';

import '../helpers.dart';
import '../helpers/fonts.dart';
import 'layout_matrix.dart';

/// A journal from a newer Piggybow (JournalTooNew, feature 19): the app
/// opens on one line asking for an update, and nothing else (JN1), in every
/// layout case. Goldens at 320 dp ×2, light and dark.
void main() {
  setUpAll(loadAppFonts);

  for (final c in layoutCases) {
    testWidgets('JN1 a journal from a newer Piggybow: the update line ($c)', (
      tester,
    ) async {
      setLayout(tester, c);
      await tester.pumpWidget(
        JournalTooNewApp(
          themeMode: c.brightness == Brightness.dark
              ? ThemeMode.dark
              : ThemeMode.light,
        ),
      );
      await tester.pumpAndSettle();
      expect(byId('journal-too-new'), findsOneWidget);
      expect(
        find.text('Update Piggybow to open this journal.'),
        findsOneWidget,
      );
      expect(find.byType(Text), findsOneWidget, reason: 'nothing else shows');
      await expectSoundLayout(tester, reason: 'JN1');
      if (c.takesGolden) {
        await expectLayoutGolden(
          tester,
          c,
          screen: 'journal-too-new',
          state: 'update',
          stateId: 'JN1',
        );
      }
    });
  }
}
