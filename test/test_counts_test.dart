import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// tool/test_counts.mjs (CI's "test counts" step) on a small report: the
/// totals, the skipped tests by name, each file's own counts, and a test
/// file that never ran. A file's loading (a hidden test) isn't counted.
void main() {
  final node = _runs('node');
  late String root;

  setUp(() => root = Directory.systemTemp.createTempSync('test-counts').resolveSymbolicLinksSync());
  tearDown(() => Directory(root).deleteSync(recursive: true));

  ProcessResult counts(String report) => Process.runSync(
    'node',
    [File('tool/test_counts.mjs').absolute.path, report],
    workingDirectory: root,
  );

  Map<String, Object?> start(int id, String name, int suite, {String? skip}) => {
    'type': 'testStart',
    'test': {
      'id': id,
      'name': name,
      'suiteID': suite,
      'groupIDs': <int>[],
      'metadata': {'skip': skip != null, 'skipReason': skip},
    },
  };

  Map<String, Object?> done(int id, String result, {bool skipped = false, bool hidden = false}) => {
    'type': 'testDone',
    'testID': id,
    'result': result,
    'skipped': skipped,
    'hidden': hidden,
  };

  Map<String, Object?> suite(int id, String path) => {
    'type': 'suite',
    'suite': {'id': id, 'platform': 'vm', 'path': '$root/$path'},
  };

  test('totals, skipped tests by name, per-file counts, and a test file that never ran', () {
    for (final f in ['a_test.dart', 'sub/b_test.dart', 'never_test.dart', 'helpers.dart']) {
      File('$root/test/$f').createSync(recursive: true);
    }
    final events = [
      {'type': 'start', 'protocolVersion': '0.1.1'},
      suite(0, 'test/a_test.dart'),
      start(1, 'loading $root/test/a_test.dart', 0),
      done(1, 'success', hidden: true),
      start(2, 'passes', 0),
      done(2, 'success'),
      start(3, 'fails', 0),
      done(3, 'failure'),
      suite(4, 'test/sub/b_test.dart'),
      start(5, 'skipped one', 4, skip: 'needs bash'),
      done(5, 'success', skipped: true),
      start(6, 'errors', 4),
      done(6, 'error'),
      {'type': 'done', 'success': false},
    ];
    File('$root/report.json').writeAsStringSync(events.map(jsonEncode).join('\n'));
    final r = counts('report.json');
    expect(r.exitCode, 0, reason: '${r.stderr}');
    expect(r.stdout, '''
### Tests: 1 passed, 1 failed, 1 errors, 1 skipped
(2 test files)

Skipped:
- test/sub/b_test.dart: skipped one (needs bash)

Test files not in the report (they never ran):
- test/never_test.dart

<details><summary>Per test file</summary>

| File | Passed | Failed | Errors | Skipped |
|---|---:|---:|---:|---:|
| test/a_test.dart | 1 | 1 | 0 | 0 |
| test/sub/b_test.dart | 0 | 0 | 1 | 1 |

</details>
''');
  }, skip: node ? false : 'needs node');

  test('no report: says so, and still exits 0 (it only reports)', () {
    final r = counts('missing.json');
    expect(r.exitCode, 0, reason: '${r.stderr}');
    expect(r.stdout, 'No test report at missing.json.\n');
  }, skip: node ? false : 'needs node');
}

bool _runs(String exe) {
  try {
    return Process.runSync(exe, ['--version']).exitCode == 0;
  } on ProcessException {
    return false;
  }
}
