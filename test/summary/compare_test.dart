import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piggybow/journal/category.dart';
import 'package:piggybow/journal/entry.dart';
import 'package:piggybow/l10n/gen/app_localizations.dart';
import 'package:piggybow/summary/compare.dart';
import 'package:piggybow/summary/summary.dart';

import '../../tool/no_guilt.dart' show findGuilt;
import '../helpers.dart';

/// Feature 13, gentle comparisons: in Summary's week, under each category, how
/// its spends compare with the week before, in words only. The current week
/// against the same days of last week ("this time last week"); a past week
/// against the whole week before. About the same within 15 %, else a bit more
/// or a bit less, however far. No line without spends to compare with; spends
/// only; weeks only.
void main() {
  group('the words', () {
    test('about the same within 15 %, either way', () {
      expect(compareSpends(100, 100), Comparison.same);
      expect(compareSpends(115, 100), Comparison.same);
      expect(compareSpends(85, 100), Comparison.same);
      expect(compareSpends(116, 100), Comparison.more);
      expect(compareSpends(84, 100), Comparison.less);
    });

    test('a bit more or a bit less, however far', () {
      expect(compareSpends(100000, 1), Comparison.more);
      expect(compareSpends(1, 100000), Comparison.less);
    });

    test('nothing to compare with: no words', () {
      expect(compareSpends(500, 0), isNull);
    });

    test('the largest amounts stay exact', () {
      const big = 999999999999999;
      expect(compareSpends(big, big), Comparison.same);
      expect(compareSpends(big, big ~/ 2), Comparison.more);
    });
  });

  group('the days it compares with', () {
    const week = Period(PeriodKind.week, '2026-09-28', '2026-10-04');

    test('this week, not over: the same days of last week', () {
      expect(
        comparedWith(week, '2026-10-02'),
        const Period(PeriodKind.week, '2026-09-21', '2026-09-25'),
      );
      expect(
        comparedWith(week, '2026-09-28'),
        const Period(PeriodKind.week, '2026-09-21', '2026-09-21'),
      );
      expect(
        comparedWith(week, '2026-10-04'),
        const Period(PeriodKind.week, '2026-09-21', '2026-09-27'),
      );
    });

    test('a past week: the whole week before', () {
      expect(
        comparedWith(week, '2026-10-20'),
        const Period(PeriodKind.week, '2026-09-21', '2026-09-27'),
      );
    });

    test('across a new year', () {
      const january = Period(PeriodKind.week, '2027-01-04', '2027-01-10');
      expect(
        comparedWith(january, '2027-01-05'),
        const Period(PeriodKind.week, '2026-12-28', '2026-12-29'),
      );
    });
  });

  group('the categories', () {
    SummaryEntry e(String type, int amount, String day, [String? category]) =>
        SummaryEntry(
          type: type,
          amountMinor: amount,
          category: category,
          localDate: day,
        );
    const before = Period(PeriodKind.week, '2026-09-21', '2026-09-25');

    test('spends only, in those days, by category', () {
      expect(
        spendsByCategory([
          e('spent', 100, '2026-09-21', 'food'),
          e('spent', 200, '2026-09-25', 'food'),
          e('spent', 400, '2026-09-26', 'food'), // after those days
          e('spent', 300, '2026-09-22', 'fun'),
          e('saved', 5000, '2026-09-22'),
          e('withdraw', 700, '2026-09-23'),
        ], before),
        {'food': 300, 'fun': 300},
      );
    });

    test("only the shown week's categories with something to compare", () {
      const week = Period(PeriodKind.week, '2026-09-28', '2026-10-04');
      expect(
        compareCategories(
          rows: const [
            CategoryRow('food', 1000, 50),
            CategoryRow('groceries', 1000, 50),
          ],
          entries: [
            e('spent', 1000, '2026-09-22', 'food'),
            e('spent', 700, '2026-09-23', 'health'),
          ],
          week: week,
          today: '2026-10-02',
        ),
        {'food': Comparison.same},
      );
    });
  });

  group('in Summary', () {
    // Tests run on Friday 2 October 2026 in Bangkok (helpers.dart): this
    // week is 28 September to 4 October, "this time last week" 21 to 25
    // September, and the week before last 14 to 20 September.
    Future<void> seed(TestApp app) async {
      Future<void> spend(int minor, SpendCategory c, String day) =>
          app.journal.addEntry(
            type: EntryType.spent,
            amountMinor: minor,
            currency: 'USD',
            localDate: day,
            category: c,
          );
      // This week.
      await spend(1000, SpendCategory.food, '2026-09-29');
      await spend(2000, SpendCategory.transport, '2026-09-30');
      await spend(300, SpendCategory.fun, '2026-10-01');
      await spend(500, SpendCategory.groceries, '2026-10-02');
      // Last week: Monday to Friday, then the weekend.
      await spend(1000, SpendCategory.food, '2026-09-22');
      await spend(1000, SpendCategory.transport, '2026-09-23');
      await spend(1000, SpendCategory.fun, '2026-09-24');
      await spend(700, SpendCategory.health, '2026-09-25');
      await spend(5000, SpendCategory.food, '2026-09-26');
      // The week before last.
      await spend(2000, SpendCategory.food, '2026-09-15');
      await spend(1000, SpendCategory.transport, '2026-09-16');
      await app.journal.addEntry(
        type: EntryType.saved,
        amountMinor: 9000,
        currency: 'USD',
        localDate: '2026-09-17',
      );
    }

    Future<void> open(WidgetTester tester) async {
      tester.view.devicePixelRatio = 3;
      tester.view.physicalSize = const Size(360 * 3, 1600 * 3);
      addTearDown(tester.view.reset);
      final app = TestApp(currency: 'USD');
      await tester.runAsync(app.openJournal);
      await tester.runAsync(() => seed(app));
      await app.pump(tester);
      await tester.tapId('tab-summary');
      for (var i = 0; i < 40 && byId('sum-by-category').evaluate().isEmpty; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      await tester.pumpAndSettle();
    }

    Finder line(String category) => byId('sum-cat-$category-compare');
    Finder says(String category, String text) =>
        find.descendant(of: line(category), matching: find.text(text));

    testWidgets('this week: against this time last week', (tester) async {
      await open(tester);
      // Food 1,000 against 1,000 (Saturday's 5,000 is after "this time").
      expect(
        says('food', 'About the same as this time last week'),
        findsOneWidget,
      );
      expect(
        says('transport', 'A bit more than this time last week'),
        findsOneWidget,
      );
      expect(
        says('fun', 'A bit less than this time last week'),
        findsOneWidget,
      );
      // New this week: nothing to compare with.
      expect(byId('sum-cat-groceries'), findsOneWidget);
      expect(line('groceries'), findsNothing);
      // Last week only: not this week's, so never mentioned.
      expect(byId('sum-cat-health'), findsNothing);
      expect(find.textContaining('last week'), findsNWidgets(3));
    });

    testWidgets('a past week: against the whole week before', (tester) async {
      await open(tester);
      await tester.tapId('sum-prev');
      // 21–27 September against 14–20: food 6,000 against 2,000, transport
      // 1,000 against 1,000; fun and health had nothing to compare with.
      expect(says('food', 'A bit more than last week'), findsOneWidget);
      expect(says('transport', 'About the same as last week'), findsOneWidget);
      expect(line('fun'), findsNothing);
      expect(line('health'), findsNothing);
      expect(find.textContaining('this time'), findsNothing);
    });

    testWidgets('a month: no comparisons', (tester) async {
      await open(tester);
      await tester.tapId('sum-month');
      expect(byId('sum-by-category'), findsOneWidget);
      expect(find.textContaining('last week'), findsNothing);
    });

    testWidgets('read out with its category', (tester) async {
      await open(tester);
      expect(
        tester.getSemantics(line('transport')),
        isSemantics(label: 'A bit more than this time last week'),
      );
    });
  });

  test('no guilt: the six lines pass the copy check, with no number, arrow, '
      'or judgement', () {
    final en = lookupAppLocalizations(const Locale('en'));
    final lines = [
      en.sumCompareMore,
      en.sumCompareLess,
      en.sumCompareSame,
      en.sumCompareMoreSoFar,
      en.sumCompareLessSoFar,
      en.sumCompareSameSoFar,
    ];
    final never = [
      r'\d',
      r'[↑↓▲▼←→%]',
      r'\bbetter\b',
      r'\bworse\b',
      r'\bgood\b',
      r'\bbad\b',
      r'\bwell done\b',
      r'\bcareful\b',
      r'\boverspen',
      r'\btoo\b',
      r'\bonly\b',
      r'\bshould\b',
      r'\bagain\b',
      r'\ba lot\b',
    ];
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
