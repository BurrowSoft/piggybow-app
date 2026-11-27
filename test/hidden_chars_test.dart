import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../tool/check_hidden_chars.dart';

/// Decision 37's check. Every test string is built from code points, so this
/// file itself holds no hidden character.
String c(int codePoint) => String.fromCharCode(codePoint);

void main() {
  test('each hidden character fails, with its line and column', () {
    final text = [
      'a${c(0x202E)}b', // right-to-left override
      '${c(0x2066)}cd', // left-to-right isolate
      'ef${c(0x200B)}', // zero-width space
      'g${c(0x200C)}h${c(0x200D)}i${c(0x2060)}', // non-joiner, joiner, word joiner
      'j${c(0x00A0)}k${c(0x202F)}l', // no-break spaces outside a translation file
      'm${c(0xFEFF)}n', // a byte order mark inside a file
    ].join('\n');
    expect(scanText('lib/a.dart', text), [
      'lib/a.dart:1:2 U+202E',
      'lib/a.dart:2:1 U+2066',
      'lib/a.dart:3:3 U+200B',
      'lib/a.dart:4:2 U+200C',
      'lib/a.dart:4:4 U+200D',
      'lib/a.dart:4:6 U+2060',
      'lib/a.dart:5:2 U+00A0',
      'lib/a.dart:5:4 U+202F',
      'lib/a.dart:6:2 U+FEFF',
    ]);
  });

  test('every bidi control of the two ranges fails', () {
    for (final cp in [
      for (var i = 0x202A; i <= 0x202E; i++) i,
      for (var i = 0x2066; i <= 0x2069; i++) i,
    ]) {
      expect(scanText('README.md', 'x${c(cp)}'), hasLength(1), reason: '$cp');
    }
  });

  test('direction marks, separators and the soft hyphen fail everywhere', () {
    // Left-to-right, right-to-left and Arabic letter marks; the line and
    // paragraph separators; the soft hyphen. Not even a translation may
    // hold them.
    for (final cp in [0x200E, 0x200F, 0x061C, 0x2028, 0x2029, 0x00AD]) {
      expect(scanText('README.md', 'x${c(cp)}'), hasLength(1), reason: '$cp');
      expect(
        scanText('lib/l10n/app_th.arb', 'x${c(cp)}'),
        hasLength(1),
        reason: 'in a translation: $cp',
      );
    }
  });

  test('a leading byte order mark fails unless the format needs one', () {
    expect(scanText('a.csv', '${c(0xFEFF)}a,b'), ['a.csv:1:1 U+FEFF']);
    expect(leadingBomAllowed, isEmpty, reason: 'none needed today');
  });

  test('translation files hold only their listed characters', () {
    final fr = 'Oui${c(0x00A0)}? Non${c(0x202F)}!';
    expect(scanText('lib/l10n/app_fr.arb', fr), isEmpty);
    // The zero-width space only in Thai.
    final th = 'ab${c(0x200B)}cd';
    expect(scanText('lib/l10n/app_th.arb', th), isEmpty);
    expect(scanText('lib/l10n/app_fr.arb', th), [
      'lib/l10n/app_fr.arb:1:3 U+200B',
    ]);
    // A bidi control never, not even in a translation.
    expect(scanText('lib/l10n/app_th.arb', 'a${c(0x202B)}b'), [
      'lib/l10n/app_th.arb:1:2 U+202B',
    ]);
    // Only lib/l10n's ARBs are translation files.
    expect(scanText('docs/app_fr.arb', fr), hasLength(2));
    expect(scanText('lib/l10n/notes.md', fr), hasLength(2));
  });

  test('escapes and visible characters pass', () {
    final backslash = c(92);
    final escaped = "'1${backslash}u00A0234 ${backslash}u202E'";
    expect(scanText('lib/a.dart', escaped), isEmpty);
    expect(scanText('lib/a.dart', "₽ ’ – — · … ฿ 😀 ${c(0x0E01)}"), isEmpty);
  });

  test('binary files are skipped', () {
    final dir = Directory.systemTemp.createTempSync('hidden_chars');
    addTearDown(() => dir.deleteSync(recursive: true));
    final png = File('${dir.path}/a.png')
      ..writeAsBytesSync([0x89, 0x50, 0, 0xE2, 0x80, 0xAE]);
    expect(scanFile(png.path), isEmpty);
    final text = File('${dir.path}/a.txt')..writeAsStringSync('a${c(0x202E)}');
    expect(scanFile(text.path), hasLength(1));
  });

  test('the repo has none', () {
    final files = trackedFiles();
    expect(files, isNotNull);
    expect(files!.length, greaterThan(100), reason: 'git listed the repo');
    expect([
      for (final f in files)
        if (File(f).existsSync()) ...scanFile(f),
    ], isEmpty);
  });
}
