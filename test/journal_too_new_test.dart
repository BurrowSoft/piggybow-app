import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piggybow/features/start/journal_too_new_app.dart';

import 'helpers.dart';

/// A journal from a newer Piggybow (JournalTooNew, feature 19): the app
/// opens on one line asking for an update, and nothing else.
void main() {
  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    testWidgets('it asks for an update (${mode.name})', (tester) async {
      await tester.pumpWidget(JournalTooNewApp(themeMode: mode));
      await tester.pumpAndSettle();
      expect(byId('journal-too-new'), findsOneWidget);
      expect(find.text('Update Piggybow to open this journal.'), findsOneWidget);
      expect(find.byType(Text), findsOneWidget, reason: 'nothing else shows');
    });
  }

  testWidgets('at 320 dp and twice the text size, the line wraps whole', (tester) async {
    tester.view.devicePixelRatio = 2;
    tester.view.physicalSize = const Size(320 * 2, 640 * 2);
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(const JournalTooNewApp());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    final box = tester.getRect(find.text('Update Piggybow to open this journal.'));
    expect(box.left, greaterThanOrEqualTo(24));
    expect(box.right, lessThanOrEqualTo(320 - 24));
  });
}
