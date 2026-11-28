import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piggybow/core/clock.dart';
import 'package:piggybow/l10n/gen/app_localizations.dart';
import 'package:piggybow/tips/tips.dart';

import 'helpers.dart';

/// Home reads again when the phone's day or the pig's night turns over (local
/// midnight, 04:00 and 22:00), with one timer to the next turn, and when the
/// app comes back. Today's idea shows it: it changes with the local date.
void main() {
  group('Clock.untilNextTurn', () {
    Duration until(String utc, String zone) => Clock(fixed: DateTime.parse(utc)).untilNextTurn(zone);

    test('Bangkok: 22:00, midnight and 04:00 are the turns', () {
      // 08:30 → 22:00.
      expect(until('2026-10-02T01:30:00Z', 'Asia/Bangkok'), const Duration(hours: 13, minutes: 30));
      // 23:00 → midnight.
      expect(until('2026-10-02T16:00:00Z', 'Asia/Bangkok'), const Duration(hours: 1));
      // 03:59 → 04:00.
      expect(until('2026-10-01T20:59:00Z', 'Asia/Bangkok'), const Duration(minutes: 1));
      // On a turn: the next one, not this one.
      expect(until('2026-10-02T15:00:00Z', 'Asia/Bangkok'), const Duration(hours: 2));
    });

    test('a daylight-saving change in between counts: real time, not wall time', () {
      // London, 29 March 2026: 00:30 GMT → 04:00 BST is 2 h 30 min (01:00 doesn't happen).
      expect(until('2026-03-29T00:30:00Z', 'Europe/London'), const Duration(hours: 2, minutes: 30));
      // London, 25 October 2026: 00:30 BST → 04:00 GMT is 4 h 30 min (01:00 happens twice).
      expect(until('2026-10-24T23:30:00Z', 'Europe/London'), const Duration(hours: 4, minutes: 30));
    });

    test("midnight only: the repeats' catch-up turn", () {
      Duration midnight(String utc, String zone) =>
          Clock(fixed: DateTime.parse(utc)).untilNextTurn(zone, hours: const [0]);
      // 08:30 in Bangkok → midnight, past 22:00.
      expect(midnight('2026-10-02T01:30:00Z', 'Asia/Bangkok'), const Duration(hours: 15, minutes: 30));
      // London, 29 March 2026: 00:30 GMT → midnight BST is 22 h 30 min (an hour is skipped).
      expect(midnight('2026-03-29T00:30:00Z', 'Europe/London'), const Duration(hours: 22, minutes: 30));
    });
  });

  group('Home', () {
    String idea(WidgetTester tester) {
      final card = byId('home-idea');
      final l10n = AppLocalizations.of(tester.element(card));
      final texts = tester.widgetList<Text>(find.descendant(of: card, matching: find.byType(Text)));
      return texts.map((t) => t.data).firstWhere((d) => d != l10n.ideaTitle && d != l10n.ideaAnother)!;
    }

    String tipOn(WidgetTester tester, DateTime day) =>
        tipText(AppLocalizations.of(tester.element(byId('home-idea'))), tipForDay(day));

    Future<void> openHome(WidgetTester tester, TestApp app) async {
      await app.pump(tester);
      for (var i = 0; i < 40 && byId('home-week').evaluate().isEmpty; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      await tester.pumpAndSettle();
      await tester.revealId('home-idea');
    }

    testWidgets('at midnight it reads again: the new day, with nothing else changed', (tester) async {
      // 23:59 on 2 October in Bangkok.
      final clock = MovableClock(DateTime.utc(2026, 10, 2, 16, 59));
      final app = TestApp(clock: clock);
      await openHome(tester, app);
      expect(idea(tester), tipOn(tester, DateTime(2026, 10, 2)));

      // 00:00:01 on 3 October: the timer set for midnight fires.
      clock.now = DateTime.utc(2026, 10, 2, 17, 0, 1);
      await tester.pump(const Duration(seconds: 61));
      await tester.pumpAndSettle();
      expect(idea(tester), tipOn(tester, DateTime(2026, 10, 3)));
    });

    testWidgets('a new day starts on its own idea, after "Another idea" the day before', (tester) async {
      final clock = MovableClock(DateTime.utc(2026, 10, 2, 16, 59));
      final app = TestApp(clock: clock);
      await openHome(tester, app);
      // Twice: one step would land on the next day's idea anyway.
      await tester.tapId('home-idea-another');
      await tester.tapId('home-idea-another');
      expect(idea(tester), isNot(tipOn(tester, DateTime(2026, 10, 2))));
      expect(idea(tester), isNot(tipOn(tester, DateTime(2026, 10, 3))));

      clock.now = DateTime.utc(2026, 10, 2, 17, 0, 1);
      await tester.pump(const Duration(seconds: 61));
      await tester.pumpAndSettle();
      expect(idea(tester), tipOn(tester, DateTime(2026, 10, 3)));
    });

    testWidgets('coming back to the app reads again', (tester) async {
      // Noon on 2 October; the next turn (22:00) is far off.
      final clock = MovableClock(DateTime.utc(2026, 10, 2, 5));
      final app = TestApp(clock: clock);
      await openHome(tester, app);
      expect(idea(tester), tipOn(tester, DateTime(2026, 10, 2)));

      // A day later, the phone wakes the app.
      clock.now = DateTime.utc(2026, 10, 3, 5);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(idea(tester), tipOn(tester, DateTime(2026, 10, 3)));
    });
  });
}
