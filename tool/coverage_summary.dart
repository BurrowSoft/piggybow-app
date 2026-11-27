// Line coverage from coverage/lcov.info: the total (generated l10n excluded)
// and every critical-path file, as a Markdown table (CI writes it to the job
// summary). No threshold: it reports, it doesn't fail.
//
//   dart run tool/coverage_summary.dart [coverage/lcov.info]
import 'dart:io';

/// The 1.0 critical paths (UX, 2026-10-20): crisis matcher + safety card,
/// offline sync + conflicts, export, delete account, reminder rules, the AI
/// client, app lock.
const critical = [
  'lib/features/safety/',
  'lib/core/user_store.dart',
  'lib/features/today/today_controller.dart',
  'lib/features/entry/',
  'lib/data/journal.dart',
  'lib/data/supabase_backend.dart',
  'lib/data/export_text.dart',
  'lib/features/me/export_',
  'lib/features/me/delete_account_dialog.dart',
  'lib/features/reminder/',
  'lib/features/reflect/',
  'lib/features/me/me_ai_section.dart',
  'lib/features/lock/',
];

void main(List<String> args) {
  final path = args.isEmpty ? 'coverage/lcov.info' : args.first;
  final files = <String, (int, int)>{}; // file → (hit, found)
  String? current;
  var hit = 0, found = 0;
  for (final line in File(path).readAsLinesSync()) {
    if (line.startsWith('SF:')) {
      current = line.substring(3).replaceAll(r'\', '/');
      final i = current.indexOf('lib/');
      if (i > 0) current = current.substring(i);
      hit = found = 0;
    } else if (line.startsWith('DA:')) {
      found++;
      if (!line.endsWith(',0')) hit++;
    } else if (line == 'end_of_record' && current != null) {
      files[current] = (hit, found);
    }
  }

  String pct(int h, int f) =>
      f == 0 ? 'n/a' : '${(100 * h / f).toStringAsFixed(1)}%';

  var th = 0, tf = 0;
  for (final MapEntry(key: f, value: (h, n)) in files.entries) {
    if (f.startsWith('lib/l10n/')) continue;
    th += h;
    tf += n;
  }
  final out = StringBuffer()
    ..writeln('### Line coverage')
    ..writeln()
    ..writeln(
      '**Total (lib/, generated l10n excluded): ${pct(th, tf)}** '
      '($th / $tf lines)',
    )
    ..writeln()
    ..writeln('| Critical-path file | Covered | Lines |')
    ..writeln('|---|---|---|');
  final rows =
      files.entries.where((e) => critical.any(e.key.startsWith)).toList()
        ..sort((a, b) => a.key.compareTo(b.key));
  for (final MapEntry(key: f, value: (h, n)) in rows) {
    out.writeln('| `$f` | ${pct(h, n)} | $h / $n |');
  }
  stdout.write(out);
}
