import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Every action a workflow uses is pinned to a full commit sha, with its
/// release in a comment, and each action to the same commit everywhere. A
/// tag such as v4 can be moved to other code; a commit sha can't. The one
/// tool a workflow downloads and runs without a pinned digest from GitHub,
/// bundletool, is checked by its sha256 first.
final _uses = RegExp(r'^\s*(?:- )?uses:\s*(.+?)\s*$', multiLine: true);
final _pinned = RegExp(
  r'^([A-Za-z0-9-]+/[A-Za-z0-9._-]+(?:/[A-Za-z0-9._/-]+)?)@([0-9a-f]{40}) # (v[0-9]+\.[0-9]+\.[0-9]+)$',
);

/// Each `uses:` value in [yaml] that isn't pinned by the rule.
List<String> unpinned(String yaml) => [
  for (final m in _uses.allMatches(yaml))
    if (!_pinned.hasMatch(m.group(1)!)) m.group(1)!,
];

void main() {
  final workflows = {
    for (final f in Directory('.github/workflows').listSync().whereType<File>())
      if (f.path.endsWith('.yaml') || f.path.endsWith('.yml'))
        f.uri.pathSegments.last: f.readAsStringSync(),
  };

  test('every uses: is a commit sha with its release', () {
    var count = 0;
    for (final w in workflows.entries) {
      count += _uses.allMatches(w.value).length;
      expect(unpinned(w.value), isEmpty, reason: w.key);
    }
    expect(count, greaterThanOrEqualTo(20), reason: 'uses: lines found');
  });

  test('one action, one commit and one release, in every workflow', () {
    final pins = <String, Set<String>>{};
    for (final w in workflows.values) {
      for (final m in _uses.allMatches(w)) {
        final p = _pinned.firstMatch(m.group(1)!);
        if (p == null) continue;
        pins
            .putIfAbsent(p.group(1)!, () => {})
            .add('${p.group(2)} ${p.group(3)}');
      }
    }
    expect(
      pins.keys,
      containsAll(['actions/checkout', 'subosito/flutter-action']),
    );
    for (final e in pins.entries) {
      expect(e.value, hasLength(1), reason: e.key);
    }
  });

  test('every workflow reads only, and no checkout keeps its credentials', () {
    final readOnly = RegExp(r'^permissions:\n  contents: read\n', multiLine: true);
    for (final w in workflows.entries) {
      final yaml = w.value.replaceAll('\r\n', '\n');
      expect(readOnly.hasMatch(yaml), isTrue, reason: '${w.key}: read only');
      // No job pushes; the release job holds the upload key.
      expect(
        'persist-credentials: false'.allMatches(yaml).length,
        'uses: actions/checkout@'.allMatches(yaml).length,
        reason: '${w.key}: each checkout',
      );
    }
  });

  test(
    'the rule refuses a tag, a branch, a short sha and a missing release',
    () {
      const sha = '11d5960a326750d5838078e36cf38b85af677262';
      expect(
        unpinned('''
steps:
  - uses: actions/checkout@v4
  - uses: actions/checkout@main
  - uses: actions/checkout@11d5960
  - uses: actions/checkout@$sha
  - uses: actions/checkout@$sha # v4
  - uses: actions/checkout@$sha # v4.4.0
  - name: x
    uses: owner/repo/sub/action@$sha # v1.2.3
'''),
        [
          'actions/checkout@v4',
          'actions/checkout@main',
          'actions/checkout@11d5960',
          'actions/checkout@$sha',
          'actions/checkout@$sha # v4',
        ],
      );
    },
  );

  test('the release job runs flutter-action with its cache off: its cache '
      'steps use actions/cache by tag', () {
    final release = workflows['release-aab.yaml']!.replaceAll('\r\n', '\n');
    final steps = RegExp(
      r'uses: subosito/flutter-action@[0-9a-f]{40} # v[0-9.]+\n'
      r'        with:\n((?:          .*\n)+)',
    ).allMatches(release).toList();
    expect(steps, hasLength(1));
    final inputs = steps.single.group(1)!;
    expect(inputs, contains('\n          cache: false\n'));
    // pub-cache: true would turn its second cache step back on.
    expect(inputs, isNot(contains('pub-cache:')));
  });

  test('bundletool is checked by its sha256 before it runs', () {
    final release = workflows['release-aab.yaml']!;
    final download = release.indexOf(
      'https://github.com/google/bundletool/releases/download/1.18.1/bundletool-all-1.18.1.jar',
    );
    final check = release.indexOf(
      'echo "675786493983787ffa11550bdb7c0715679a44e1643f3ff980a529e9c822595c  '
      r'$RUNNER_TEMP/bundletool.jar" | sha256sum -c -',
    );
    final firstRun = release.indexOf(
      r'java -jar "$RUNNER_TEMP/bundletool.jar"',
    );
    expect(download, greaterThan(0));
    expect(check, greaterThan(download));
    expect(firstRun, greaterThan(check));
  });

  test('every download is checked by sha256 in the same step', () {
    var downloads = 0;
    for (final w in workflows.entries) {
      for (final m in 'curl '.allMatches(w.value)) {
        downloads++;
        final next = w.value.indexOf('\n      - ', m.start);
        final step = w.value.substring(
          m.start,
          next < 0 ? w.value.length : next,
        );
        expect(step, contains('sha256sum -c -'), reason: '${w.key}: $step');
      }
    }
    expect(downloads, greaterThanOrEqualTo(2), reason: 'downloads found');
  });
}
