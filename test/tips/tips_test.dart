import 'dart:convert' show jsonDecode;
import 'dart:io' show File;
import 'dart:ui' show Locale;

import 'package:flutter_test/flutter_test.dart';
import 'package:piggybow/l10n/gen/app_localizations.dart';
import 'package:piggybow/pig/pig_mood.dart' show rotatingLine;
import 'package:piggybow/tips/tips.dart';

String key(int tip) => 'tip${tip.toString().padLeft(2, '0')}';

void main() {
  group('the tip of the day: (dayOfYear - 1) mod 20', () {
    test('1 January is tip 1, 20 January tip 20, 21 January tip 1 again', () {
      expect(tipForDay(DateTime(2026, 1, 1)), 1);
      expect(tipForDay(DateTime(2026, 1, 20)), 20);
      expect(tipForDay(DateTime(2026, 1, 21)), 1);
    });

    test('2 December 2026 is day 336: tip 16', () => expect(tipForDay(DateTime(2026, 12, 2)), 16));

    test('31 December: day 365 in a common year (tip 5), 366 in a leap year (tip 6)', () {
      expect(tipForDay(DateTime(2026, 12, 31)), 5);
      expect(tipForDay(DateTime(2028, 12, 31)), 6);
    });

    test('only the date counts, not the time or the zone', () {
      expect(tipForDay(DateTime(2026, 3, 29, 23, 59)), tipForDay(DateTime(2026, 3, 29)));
      expect(tipForDay(DateTime.utc(2026, 10, 25, 0, 1)), tipForDay(DateTime(2026, 10, 25, 22)));
    });

    test('it agrees with the pig\'s rotation for every day of two years', () {
      final keys = [for (var t = 1; t <= tipCount; t++) key(t)];
      for (var d = DateTime.utc(2026); d.year < 2028; d = d.add(const Duration(days: 1))) {
        final iso = '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
        expect(key(tipForDay(d)), rotatingLine(keys, iso), reason: iso);
      }
    });
  });

  group('"Another idea"', () {
    test('steps forward and wraps from 20 to 1', () {
      expect(nextTip(1), 2);
      expect(nextTip(19), 20);
      expect(nextTip(20), 1);
    });

    test('20 steps visit every tip once and come back', () {
      var tip = 7;
      final seen = <int>{};
      for (var i = 0; i < tipCount; i++) {
        seen.add(tip);
        tip = nextTip(tip);
      }
      expect(seen.length, tipCount);
      expect(tip, 7);
    });

    test('a tip outside 1-20 is refused', () {
      for (final bad in [0, 21, -1]) {
        expect(() => nextTip(bad), throwsRangeError, reason: '$bad');
      }
    });
  });

  group('the texts', () {
    final l10n = lookupAppLocalizations(const Locale('en'));
    final arb = jsonDecode(File('lib/l10n/app_en.arb').readAsStringSync()) as Map<String, dynamic>;

    test('tip N shows key tipNN, for all 20', () {
      for (var t = 1; t <= tipCount; t++) {
        expect(tipText(l10n, t), arb[key(t)], reason: key(t));
      }
    });

    test('the 20 texts are distinct and none is empty', () {
      final texts = {for (var t = 1; t <= tipCount; t++) tipText(l10n, t)};
      expect(texts.length, tipCount);
      expect(texts.every((s) => s.trim().isNotEmpty), isTrue);
    });

    test('the first and the last read as the plan has them (§4.5)', () {
      expect(tipText(l10n, 1), "Before a non-essential buy, wait a day. If you still want it tomorrow, it's probably worth it.");
      expect(tipText(l10n, 20), 'Give your savings goal a name you love.');
    });

    test('a tip outside 1-20 is refused', () {
      expect(() => tipText(l10n, 0), throwsRangeError);
      expect(() => tipText(l10n, 21), throwsRangeError);
    });
  });
}
