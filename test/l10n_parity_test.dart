import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../tool/check_l10n.dart';

void main() {
  test('every ARB file has the same keys and placeholders', () {
    expect(shippedLocales(), ['en']);
    expect(l10nProblems(), isEmpty);
  });

  test('x-same-as-en lets one locale keep one English word', () {
    final dir = Directory.systemTemp.createTempSync('l10n');
    addTearDown(() => dir.deleteSync(recursive: true));
    File('${dir.path}/app_en.arb').writeAsStringSync(
      jsonEncode({'stress': 'Stress', 'hello': 'Hello'}),
    );
    File('${dir.path}/app_de.arb').writeAsStringSync(
      jsonEncode({
        'stress': 'Stress',
        '@stress': {'x-same-as-en': true},
        'hello': 'Hallo',
      }),
    );
    File('${dir.path}/app_fr.arb').writeAsStringSync(
      jsonEncode({'stress': 'Stress', 'hello': 'Bonjour'}),
    );
    expect(l10nProblems(dir: dir.path), [
      'fr: "stress" is the English text (untranslated?)',
    ]);
  });

  test('a key marked x-same-in-all-locales may equal English; others not', () {
    final dir = Directory.systemTemp.createTempSync('l10n');
    addTearDown(() => dir.deleteSync(recursive: true));
    File('${dir.path}/app_en.arb').writeAsStringSync(
      jsonEncode({
        'brand': 'Piggybow',
        '@brand': {'x-same-in-all-locales': true},
        'hello': 'Hello',
      }),
    );
    File('${dir.path}/app_th.arb')
        .writeAsStringSync(jsonEncode({'brand': 'Piggybow', 'hello': 'Hello'}));
    expect(l10nProblems(dir: dir.path), [
      'th: "hello" is the English text (untranslated?)',
    ]);
  });

  test('a key repeated at the top level is a problem (jsonDecode hides it)', () {
    final dir = Directory.systemTemp.createTempSync('l10n');
    addTearDown(() => dir.deleteSync(recursive: true));
    File('${dir.path}/app_en.arb').writeAsStringSync(
      '{"hello": "Hello", "@hello": {"hello": "nested, not a duplicate"},'
      ' "bye": "Bye \\"x\\"", "hello": "Hello"}',
    );
    File('${dir.path}/app_th.arb').writeAsStringSync(
      jsonEncode({'hello': 'สวัสดี', 'bye': 'ลาก่อน "x"'}),
    );
    expect(l10nProblems(dir: dir.path), ['en: "hello" appears more than once']);
  });
}
