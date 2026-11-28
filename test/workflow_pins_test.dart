import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Every action a workflow uses is pinned to a full commit sha, with its
/// release in a comment, and each action to the same commit everywhere. A
/// tag such as v4 can be moved to other code; a commit sha can't. Our own
/// actions (.github/actions) are held to the same rule, and a workflow uses
/// them from its own commit. What a workflow downloads and runs without a
/// pinned digest from GitHub (bundletool, Flutter) is checked by its sha256
/// first.
final _uses = RegExp(r'^\s*(?:- )?uses:\s*(.+?)\s*$', multiLine: true);
final _pinned = RegExp(
  r'^([A-Za-z0-9-]+/[A-Za-z0-9._-]+(?:/[A-Za-z0-9._/-]+)?)@([0-9a-f]{40}) # (v[0-9]+\.[0-9]+\.[0-9]+)$',
);

/// One of our own actions, from the checkout of the workflow's own commit:
/// the root, or ci/ where the root holds another commit.
final _local = RegExp(r'^\./(?:ci/)?\.github/actions/[a-z0-9-]+$');

/// Each `uses:` value in [yaml] that isn't pinned by the rule.
List<String> unpinned(String yaml) => [
  for (final m in _uses.allMatches(yaml))
    if (!_pinned.hasMatch(m.group(1)!) && !_local.hasMatch(m.group(1)!))
      m.group(1)!,
];

