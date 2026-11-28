import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piggybow/core/clock.dart';
import 'package:piggybow/journal/entry.dart';
import 'package:piggybow/journal/goal.dart';
import 'package:piggybow/pig/pig_mood.dart';

import 'helpers.dart';

/// Feature 2, the sleepy pig at night: from 22:00 to 05:59 on the phone's
/// clock, in its zone, Home's pig is the sleepy pig saying it's late. A
/// reaction to what was just added wins for that visit, and a goal reached in
/// the last 24 hours keeps its line. Never a word about spending.
void main() {
  const nightLine = "It's getting late. I'll be here tomorrow.";
  const day = PigState(PigMood.calm, 'pigCalm1');
  const goalDay = PigState(PigMood.delighted, 'pigDelightedGoal', {
    'goalName': 'Bike',
  });

  group('the rule', () {
    test('Home reads again at night\'s two edges (Clock.turnHours, #62)', () {
      expect(Clock.turnHours, containsAll([nightStartHour, nightEndHour]));
    });

    test('night is 22:00 to 05:59', () {
      for (final h in [22, 23, 0, 1, 5]) {
        expect(isNight(h), isTrue, reason: '$h:00');
      }
      for (final h in [6, 7, 12, 21]) {
        expect(isNight(h), isFalse, reason: '$h:00');
      }
    });

    test('at night with nothing just added: the sleepy pig, saying it is '
        'late', () {
      final s = pigAtNight(day, night: true, lastAdd: null);
      expect(s, nightPig);
      expect(s.mood, PigMood.sleepy);
      expect(pigBubbleKey(s, null), 'homeNightLine');
    });

    test('by day: the pig as usual', () {
      expect(pigAtNight(day, night: false, lastAdd: null), day);
    });

    test('just added: the reaction wins, as by day', () {
      for (final r in PigReaction.values) {
        final s = pigAtNight(day, night: true, lastAdd: r);
        expect(s, day, reason: r.name);
        expect(pigBubbleKey(s, r), isNot('homeNightLine'), reason: r.name);
      }
    });

    test('a goal reached in the last 24 hours keeps its line', () {
      expect(pigAtNight(goalDay, night: true, lastAdd: null), goalDay);
    });
  });

  group('Home at the boundaries, on a phone in Bangkok (UTC+7)', () {
    Finder line(String text) =>
        find.descendant(of: byId('home-pig-line'), matching: find.text(text));

    Future<TestApp> openAt(WidgetTester tester, String localTime) async {
      tester.view.devicePixelRatio = 3;
      tester.view.physicalSize = const Size(360 * 3, 1600 * 3);
      addTearDown(tester.view.reset);
      final app = TestApp(
        clock: Clock(fixed: DateTime.parse('2026-10-02T$localTime:00+07:00')),
      );
      await tester.runAsync(app.openJournal);
      return app;
    }

    Future<void> pumpHome(WidgetTester tester, TestApp app) async {
      await app.pump(tester);
      for (var i = 0; i < 40 && byId('home-pig-line').evaluate().isEmpty; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      await tester.pumpAndSettle();
    }

    // The phone's zone, not UTC: 22:00 in Bangkok is 15:00 UTC (daytime
    // there), 05:59 is 22:59 UTC the day before (night there too), and
    // 06:00 is 23:00 UTC (still night in UTC).
    for (final (time, night) in [
      ('21:59', false),
      ('22:00', true),
      ('05:59', true),
      ('06:00', false),
    ]) {
      testWidgets('$time: ${night ? 'the night pig' : 'the pig as by day'}', (
        tester,
      ) async {
        final app = await openAt(tester, time);
        await pumpHome(tester, app);
        expect(line(nightLine), night ? findsOneWidget : findsNothing);
        if (!night) {
          expect(
            line('Hi! Tap Add to note your first spend or save.'),
            findsOneWidget,
          );
        }
      });
    }

    testWidgets('Home left open at 21:59: at 22:00 its own turn re-read '
        'brings the night pig, with nothing tapped', (tester) async {
      tester.view.devicePixelRatio = 3;
      tester.view.physicalSize = const Size(360 * 3, 1600 * 3);
      addTearDown(tester.view.reset);
      final clock = MovableClock(
        DateTime.parse('2026-10-02T21:59:00+07:00').toUtc(),
      );
      final app = TestApp(clock: clock);
      await tester.runAsync(app.openJournal);
      await pumpHome(tester, app);
      expect(line(nightLine), findsNothing);

      clock.now = DateTime.parse('2026-10-02T22:00:00+07:00').toUtc();
      // Home's turn timer (Clock.untilNextTurn) was set for 22:00.
      await tester.pump(const Duration(minutes: 1));
      for (var i = 0; i < 40 && line(nightLine).evaluate().isEmpty; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      await tester.pumpAndSettle();
      expect(line(nightLine), findsOneWidget);
    });

    testWidgets('23:00, just after an Add: the reaction', (tester) async {
      final app = await openAt(tester, '23:00');
      await pumpHome(tester, app);
      expect(line(nightLine), findsOneWidget);
      await tester.tapId('home-add');
      await tester.tapId('add-seg-saved');
      await tester.enterId('add-amount', '5');
      await tester.tapId('add-submit');
      await tester.pumpAndSettle();
      expect(line('Into the rainbow it goes!'), findsOneWidget);
      expect(line(nightLine), findsNothing);
    });

    testWidgets('23:00, a goal reached tonight: its line stays', (
      tester,
    ) async {
      final app = await openAt(tester, '23:00');
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
        // The celebration was shown; Home is next.
        await app.journal.markCelebrated('g1');
        await app.journal.addEntry(
          type: EntryType.saved,
          amountMinor: 1000,
          currency: 'THB',
          localDate: '2026-10-02',
        );
      });
      await pumpHome(tester, app);
      expect(line('You reached Bike!'), findsOneWidget);
      expect(line(nightLine), findsNothing);
    });
  });
}
