// Fails on user-facing string literals in lib/ (decision 32: every text the
// user sees comes from the ARB files). Run: dart run tool/check_hardcoded_text.dart
// (CI runs it; test/no_hardcoded_text_test.dart runs the same check).
//
// It looks for a literal containing a letter in the places users read text:
// Text(...), TextSpan(text:), SnackBar content, and the label/hint/title/
// tooltip/semantics-label style parameters, and hand-written DateFormat
// patterns. A line ending in `// l10n-ignore`
// is exempt (e.g. language endonyms). Generated l10n code is skipped.
import 'dart:io';

// A letter in any script (\p{L}): Thai or Cyrillic literals count too.
final _literal = r'''(?:'[^'\n]*\p{L}[^'\n]*'|"[^"\n]*\p{L}[^"\n]*")''';

final _patterns = [
  RegExp(
    '\\b(?:Text|SelectableText|Tooltip|ButtonLabel)\\(\\s*$_literal',
    unicode: true,
  ),
  RegExp('\\bTextSpan\\([^)]*?\\btext:\\s*$_literal', unicode: true),
  RegExp(
    unicode: true,
    '\\b(?:labelText|hintText|helperText|errorText|counterText|prefixText|'
    'suffixText|tooltip|semanticsLabel|semanticLabel|message|'
    'title|subtitle|label|content|placeholder|'
    'confirmText|cancelText|helpText)\\s*:\\s*$_literal',
  ),
  // A hand-written date pattern fixes one region's order (decision 89): use
  // the DateFormat skeletons (yMMMMEEEEd …) with the session's dateLocale.
  RegExp('\\bDateFormat\\(\\s*$_literal', unicode: true),
];

/// Problems as `path:line: source`.
List<String> hardcodedText({String root = 'lib'}) {
  final problems = <String>[];
  final files = Directory(root)
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .where((f) => !f.path.replaceAll('\\', '/').contains('/l10n/gen/'));
  for (final file in files) {
    final lines = file.readAsLinesSync();
    // Join so a literal on the line after `Text(` is still caught; ignored
    // and comment lines are blanked first.
    final kept = [
      for (final line in lines)
        line.trimRight().endsWith('// l10n-ignore') ||
                line.trimLeft().startsWith('//')
            ? ''
            : line,
    ];
    final text = kept.join('\n');
    for (final pattern in _patterns) {
      for (final match in pattern.allMatches(text)) {
        if (!_hasWords(match.group(0)!)) continue;
        final lineNo = '\n'.allMatches(text.substring(0, match.start)).length;
        problems.add(
          '${file.path.replaceAll('\\', '/')}:${lineNo + 1}: '
          '${match.group(0)!.replaceAll(RegExp(r'\s+'), ' ')}',
        );
      }
    }
  }
  return problems;
}

/// The matched literal still has letters once `$x` / `${...}` interpolations
/// are removed (`Text('$hours')` is data, not copy).
bool _hasWords(String match) {
  final literal = RegExp(r'''('[^'\n]*'|"[^"\n]*")$''').firstMatch(match);
  final body = (literal?.group(0) ?? match)
      .replaceAll(RegExp(r'\$\{[^}]*\}'), '')
      .replaceAll(RegExp(r'\$\w+'), '');
  return RegExp(r'\p{L}', unicode: true).hasMatch(body);
}

void main() {
  final problems = hardcodedText();
  if (problems.isEmpty) {
    stdout.writeln('No hard-coded user-facing text in lib/');
    return;
  }
  stderr.writeln('User-facing text must come from lib/l10n/app_en.arb:');
  problems.forEach(stderr.writeln);
  exitCode = 1;
}