void main() {
  String read(File f) => f.readAsStringSync().replaceAll('\r\n', '\n');
  final workflows = {
    for (final f in Directory('.github/workflows').listSync().whereType<File>())
      if (f.path.endsWith('.yaml') || f.path.endsWith('.yml'))
        f.uri.pathSegments.last: read(f),
  };
  final actions = {
    for (final f in Directory(
      '.github/actions',
    ).listSync(recursive: true).whereType<File>())
      if (f.uri.pathSegments.last == 'action.yml')
        f.path.replaceAll(r'\', '/'): read(f),
  };
  final all = {...workflows, ...actions};
  const flutterAction = '.github/actions/flutter/action.yml';

  test('every uses: is a commit sha with its release, or our own action', () {
    expect(actions.keys, contains(flutterAction));
    var count = 0;
    for (final w in all.entries) {
      count += _uses.allMatches(w.value).length;
      expect(unpinned(w.value), isEmpty, reason: w.key);
    }
    expect(count, greaterThanOrEqualTo(20), reason: 'uses: lines found');
  });

  test('one action, one commit and one release, in every workflow', () {
    final pins = <String, Set<String>>{};
    for (final w in all.values) {
      for (final m in _uses.allMatches(w)) {
        final p = _pinned.firstMatch(m.group(1)!);
        if (p == null) continue;
        pins
            .putIfAbsent(p.group(1)!, () => {})
            .add('${p.group(2)} ${p.group(3)}');
      }
    }
    expect(pins.keys, containsAll(['actions/checkout', 'actions/cache']));
    for (final e in pins.entries) {
      expect(e.value, hasLength(1), reason: e.key);
    }
  });

  test('every workflow reads only, and no checkout keeps its credentials', () {
    final readOnly = RegExp(r'^permissions:\n  contents: read\n', multiLine: true);
    for (final w in workflows.entries) {
      expect(readOnly.hasMatch(w.value), isTrue, reason: '${w.key}: read only');
      // No job pushes; the release job holds the upload key.
      expect(
        'persist-credentials: false'.allMatches(w.value).length,
        'uses: actions/checkout@'.allMatches(w.value).length,
        reason: '${w.key}: each checkout',
      );
    }
  });

  test("every workflow sets up Flutter with our own action, from the workflow's "
      'own commit', () {
    final checkout = RegExp(
      r'uses: actions/checkout@\S+ # \S+\n        with:\n((?:          .*\n)+)',
    );
    final pathOf = RegExp(r'^          path: (\S+)$', multiLine: true);
    for (final w in workflows.entries) {
      expect(w.value, isNot(contains('flutter-action')), reason: w.key);
      expect(
        RegExp(
          r'uses: \./(?:ci/)?\.github/actions/flutter$',
          multiLine: true,
        ).hasMatch(w.value),
        isTrue,
        reason: '${w.key} sets up Flutter',
      );
      for (final m in RegExp(
        r'uses: \./(ci/)?\.github/actions/',
      ).allMatches(w.value)) {
        final path = m.group(1) == null ? null : 'ci';
        final trees = [
          for (final c in checkout.allMatches(w.value))
            if (pathOf.firstMatch(c.group(1)!)?.group(1) == path) c.group(1)!,
        ];
        final tree = path ?? 'the root';
        expect(trees, isNotEmpty, reason: '${w.key}: $tree is checked out');
        for (final t in trees) {
          // No ref: the commit the workflow itself runs from.
          expect(
            t,
            isNot(contains('          ref:')),
            reason: '${w.key}: $tree is its own commit',
          );
        }
      }
    }
  });

  test('the Flutter action: a download is checked by its sha256, and the SDK '
      'by its revision and its tracked files, before it runs', () {
    final a = actions[flutterAction]!;
    expect(
      RegExp(
        r'^          echo "sha256=[0-9a-f]{64}"$',
        multiLine: true,
      ).allMatches(a),
      hasLength(1),
    );
    expect(
      RegExp(
        r'^          echo "revision=[0-9a-f]{40}"$',
        multiLine: true,
      ).allMatches(a),
      hasLength(1),
    );
    final download = a.indexOf('curl ');
    final check = a.indexOf(
      r'echo "$SHA256  $RUNNER_TEMP/flutter.tar.xz" | sha256sum -c -',
    );
    final unpack = a.indexOf(r'tar -xJf "$RUNNER_TEMP/flutter.tar.xz"');
    final revision = a.indexOf(r'if [ "$head" != "$REVISION" ]; then');
    final tracked = a.indexOf(
      r'if ! git -C "$DIR/flutter" diff --quiet HEAD --; then',
    );
    final onPath = a.indexOf(r'>> "$GITHUB_PATH"');
    final firstRun = a.indexOf(r'"$DIR/flutter/bin/flutter" --version');
    expect(download, greaterThan(0));
    expect(check, greaterThan(download));
    expect(unpack, greaterThan(check));
    expect(revision, greaterThan(unpack));
    expect(tracked, greaterThan(revision));
    expect(onPath, greaterThan(tracked));
    expect(firstRun, greaterThan(onPath));
  });

  test('its cache is off unless a job asks, and the release job never does', () {
    final a = actions[flutterAction]!;
    expect(
      RegExp(
        r'^  cache:\n(?:    .*\n)*?    default: "false"\n',
        multiLine: true,
      ).hasMatch(a),
      isTrue,
    );
    // Both cache steps, and only they, use actions/cache.
    expect("if: inputs.cache == 'true'".allMatches(a), hasLength(2));
    expect('uses: actions/cache@'.allMatches(a), hasLength(2));
    final release = RegExp(
      r'uses: \./\.github/actions/flutter\n((?:        .*\n)*)',
    ).allMatches(workflows['release-aab.yaml']!).toList();
    expect(release, hasLength(1));
    expect(release.single.group(1), isNot(contains('cache:')));
  });

  test(
    'the rule refuses a tag, a branch, a short sha, a missing release and '
    "another commit's action",
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
  - uses: ./.github/actions/flutter
  - uses: ./ci/.github/actions/flutter
  - uses: ./app/.github/actions/flutter
'''),
        [
          'actions/checkout@v4',
          'actions/checkout@main',
          'actions/checkout@11d5960',
          'actions/checkout@$sha',
          'actions/checkout@$sha # v4',
          './app/.github/actions/flutter',
        ],
      );
    },
  );

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
    // A workflow's steps sit six spaces in, an action's four.
    for (final (files, step) in [
      (workflows, '\n      - '),
      (actions, '\n    - '),
    ]) {
      for (final w in files.entries) {
        for (final m in 'curl '.allMatches(w.value)) {
          downloads++;
          final next = w.value.indexOf(step, m.start);
          final s = w.value.substring(
            m.start,
            next < 0 ? w.value.length : next,
          );
          expect(s, contains('sha256sum -c -'), reason: '${w.key}: $s');
        }
      }
    }
    expect(downloads, greaterThanOrEqualTo(3), reason: 'downloads found');
  });
}
