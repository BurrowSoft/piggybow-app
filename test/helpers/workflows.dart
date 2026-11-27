/// Plain-text readers for the workflow files under .github/workflows/, for
/// the tests that pin them.
library;

/// The body of every `run:` step in [yaml], one string per step.
List<String> runBlocks(String yaml) {
  final lines = yaml.split('\n');
  final blocks = <String>[];
  for (var i = 0; i < lines.length; i++) {
    final m = RegExp(r'^(\s*)(- )?run: ?(.*)$').firstMatch(lines[i]);
    if (m == null) continue;
    final indent = m.group(1)!.length + (m.group(2)?.length ?? 0);
    final rest = m.group(3)!;
    if (rest.isNotEmpty && rest != '|' && rest != '>') {
      blocks.add(rest);
      continue;
    }
    final body = <String>[];
    for (var j = i + 1; j < lines.length; j++) {
      final l = lines[j];
      if (l.trim().isNotEmpty && l.length - l.trimLeft().length <= indent) {
        break;
      }
      body.add(l);
    }
    blocks.add(body.join('\n'));
  }
  return blocks;
}

/// The text of job [name] in [yaml]: from its `  name:` line to the next job
/// (or the end of the file). Throws a StateError when there is no such job.
String jobSection(String yaml, String name) {
  final start = yaml.indexOf('\n  $name:\n');
  if (start < 0) throw StateError('no job $name');
  final next = RegExp(r'\n  [A-Za-z0-9_-]+:\n')
      .firstMatch(yaml.substring(start + 1));
  return next == null
      ? yaml.substring(start + 1)
      : yaml.substring(start + 1, start + 1 + next.start);
}

/// Every value of `key: value` in [yaml], in order, trimmed.
List<String> valuesOf(String yaml, String key) => [
  for (final m in RegExp(
    '^\\s*(?:- )?${RegExp.escape(key)}: *(.+?)\\s*\$',
    multiLine: true,
  ).allMatches(yaml))
    m.group(1)!,
];
