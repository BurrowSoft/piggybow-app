// Checks that every shipped ARB file has exactly the template's keys, no
// empty values and the same {placeholders}. Run: dart run tool/check_l10n.dart
// (CI runs it; test/l10n_parity_test.dart runs the same check).
import 'dart:convert';
import 'dart:io';

/// Shipped locales = the ARB files present, English (the template) first.
List<String> shippedLocales({String dir = arbDir}) {
  final codes = [
    for (final f in Directory(dir).listSync())
      if (RegExp(r'^app_(\w+)\.arb$').firstMatch(f.uri.pathSegments.last)
          case final m?)
        m.group(1)!,
  ]..sort();
  return ['en', ...codes.where((c) => c != 'en')];
}

const arbDir = 'lib/l10n';

/// Keys whose value is legitimately the same in every language (the brand,
/// "AI", format-only strings) carry `"x-same-in-all-locales": true` in their
/// @metadata in the template. Any other non-English value equal to the
/// English one is treated as untranslated, unless that locale's own ARB marks
/// the key `"x-same-as-en": true` (a loanword there: "Stress", "Insights").
const sameMarker = 'x-same-in-all-locales';
const sameAsEnMarker = 'x-same-as-en';

List<String> l10nProblems({String dir = arbDir}) {
  final problems = <String>[];
  Map<String, String> load(String locale) {
    final json = jsonDecode(
      File('$dir/app_$locale.arb').readAsStringSync(),
    ) as Map<String, dynamic>;
    return {
      for (final e in json.entries)
        if (!e.key.startsWith('@')) e.key: e.value as String,
    };
  }

  // Simple {name} placeholders (for keys without metadata).
  Set<String> placeholders(String s) =>
      RegExp(r'\{(\w+)\}').allMatches(s).map((m) => m.group(1)!).toSet();

  final locales = shippedLocales(dir: dir);
  final template = load(locales.first);
  final templateRaw = jsonDecode(
    File('$dir/app_${locales.first}.arb').readAsStringSync(),
  ) as Map<String, dynamic>;
  final sameInEveryLocale = {
    for (final e in templateRaw.entries)
      if (e.key.startsWith('@') &&
          e.value is Map &&
          (e.value as Map)[sameMarker] == true)
        e.key.substring(1),
  };
  for (final locale in locales) {
    // jsonDecode keeps the last of a repeated key without a word.
    final text = File('$dir/app_$locale.arb').readAsStringSync();
    for (final key in duplicateTopLevelKeys(text)) {
      problems.add('$locale: "$key" appears more than once');
    }
    final arb = load(locale);
    final sameHere = {
      for (final e in (jsonDecode(text) as Map<String, dynamic>).entries)
        if (e.key.startsWith('@') &&
            e.value is Map &&
            (e.value as Map)[sameAsEnMarker] == true)
          e.key.substring(1),
    };
    for (final key in template.keys.where((k) => !arb.containsKey(k))) {
      problems.add('$locale: missing "$key"');
    }
    for (final key in arb.keys.where((k) => !template.containsKey(k))) {
      problems.add('$locale: "$key" is not in the template (app_en.arb)');
    }
    for (final MapEntry(:key, :value) in arb.entries) {
      if (value.trim().isEmpty) problems.add('$locale: "$key" is empty');
      final expected = template[key];
      if (locale != locales.first &&
          value == expected &&
          !sameInEveryLocale.contains(key) &&
          !sameHere.contains(key)) {
        problems.add('$locale: "$key" is the English text (untranslated?)');
      }
      if (expected == null) continue;
      // The template's declared placeholders are the real ones: an ICU
      // message's branch texts ({week}) and plural cases (=1{1 day}) are
      // not, and a translation may legitimately drop them (Thai has no
      // plural forms). Without metadata, the simple {name} ones count.
      final declared = ((templateRaw['@$key'] as Map?)?['placeholders'] as Map?)
          ?.keys
          .cast<String>()
          .toSet();
      if (declared != null && declared.isNotEmpty) {
        final lost = declared.where((p) => !value.contains('{$p'));
        if (lost.isNotEmpty) {
          problems.add('$locale: "$key" lost placeholders ${lost.join(', ')}');
        }
      } else if (!_sameSet(placeholders(expected), placeholders(value))) {
        problems.add('$locale: "$key" placeholders differ from en');
      }
    }
  }
  return problems;
}

/// The top-level keys of a JSON object [text] that occur more than once, in
/// order of their second occurrence.
List<String> duplicateTopLevelKeys(String text) {
  final seen = <String>{};
  final dupes = <String>[];
  var depth = 0;
  for (var i = 0; i < text.length; i++) {
    final c = text[i];
    if (c == '{' || c == '[') {
      depth++;
    } else if (c == '}' || c == ']') {
      depth--;
    } else if (c == '"') {
      final start = i + 1;
      for (i = start; text[i] != '"'; i++) {
        if (text[i] == r'\') i++;
      }
      final key = jsonDecode(text.substring(start - 1, i + 1)) as String;
      var j = i + 1;
      while (j < text.length && text[j].trim().isEmpty) {
        j++;
      }
      if (depth == 1 && j < text.length && text[j] == ':' && !seen.add(key)) {
        dupes.add(key);
      }
    }
  }
  return dupes;
}

bool _sameSet(Set<String> a, Set<String> b) =>
    a.length == b.length && a.containsAll(b);

void main() {
  final problems = l10nProblems();
  if (problems.isEmpty) {
    stdout.writeln('l10n: ${shippedLocales().join(", ")} in parity');
    return;
  }
  problems.forEach(stderr.writeln);
  exitCode = 1;
}
