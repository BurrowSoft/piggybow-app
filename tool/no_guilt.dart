// The no-guilt copy check: no user-facing English string may judge, blame or
// pressure. Dependency-free (dart:convert and dart:io only), so CI can run it
// before the Flutter tests.
//
// Usage: dart run tool/no_guilt.dart [path/to/app_en.arb]
// Exit codes: 0 = clean, 1 = banned phrases found (each hit listed),
//             2 = the file is missing or holds no messages (fails closed).
import 'dart:convert';
import 'dart:io';

/// A banned pattern and the reason it's banned. Patterns are matched
/// case-insensitively and on word boundaries, so "dismissed" never matches
/// "missed" and "later" never matches "late".
class Banned {
  const Banned(this.pattern, this.why);

  final String pattern;
  final String why;

  RegExp get regExp => RegExp(pattern, caseSensitive: false);
}

/// Apostrophes: ASCII ' and the typographic ’ are both matched.
const List<Banned> bannedPhrases = [
  Banned(r'\bover budget\b', 'judges a spend'),
  Banned(r'\bbehind\b', 'implies being late on money'),
  Banned(r'\bmissed\b', 'counts what was not done'),
  Banned(r'\bfail(s|ed|ing|ure|ures)?\b', 'failure language'),
  Banned(r'\byou should\b', 'tells the person what to do'),
  Banned(r'\boverspen(t|d|ds|ding)\b', 'judges a spend'),
  Banned(r'\bover (your|the|my) (plan|budget|limit)\b', 'judges a spend against a plan'),
  Banned(r"\bshould(n['’]t)? have\b", 'hindsight blame'),
  Banned(r'\bstreaks?\b', 'no streaks'),
  Banned(r'\bwast(e|ed|es|ing|eful)\b', 'judges a spend'),
  Banned(r'\bguilt(y)?\b', 'guilt'),
  Banned(r'\b(shame|shameful|ashamed)\b', 'shame'),
  Banned(r'\btoo much\b', 'judges a spend'),
  Banned(r'\bbad (habit|habits|spend|spends|spending|choice|choices)\b', 'judges the person'),
  Banned(r'\b(irresponsible|careless|reckless)\b', 'judges the person'),
  Banned(r"\bdon['’]t forget\b", 'a nag'),
  Banned(r'\byou only\b', 'a nag ("you only saved…")'),
];

/// Message keys exempt from the scan, each with its reason. Empty on purpose:
/// an entry needs the product owner's OK in the PR that adds it.
const Map<String, String> allowed = {};

/// Every banned-phrase hit in [arb], an ARB map. Metadata keys ("@…",
/// "@@locale") and non-string values are skipped.
List<String> findGuilt(
  Map<String, Object?> arb, {
  List<Banned> banned = bannedPhrases,
  Map<String, String> allow = const {},
}) {
  final hits = <String>[];
  for (final entry in arb.entries) {
    final key = entry.key;
    final value = entry.value;
    if (key.startsWith('@') || value is! String || allow.containsKey(key)) {
      continue;
    }
    for (final b in banned) {
      final match = b.regExp.firstMatch(value);
      if (match != null) {
        hits.add('$key: "$value" (matched "${match[0]}": ${b.why})');
      }
    }
  }
  return hits;
}

/// The number of messages (non-metadata string entries) in [arb].
int messageCount(Map<String, Object?> arb) => arb.entries
    .where((e) => !e.key.startsWith('@') && e.value is String)
    .length;

void main(List<String> args) {
  final path = args.isNotEmpty ? args.first : 'lib/l10n/app_en.arb';
  final file = File(path);
  if (!file.existsSync()) {
    stderr.writeln('no-guilt check: $path not found');
    exit(2);
  }
  final Object? decoded;
  try {
    decoded = jsonDecode(file.readAsStringSync());
  } on FormatException catch (e) {
    stderr.writeln('no-guilt check: $path is not valid JSON (${e.message})');
    exit(2);
  }
  if (decoded is! Map<String, Object?>) {
    stderr.writeln('no-guilt check: $path is not a JSON object');
    exit(2);
  }
  final arb = decoded;
  final count = messageCount(arb);
  if (count == 0) {
    stderr.writeln('no-guilt check: no messages read from $path (failing closed)');
    exit(2);
  }
  final hits = findGuilt(arb, allow: allowed);
  if (hits.isEmpty) {
    stdout.writeln('no-guilt check: $count messages, 0 hits');
    return;
  }
  stderr.writeln('no-guilt check: ${hits.length} hit(s) in $path');
  for (final hit in hits) {
    stderr.writeln('  $hit');
  }
  exit(1);
}
