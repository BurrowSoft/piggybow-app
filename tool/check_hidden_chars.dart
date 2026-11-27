import 'dart:convert';
import 'dart:io';

/// Decision 37: no hidden characters in the source. It fails on bidi
/// controls (U+202A–202E, U+2066–2069) and direction marks (U+200E, U+200F,
/// U+061C), which can make code read differently from how it runs; on
/// zero-width or invisible characters (U+200B–200D, U+2060, U+FEFF); and on
/// the line and paragraph separators (U+2028, U+2029) and the soft hyphen
/// (U+00AD); in every file git tracks: code, config, workflows, docs.
/// The no-break spaces U+00A0 and U+202F fail too, except in translation
/// files, which may hold only the characters listed for them below. Where a
/// string needs one of these, write it as an escape (backslash, u, 4 hex
/// digits) or build it from its code point.
///
/// Exit 0 when clean; 1 with each hit as `path:line:column U+XXXX`; 2 when git
/// can't list the files.
void main() {
  final files = trackedFiles();
  if (files == null || files.isEmpty) {
    stderr.writeln('git ls-files failed or listed nothing');
    exit(2);
  }
  final hits = [
    for (final f in files)
      if (File(f).existsSync()) ...scanFile(f),
  ];
  if (hits.isEmpty) {
    stdout.writeln('no hidden characters in ${files.length} tracked files');
    return;
  }
  hits.forEach(stdout.writeln);
  stdout.writeln(
    '${hits.length} hidden characters (decision 37): write each as an escape',
  );
  exit(1);
}

/// The characters that fail (anywhere a file doesn't allow them).
const hidden = <int>{
  // Bidi embeddings, overrides and isolates.
  0x202A, 0x202B, 0x202C, 0x202D, 0x202E, 0x2066, 0x2067, 0x2068, 0x2069,
  // Direction marks: left-to-right, right-to-left, Arabic letter.
  0x200E, 0x200F, 0x061C,
  // Zero width: space, non-joiner, joiner, word joiner, no-break space (BOM).
  0x200B, 0x200C, 0x200D, 0x2060, 0xFEFF,
  // Line and paragraph separators; the soft hyphen.
  0x2028, 0x2029, 0x00AD,
  // No-break spaces, allowed only in translation files.
  0x00A0, 0x202F,
};

/// What a translation file may hold, each character listed: the fr/de
/// no-break spaces, and in Thai the zero-width space for line breaks.
Set<int> allowedIn(String path) {
  if (!RegExp(r'^lib/l10n/app_[A-Za-z_]+\.arb$').hasMatch(path)) return {};
  return {0x00A0, 0x202F, if (path == 'lib/l10n/app_th.arb') 0x200B};
}

/// Files whose format needs a leading byte order mark (none today).
const leadingBomAllowed = <String>{};

/// Each hidden character in [text] (the contents of [path]).
List<String> scanText(String path, String text) {
  final allowed = allowedIn(path);
  final hits = <String>[];
  var line = 1;
  var column = 0;
  var first = true;
  for (final rune in text.runes) {
    final atStart = first;
    first = false;
    if (rune == 0x0A) {
      line++;
      column = 0;
      continue;
    }
    column++;
    if (!hidden.contains(rune) || allowed.contains(rune)) continue;
    if (rune == 0xFEFF && atStart && leadingBomAllowed.contains(path)) continue;
    final code = rune.toRadixString(16).toUpperCase().padLeft(4, '0');
    hits.add('$path:$line:$column U+$code');
  }
  return hits;
}

/// [scanText] on a file; binary files (a NUL byte, or not UTF-8) are skipped.
List<String> scanFile(String path) {
  final bytes = File(path).readAsBytesSync();
  if (bytes.contains(0)) return const [];
  final String text;
  try {
    text = utf8.decode(bytes);
  } on FormatException {
    return const [];
  }
  return scanText(path, text);
}

/// Every file git tracks, relative to the repo root; null if git fails.
List<String>? trackedFiles() {
  final result = Process.runSync('git', [
    'ls-files',
    '-z',
  ], stdoutEncoding: utf8);
  if (result.exitCode != 0) return null;
  return (result.stdout as String)
      .split(String.fromCharCode(0))
      .where((p) => p.isNotEmpty)
      .toList();
}
