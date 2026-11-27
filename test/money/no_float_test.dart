// The money path is integers only (plan §0.1; floating point there is BLOCKING). This reads the
// source of the money paths (lib/money, lib/export, lib/pig), comments and strings
// removed, and fails on anything that brings floating point in. The oracle in format_test.dart is
// the only place a fraction is computed.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

final _banned = <String, RegExp>{
  'the double type': RegExp(r'\bdouble\b'),
  'the num type (can hold a fraction)': RegExp(r'\bnum\b'),
  'toDouble()': RegExp(r'\btoDouble\b'),
  'division with /': RegExp(r'(?<![~/*])/(?![/*=])'),
  '/=': RegExp(r'(?<!~)/='),
  'round()': RegExp(r'\.round\('),
  'toStringAsFixed()': RegExp(r'\.toStringAsFixed\('),
  'pow()': RegExp(r'\bpow\('),
  'parsing a fraction': RegExp(r'\b(?:double|num)\.(?:try)?[pP]arse\b'),
};

/// The source without comments or string contents, so a slash in a comment or a URL in a
/// string can't trip the scan (strings are replaced by "" before checking).
String codeOnly(String source) => source
    .replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '')
    .replaceAll(RegExp(r"r?'(?:[^'\\\n]|\\.)*'"), "''")
    .replaceAll(RegExp(r'r?"(?:[^"\\\n]|\\.)*"'), '""')
    .split('\n')
    .map((line) {
      final i = line.indexOf('//');
      return i >= 0 ? line.substring(0, i) : line;
    })
    .join('\n');

void main() {
  final files = [
    for (final dir in ['lib/money', 'lib/export', 'lib/pig'])
      ...Directory(dir).listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart')),
  ];

  test('the scan finds the money and export code', () {
    expect(files.map((f) => f.uri.pathSegments.last), containsAll(['currency.dart', 'money.dart', 'csv_export.dart', 'pig_mood.dart']));
  });

  test('no floating point on any money path', () {
    for (final file in files) {
      final code = codeOnly(file.readAsStringSync());
      for (final entry in _banned.entries) {
        final hit = entry.value.firstMatch(code);
        expect(hit, isNull, reason: '${file.path}: ${entry.key} near "${hit == null ? '' : code.substring(hit.start, (hit.end + 20).clamp(0, code.length))}"');
      }
    }
  });

  test('the scan itself catches each banned form (control)', () {
    const samples = [
      'final x = 1.5 as double;',
      'num total = 0;',
      'a.toDouble()',
      'final y = minor / 100;',
      'y /= 2;',
      'x.round()',
      'x.toStringAsFixed(2)',
      'pow(10, 2)',
      'double.parse(t)',
    ];
    for (final s in samples) {
      final code = codeOnly(s);
      expect(_banned.values.any((r) => r.hasMatch(code)), isTrue, reason: s);
    }
    // Integer division, comments and strings are fine.
    for (final s in ['a ~/ b', '// a / b', "'a/b'", 'x ~/= 2;']) {
      final code = codeOnly(s);
      expect(_banned.values.any((r) => r.hasMatch(code)), isFalse, reason: s);
    }
  });
}
