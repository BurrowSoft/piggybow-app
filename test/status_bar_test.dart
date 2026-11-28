import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piggybow/core/status_bar.dart';
import 'package:piggybow/journal/entry.dart';
import 'package:piggybow/journal/goal.dart';

import 'helpers.dart';

/// The status bar over pages with no app bar (decision 65): see-through, so
/// the page shows behind it, with icons that read on the page in light and
/// dark. O1 Welcome showed a grey band there; the celebration had no style of
/// its own either.
void main() {
  /// What the app last asked the system for, as the status bar shows it.
  void expectPageStatusBar(bool dark, String where) {
    final style = SystemChrome.latestStyle!;
    expect(style.statusBarColor, Colors.transparent, reason: where);
    expect(
      style.statusBarIconBrightness,
      dark ? Brightness.light : Brightness.dark,
      reason: '$where: Android icons',
    );
    expect(
      style.statusBarBrightness,
      dark ? Brightness.dark : Brightness.light,
      reason: '$where: iOS icons',
    );
    expect(style.systemStatusBarContrastEnforced, isFalse, reason: where);
  }

  /// A style no page asks for, so a stale one from the last test can't pass.
  Future<void> forgetTheLastStyle(WidgetTester tester) async {
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(statusBarColor: Color(0xFFFF0000)),
    );
    await tester.pump();
    expect(SystemChrome.latestStyle!.statusBarColor, const Color(0xFFFF0000));
  }

  test('the style: see-through, icons for the theme, nav bar untouched', () {
    for (final brightness in Brightness.values) {
      final s = pageStatusBar(brightness);
      expect(s.statusBarColor, Colors.transparent);
      expect(s.systemNavigationBarColor, isNull);
      expect(s.systemNavigationBarIconBrightness, isNull);
      expect(s.systemNavigationBarDividerColor, isNull);
    }
    expect(
      pageStatusBar(Brightness.light).statusBarIconBrightness,
      Brightness.dark,
    );
    expect(
      pageStatusBar(Brightness.dark).statusBarIconBrightness,
      Brightness.light,
    );
  });

  for (final appearance in ['light', 'dark']) {
    final dark = appearance == 'dark';

    testWidgets('O1 Welcome: see-through, icons for $appearance', (
      tester,
    ) async {
      await forgetTheLastStyle(tester);
      final app = TestApp(onboarded: false)..prefs.appearance = appearance;
      await tester.runAsync(app.openJournal);
      await app.pump(tester);
      await tester.pumpAndSettle();
      expect(byId('onb-welcome'), findsOneWidget);
      expect(find.byType(AppBar), findsNothing, reason: 'no bar of its own');
      expectPageStatusBar(dark, 'O1');
    });

    testWidgets('the celebration: see-through, icons for $appearance', (
      tester,
    ) async {
      await forgetTheLastStyle(tester);
      final app = TestApp()..prefs.appearance = appearance;
      await tester.runAsync(app.openJournal);
      await tester.runAsync(() async {
        final t = DateTime.utc(2026, 9, 20);
        await app.journal.putGoal(
          Goal(
            id: 'g1',
            name: 'Bike',
            targetMinor: 1000,
            createdAt: t,
            updatedAt: t,
          ),
        );
        await app.journal.addEntry(
          type: EntryType.saved,
          amountMinor: 1000,
          currency: 'THB',
          localDate: '2026-10-01',
        );
      });
      await app.pump(tester);
      for (
        var i = 0;
        i < 40 && byId('goal-done-screen').evaluate().isEmpty;
        i++
      ) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      await tester.pumpAndSettle();
      expect(byId('goal-done-screen'), findsOneWidget);
      expectPageStatusBar(dark, 'the celebration');
    });
  }
}
