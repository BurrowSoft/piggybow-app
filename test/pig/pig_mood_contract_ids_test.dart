import 'dart:convert' show jsonDecode;
import 'dart:io' show File;

import 'package:flutter_test/flutter_test.dart';

/// The mood contract's case ids (test/contracts/pig_mood_cases.json) read as
/// `C<number>` or `C<number><letter>`. Down the file the numbers increase and
/// never repeat, and a number's lettered variants run a, b, c… in order
/// (C22a, C22b). Gaps are allowed: a branch can reserve its numbers before it
/// lands. Two branches giving the same number to different cases fail here,
/// whatever order they land in.
final _id = RegExp(r'^C([1-9][0-9]*)([a-z]?)$');

/// What's wrong with [ids], in file order; empty when they read as above.
List<String> idOrderProblems(List<String> ids) {
  final problems = <String>[];
  final seen = <int>{};
  var lastNumber = 0;
  String? lastLetter;
  for (final id in ids) {
    final match = _id.firstMatch(id);
    if (match == null) {
      problems.add('$id: not C<number> or C<number><letter>');
      continue;
    }
    final number = int.parse(match.group(1)!);
    final letter = match.group(2)!;
    if (number == lastNumber) {
      // Another variant of the same number: lettered, and the next letter.
      final next = (lastLetter == null || lastLetter.isEmpty)
          ? null
          : String.fromCharCode(lastLetter.codeUnitAt(0) + 1);
      if (letter.isEmpty || next == null || letter != next) {
        problems.add('$id after C$lastNumber${lastLetter ?? ''}');
      }
    } else {
      if (number < lastNumber) {
        problems.add('$id after C$lastNumber: numbers must increase');
      }
      if (!seen.add(number)) problems.add('$id: C$number used twice');
      if (letter.isNotEmpty && letter != 'a') {
        problems.add('$id: a lettered case starts at a');
      }
    }
    lastNumber = number;
    lastLetter = letter;
  }
  return problems;
}

void main() {
  test('the contract\'s case ids increase, never repeat a number, and run a, b… within one', () {
    final contract = jsonDecode(
      File('test/contracts/pig_mood_cases.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    final ids = [
      for (final c in (contract['cases'] as List).cast<Map<String, dynamic>>())
        c['id'] as String,
    ];
    expect(ids, isNotEmpty);
    expect(idOrderProblems(ids), isEmpty);
  });

  group('the check itself', () {
    test('passes good ids, gaps included', () {
      expect(idOrderProblems(['C1', 'C2', 'C22a', 'C22b', 'C33']), isEmpty);
      expect(idOrderProblems(['C1', 'C33', 'C38', 'C39']), isEmpty);
    });
    test('fails a number used twice (two branches, one number)', () {
      expect(idOrderProblems(['C1', 'C34', 'C35', 'C34']), isNotEmpty);
      expect(idOrderProblems(['C1', 'C1']), isNotEmpty);
    });
    test('fails numbers going down', () {
      expect(idOrderProblems(['C1', 'C3', 'C2']), isNotEmpty);
    });
    test('fails letters that skip or don\'t start at a', () {
      expect(idOrderProblems(['C1', 'C2b']), isNotEmpty);
      expect(idOrderProblems(['C1', 'C2a', 'C2c']), isNotEmpty);
      expect(idOrderProblems(['C2', 'C2a']), isNotEmpty);
    });
    test('fails an id of another shape', () {
      expect(idOrderProblems(['X1']), isNotEmpty);
      expect(idOrderProblems(['C01']), isNotEmpty);
    });
  });
}
