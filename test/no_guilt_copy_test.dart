import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../tool/no_guilt.dart' show allowed, findGuilt, messageCount;

void main() {
  group('the scanner (controls)', () {
    test('catches every listed phrase, in any case', () {
      final arb = <String, Object?>{
        'a': 'You are Over Budget this week.',
        'b': 'You fell behind.',
        'c': 'You missed a day.',
        'd': 'Saving failed.',
        'e': 'You should save more.',
        'f': 'You overspent on food.',
        'g': 'That is over your plan.',
        'h': 'Shouldn’t have bought it.',
        'i': 'I should have waited.',
        'j': 'Keep your streak going!',
        'k': 'What a waste.',
        'l': 'Don’t feel guilty.',
        'm': 'No shame in that.',
        'n': 'That was too much.',
        'o': 'A bad habit.',
        'p': 'A careless spend.',
        'q': 'Don’t forget to note your day.',
        'r': 'You only saved a little.',
      };
      final hits = findGuilt(arb);
      for (final key in arb.keys) {
        // Exactly one pattern per control string, so each pattern is proven
        // on its own.
        expect(hits.where((h) => h.startsWith('$key:')).length, 1, reason: key);
      }
    });

    test('matches whole words only: no false positives', () {
      final arb = <String, Object?>{
        'a': 'Dismissed.',
        'b': 'Maybe later',
        'c': "Every happy thing, this week. I'm over the rainbow!",
        'd': 'Your week fits your plan so far.',
        'e': 'Behindthescenes',
        'f': 'Snoozing till your next note. No rush.',
        'g': 'Good to know. That’s how we learn.',
        'h': 'Not really',
        'i': 'Forgot PIN?',
        'j': 'Only on this phone.',
        'k': 'It can’t be undone.',
      };
      expect(findGuilt(arb), isEmpty);
    });

    test('skips metadata and non-string values', () {
      final arb = <String, Object?>{
        '@@locale': 'en',
        '@x': {'description': 'never say failed here either'},
        'x': 'Fine.',
      };
      expect(findGuilt(arb), isEmpty);
      expect(messageCount(arb), 1);
    });

    test('an allowed key is skipped; others are still caught', () {
      final arb = <String, Object?>{'a': 'Saving failed.', 'b': 'You missed it.'};
      final hits = findGuilt(arb, allow: {'a': 'test only'});
      expect(hits, hasLength(1));
      expect(hits.single, startsWith('b:'));
    });
  });

  test('app_en.arb holds no banned phrase', () {
    final arb = jsonDecode(File('lib/l10n/app_en.arb').readAsStringSync())
        as Map<String, Object?>;
    expect(messageCount(arb), greaterThan(0),
        reason: 'fail closed: no messages were read');
    expect(findGuilt(arb, allow: allowed), isEmpty);
  });
}
