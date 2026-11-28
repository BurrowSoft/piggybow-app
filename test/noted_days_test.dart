import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piggybow/core/clock.dart';
import 'package:piggybow/journal/category.dart';
import 'package:piggybow/journal/entry.dart';
import 'package:piggybow/l10n/gen/app_localizations.dart';
import 'package:piggybow/summary/noted_days.dart';
import 'package:piggybow/summary/summary.dart' show PeriodKind, periodContaining;

import '../tool/no_guilt.dart' show findGuilt;
import 'helpers.dart';

/// Feature 6, the days noted this week: in Home's This week card, "You noted
/// {count} days this week", counting the different days of this week (Monday
/// to Sunday, in the phone's zone) with any entry. Shown from 2 days; never a
/// word about the days without one, never a streak, never a reset.
void main() {
  // Tests run on Friday 2 October 2026, 08:30 in Bangkok (helpers.dart):
  // this week is Monday 28 September to Sunday 4 October.
  group('the count', () {
    final week = periodContaining(PeriodKind.week, '2026-10-02');

    test('each day once, however many entries it has', () {
      expect(notedDays(['2026-09-29', '2026-09-29', '2026-10-01'], week), 2);
    });

    test('this week only: Monday to Sunday', () {
      expect(notedDays(['2026-09-28', '2026-10-04'], week), 2);
      expect(notedDays(['2026-09-27', '2026-10-05'], week), 0);
    });

    test('nothing yet: 0', () {
      expect(notedDays(const [], week), 0);
    });
  });

  group("on Home's This week card", () {
    Future<void> openHome(
      WidgetTester tester,
      List<(EntryType, String)> entries, {
      Clock? clock,
    }) async {
      tester.view.devicePixelRatio = 3;
      tester.view.physicalSize = const Size(360 * 3, 1600 * 3);
      addTearDown(tester.view.reset);
      final app = TestApp(clock: clock);
      await tester.runAsync(app.openJournal);
      await tester.runAsync(() async {
        for (final (type, day) in entries) {
          await app.journal.addEntry(
            type: type,
            amountMinor: 500,
            currency: 'THB',
            localDate: day,
            category: type == EntryType.spent ? SpendCategory.food : null,
          );
        }
      });
      await app.pump(tester);
      // The journal answers over a few frames.
      for (var i = 0; i < 40 && byId('home-idea').evaluate().isEmpty; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      await tester.pumpAndSettle();
    }

    const spent = EntryType.spent;
    const saved = EntryType.saved;
    Finder line() => byId('home-week-noted');

    testWidgets('from 2 days: "You noted 2 days this week"', (tester) async {
      await openHome(tester, [(spent, '2026-09-28'), (saved, '2026-09-30')]);
      expect(line(), findsOneWidget);
      expect(find.text('You noted 2 days this week'), findsOneWidget);
    });

    testWidgets('a day with several entries counts once', (tester) async {
      await openHome(tester, [
        (spent, '2026-09-29'),
        (spent, '2026-09-29'),
        (saved, '2026-09-29'),
        (spent, '2026-10-01'),
      ]);
      expect(find.text('You noted 2 days this week'), findsOneWidget);
    });

    testWidgets('any entry counts: saves alone make days too', (tester) async {
      await openHome(tester, [(saved, '2026-09-28'), (saved, '2026-10-02')]);
      expect(find.text('You noted 2 days this week'), findsOneWidget);
    });

    testWidgets('below 2 days: no line', (tester) async {
      // One day this week (three entries), and last Sunday's, not this week.
      await openHome(tester, [
        (spent, '2026-09-27'),
        (spent, '2026-10-02'),
        (spent, '2026-10-02'),
        (saved, '2026-10-02'),
      ]);
      expect(byId('home-week'), findsOneWidget);
      expect(line(), findsNothing);
      expect(find.textContaining('You noted'), findsNothing);
    });

    testWidgets('no entries: no line', (tester) async {
      await openHome(tester, const []);
      expect(line(), findsNothing);
    });

    testWidgets('a whole week: 7 days', (tester) async {
      await openHome(tester, [
        for (final d in [28, 29, 30]) (spent, '2026-09-$d'),
        for (final d in [1, 2, 3, 4]) (spent, '2026-10-0$d'),
      ], clock: Clock(fixed: DateTime.parse('2026-10-04T12:00:00+07:00')));
      expect(find.text('You noted 7 days this week'), findsOneWidget);
    });

    group("the week is the phone's (Bangkok), Monday first", () {
      final days = [
        (spent, '2026-09-29'),
        (spent, '2026-09-30'),
        (saved, '2026-10-01'),
      ];

      testWidgets('Sunday 23:59 in Bangkok: still this week', (tester) async {
        await openHome(
          tester,
          days,
          clock: Clock(fixed: DateTime.utc(2026, 10, 4, 16, 59)),
        );
        expect(find.text('You noted 3 days this week'), findsOneWidget);
      });

      testWidgets('Monday 00:00 in Bangkok (still Sunday in UTC): a new week, '
          'no line', (tester) async {
        await openHome(
          tester,
          days,
          clock: Clock(fixed: DateTime.utc(2026, 10, 4, 17)),
        );
        expect(byId('home-week'), findsOneWidget);
        expect(line(), findsNothing);
      });
    });
  });

  test('no guilt: for 2 to 7 days, the line passes the copy check and names '
      'no missed day, streak or reset', () {
    final en = lookupAppLocalizations(const Locale('en'));
    final never = [
      r'\bstreaks?\b',
      r'\bmiss',
      r'\breset',
      r'\bstart(ing)? over\b',
      r'\bin a row\b',
      r'\bonly\b',
      r'\bagain\b',
      r'\bbreak',
      r'\blost\b',
      r'\bskip',
      r'\bout of\b',
      r'\bof 7\b',
    ];
    for (var n = 2; n <= 7; n++) {
      final text = en.weekNotedDays(n);
      expect(text, 'You noted $n days this week');
      expect(findGuilt({'weekNotedDays': text}), isEmpty, reason: text);
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
