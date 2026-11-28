import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piggybow/goal/goal_pace.dart';
import 'package:piggybow/journal/entry.dart';
import 'package:piggybow/journal/goal.dart';
import 'package:piggybow/l10n/gen/app_localizations.dart';
import 'package:piggybow/money/rate.dart';
import 'package:piggybow/router.dart';

import '../tool/no_guilt.dart' show findGuilt;
import 'helpers.dart';

/// Feature 11, a goal's target date and its pace: an optional date in the
/// goal form (not in onboarding); under "{x} to go" on the goal, "About N
/// weeks to go at this pace" when the last 4 weeks have saves (up to 52
/// weeks), else "Target: {date}" until that day has passed. The two are
/// never compared: never "behind", never red.
void main() {
  // Tests run on Friday 2 October 2026, 08:30 in Bangkok (helpers.dart).
  final t = DateTime.utc(2026, 9, 20);
  Goal bike({String? targetDate, int target = 100000, int start = 0}) => Goal(
    id: 'g1',
    name: 'Bike',
    targetMinor: target,
    startMinor: start,
    createdAt: t,
    updatedAt: t,
    targetDate: targetDate,
  );

  group('the goal keeps its target date', () {
    test('stored as target_date, absent when there is none', () {
      expect(
        bike(targetDate: '2026-12-31').toMap()['target_date'],
        '2026-12-31',
      );
      expect(bike().toMap().containsKey('target_date'), isFalse);
    });

    test("read back; one this build can't read is dropped, not the goal", () {
      final m = bike(targetDate: '2026-12-31').toMap();
      expect(Goal.fromMap('g1', m)!.targetDate, '2026-12-31');
      expect(Goal.fromMap('g1', bike().toMap())!.targetDate, isNull);
      for (final bad in ['2026-02-30', '31/12/2026', 20261231]) {
        final g = Goal.fromMap('g1', {...m, 'target_date': bad});
        expect(g, isNotNull, reason: '$bad');
        expect(g!.targetDate, isNull, reason: '$bad');
      }
    });

    test('copyWith keeps it unless given; null removes it', () {
      final g = bike(targetDate: '2026-12-31');
      expect(g.copyWith(name: 'Bike 2').targetDate, '2026-12-31');
      expect(g.copyWith(targetDate: '2027-01-15').targetDate, '2027-01-15');
      expect(g.copyWith(targetDate: null).targetDate, isNull);
    });
  });

  group('the pace', () {
    Entry entry(String day, int amount, {EntryType type = EntryType.saved}) =>
        Entry(
          id: 'e-$day-$amount',
          type: type,
          amountMinor: amount,
          currency: 'THB',
          localDate: day,
          createdAt: t,
          updatedAt: t,
          goalId: 'g1',
        );
    final today = DateTime(2026, 10, 2);

    test('the last 4 weeks, today included: from 5 September', () {
      expect(
        recentSavesMinor([
          entry('2026-09-04', 100),
          entry('2026-09-05', 200),
          entry('2026-10-02', 400),
        ], today),
        600,
      );
    });

    test('saves only', () {
      expect(
        recentSavesMinor([
          entry('2026-10-01', 500),
          entry('2026-10-01', 900, type: EntryType.spent),
        ], today),
        500,
      );
    });

    // A take-out (#61) slows the pace: the last 4 weeks are saves less
    // withdrawals (UX).
    test('a take-out nets out: 300 − 300 is no pace', () {
      final recent = recentSavesMinor([
        entry('2026-10-01', 300),
        entry('2026-10-02', 300, type: EntryType.withdraw),
      ], today);
      expect(recent, 0);
      expect(goalPaceWeeks(remainingMinor: 1000, recentMinor: recent), isNull);
      expect(
        goalOutlook(
          remainingMinor: 1000,
          recentMinor: recent,
          targetDate: null,
          today: '2026-10-02',
        ).paceWeeks,
        isNull,
      );
    });

    test('500 − 200: the pace on 300', () {
      final recent = recentSavesMinor([
        entry('2026-09-30', 500),
        entry('2026-10-01', 200, type: EntryType.withdraw),
      ], today);
      expect(recent, 300);
      // ceil(1200 × 4 ÷ 300) = 16 weeks.
      expect(goalPaceWeeks(remainingMinor: 1200, recentMinor: recent), 16);
    });

    // Wiring item 18 (#60 with #74): a save in another currency counts at
    // its home amount.
    test('a save in another currency counts at its home amount', () {
      // EUR 10.00 at "1 EUR = 39.12 THB" is 391.20 at home.
      final abroad = Entry(
        id: 'e-abroad',
        type: EntryType.saved,
        amountMinor: 1000,
        currency: 'EUR',
        localDate: '2026-10-01',
        createdAt: t,
        updatedAt: t,
        goalId: 'g1',
        rate: parseRate('39.12', RateDirection.toHome, mark: '.').rate,
        convertedMinor: 39120,
      );
      expect(recentSavesMinor([entry('2026-10-01', 500), abroad], today), 39620);
    });

    test('a take-out before the 4 weeks doesn\'t count', () {
      expect(
        recentSavesMinor([
          entry('2026-09-04', 400, type: EntryType.withdraw),
          entry('2026-10-01', 500),
        ], today),
        500,
      );
    });

    test('weeks: ceil(what is left × 4 ÷ the last 4 weeks)', () {
      expect(goalPaceWeeks(remainingMinor: 10000, recentMinor: 10000), 4);
      expect(goalPaceWeeks(remainingMinor: 10001, recentMinor: 10000), 5);
      expect(goalPaceWeeks(remainingMinor: 2500, recentMinor: 10000), 1);
      expect(goalPaceWeeks(remainingMinor: 1, recentMinor: 10000), 1);
    });

    test('up to 52 weeks; none beyond, with no saves, or nothing left', () {
      expect(goalPaceWeeks(remainingMinor: 130000, recentMinor: 10000), 52);
      expect(goalPaceWeeks(remainingMinor: 130001, recentMinor: 10000), isNull);
      expect(goalPaceWeeks(remainingMinor: 10000, recentMinor: 0), isNull);
      expect(goalPaceWeeks(remainingMinor: 0, recentMinor: 10000), isNull);
      expect(goalPaceWeeks(remainingMinor: -5, recentMinor: 10000), isNull);
    });

    test('the largest amounts stay exact', () {
      const big = 999999999999999;
      expect(goalPaceWeeks(remainingMinor: big, recentMinor: big), 4);
    });
  });

  group('the line under "{x} to go"', () {
    ({int? paceWeeks, String? targetDate}) outlook({
      int remaining = 75000,
      int recent = 0,
      String? date,
    }) => goalOutlook(
      remainingMinor: remaining,
      recentMinor: recent,
      targetDate: date,
      today: '2026-10-02',
    );

    test('the pace when there is one, never next to the date', () {
      expect(outlook(recent: 25000, date: '2026-12-31'), (
        paceWeeks: 12,
        targetDate: null,
      ));
    });

    test('no pace: the date, until it has passed', () {
      expect(outlook(date: '2026-12-31'), (
        paceWeeks: null,
        targetDate: '2026-12-31',
      ));
      expect(outlook(date: '2026-10-02'), (
        paceWeeks: null,
        targetDate: '2026-10-02',
      ));
      expect(outlook(date: '2026-10-01'), (paceWeeks: null, targetDate: null));
    });

    test('over 52 weeks: the date instead, if any', () {
      expect(outlook(remaining: 10000000, recent: 100, date: '2027-06-30'), (
        paceWeeks: null,
        targetDate: '2027-06-30',
      ));
      expect(outlook(remaining: 10000000, recent: 100), (
        paceWeeks: null,
        targetDate: null,
      ));
    });

    test('reached: nothing', () {
      expect(outlook(remaining: 0, recent: 500, date: '2026-12-31'), (
        paceWeeks: null,
        targetDate: null,
      ));
    });
  });

  Future<void> settle(WidgetTester tester, Finder f) async {
    for (var i = 0; i < 40 && f.evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.pumpAndSettle();
  }

  Future<TestApp> open(
    WidgetTester tester, {
    required String location,
    required Finder until,
    Future<void> Function(TestApp)? seed,
    bool onboarded = true,
  }) async {
    final app = TestApp(onboarded: onboarded);
    await tester.runAsync(app.openJournal);
    if (seed != null) await tester.runAsync(() => seed(app));
    await app.pump(tester, location: location);
    await settle(tester, until);
    return app;
  }

  Future<void> save(TestApp app, int minor, String day) => app.journal.addEntry(
    type: EntryType.saved,
    amountMinor: minor,
    currency: 'THB',
    localDate: day,
  );

  group('the goal form', () {
    testWidgets('create with a target date, picked in the calendar', (
      tester,
    ) async {
      final app = await open(
        tester,
        location: GoalRoutes.create,
        until: byId('goal-submit'),
      );
      expect(find.text('Target date (optional)'), findsOneWidget);
      expect(byId('goal-target-date-remove'), findsNothing);
      await tester.enterId('goal-name', 'Bike');
      await tester.enterId('goal-amount', '1000');
      await tester.tapId('goal-target-date');
      // The calendar opens on tomorrow, Saturday 3 October; today can't be
      // picked.
      expect(find.byType(DatePickerDialog), findsOneWidget);
      await tester.tap(find.text('15'));
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(find.text('Oct 15, 2026'), findsOneWidget);
      expect(byId('goal-target-date-remove'), findsOneWidget);
      await tester.tapId('goal-submit');
      final goal = (await tester.runAsync(app.journal.activeGoal))!;
      expect(goal.targetDate, '2026-10-15');
    });

    testWidgets('edit: the date shown, and × removes it', (tester) async {
      final app = await open(
        tester,
        location: GoalRoutes.edit('g1'),
        until: byId('goal-submit'),
        seed: (app) => app.journal.putGoal(bike(targetDate: '2026-12-31')),
      );
      expect(find.text('Dec 31, 2026'), findsOneWidget);
      expect(
        tester.getSemantics(byId('goal-target-date-remove')),
        isSemantics(tooltip: 'Remove target date', isButton: true),
      );
      await tester.tapId('goal-target-date-remove');
      expect(find.text('Dec 31, 2026'), findsNothing);
      expect(byId('goal-target-date-remove'), findsNothing);
      await tester.tapId('goal-submit');
      final goal = (await tester.runAsync(() => app.journal.goal('g1')))!;
      expect(goal.targetDate, isNull);
    });

    testWidgets('edit keeps the date when it is left alone', (tester) async {
      final app = await open(
        tester,
        location: GoalRoutes.edit('g1'),
        until: byId('goal-submit'),
        seed: (app) => app.journal.putGoal(bike(targetDate: '2026-12-31')),
      );
      await tester.enterId('goal-name', 'Bike and helmet');
      await tester.tapId('goal-submit');
      final goal = (await tester.runAsync(() => app.journal.goal('g1')))!;
      expect((goal.name, goal.targetDate), ('Bike and helmet', '2026-12-31'));
    });

    testWidgets("onboarding's first goal has no target date", (tester) async {
      await open(
        tester,
        location: OnboardingRoutes.goal,
        until: byId('onb-goal-start'),
        onboarded: false,
      );
      tester.expectScreen('onb-goal');
      expect(byId('goal-target-date'), findsNothing);
    });
  });

  group("the goal's detail", () {
    Finder line() => byId('goal-outlook');

    testWidgets('saves in the last 4 weeks: the weeks to go at this pace', (
      tester,
    ) async {
      await open(
        tester,
        location: GoalRoutes.detail('g1'),
        until: byId('goal-add-savings'),
        seed: (app) async {
          await app.journal.putGoal(bike(targetDate: '2026-12-31'));
          await save(app, 25000, '2026-09-28');
        },
      );
      // 75,000 left at 25,000 in 4 weeks: 12 weeks.
      expect(find.text('About 12 weeks to go at this pace'), findsOneWidget);
      expect(find.textContaining('Target'), findsNothing);
    });

    testWidgets('no pace, a date ahead: "Target: {date}"', (tester) async {
      await open(
        tester,
        location: GoalRoutes.detail('g1'),
        until: byId('goal-add-savings'),
        seed: (app) async {
          await app.journal.putGoal(bike(targetDate: '2026-12-31'));
          await save(app, 25000, '2026-09-04'); // over 4 weeks ago
        },
      );
      expect(line(), findsOneWidget);
      expect(find.text('Target: Dec 31, 2026'), findsOneWidget);
    });

    testWidgets('a date that has passed: no line', (tester) async {
      await open(
        tester,
        location: GoalRoutes.detail('g1'),
        until: byId('goal-add-savings'),
        seed: (app) => app.journal.putGoal(bike(targetDate: '2026-10-01')),
      );
      expect(byId('goal-add-savings'), findsOneWidget);
      expect(line(), findsNothing);
      expect(find.textContaining('Target'), findsNothing);
    });

    testWidgets('no pace and no date: no line', (tester) async {
      await open(
        tester,
        location: GoalRoutes.detail('g1'),
        until: byId('goal-add-savings'),
        seed: (app) => app.journal.putGoal(bike()),
      );
      expect(line(), findsNothing);
    });

    testWidgets('over 52 weeks at this pace: no pace line', (tester) async {
      await open(
        tester,
        location: GoalRoutes.detail('g1'),
        until: byId('goal-add-savings'),
        seed: (app) async {
          await app.journal.putGoal(bike(target: 10000000));
          await save(app, 100, '2026-10-01');
        },
      );
      expect(line(), findsNothing);
    });

    testWidgets('reached: no line', (tester) async {
      await open(
        tester,
        location: GoalRoutes.detail('g1'),
        until: byId('goal-screen'),
        seed: (app) async {
          await app.journal.putGoal(
            bike(target: 10000, targetDate: '2026-12-31'),
          );
          await save(app, 10000, '2026-10-01');
        },
      );
      expect(line(), findsNothing);
    });
  });

  test('no guilt: the pace and the target pass the copy check, and never '
      'say behind, late, or what to do', () {
    final en = lookupAppLocalizations(const Locale('en'));
    final never = [
      r'\bbehind\b',
      r'\blate\b',
      r'\bonly\b',
      r'\bneed',
      r'\bmust\b',
      r'\bshould\b',
      r'\bhurry\b',
      r'\bfall(ing)?\b',
      r'\bcatch up\b',
      r'\b(on|off) track\b',
      r'\bmiss',
    ];
    final lines = [
      for (var n = 1; n <= goalPaceMaxWeeks; n++) en.goalPaceWeeks(n),
      en.goalTargetOn('Dec 31, 2026'),
      en.goalTargetDate,
      en.goalTargetDateRemove,
    ];
    expect(lines.first, 'About 1 week to go at this pace');
    expect(lines[11], 'About 12 weeks to go at this pace');
    for (final text in lines) {
      expect(findGuilt({'line': text}), isEmpty, reason: text);
      for (final p in never) {
        expect(
          RegExp(p, caseSensitive: false).hasMatch(text),
          isFalse,
          reason: '"$text" matches $p',
        );
      }
    }
  });
}
