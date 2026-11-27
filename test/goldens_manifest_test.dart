import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../tool/golden_manifest.dart';
import 'helpers/goldens.dart';

/// Decision 44: the committed goldens are exactly what a goldens.yaml run
/// wrote. Each is listed in manifest.json beside it, both ways, byte for
/// byte, each is an 8-bit RGBA PNG named by the rule, and every golden goes
/// through expectGolden in a file tagged golden that loads the app's fonts.
List<int> _u32(int v) => [v >> 24 & 255, v >> 16 & 255, v >> 8 & 255, v & 255];

List<int> _chunk(String type, List<int> data) => [
  ..._u32(data.length),
  ...type.codeUnits,
  ...data,
  0,
  0,
  0,
  0,
];

/// A PNG's bytes as Flutter's encoder lays them out (the image data is
/// filler: only the header and the chunks are read).
Uint8List png({
  int width = 960,
  int height = 1800,
  int bitDepth = 8,
  int colourType = 6,
  bool signature = true,
  bool iend = true,
  int fill = 1,
}) => Uint8List.fromList([
  ...(signature
      ? [137, 80, 78, 71, 13, 10, 26, 10]
      : [71, 73, 70, 56, 57, 97, 0, 0]),
  ..._chunk('IHDR', [
    ..._u32(width),
    ..._u32(height),
    bitDepth,
    colourType,
    0,
    0,
    0,
  ]),
  ..._chunk('IDAT', [fill, 2, 3, 4]),
  if (iend) ...[0, 0, 0, 0, 73, 69, 78, 68, 174, 66, 96, 130],
]);

Directory tempDir() {
  final dir = Directory.systemTemp.createTempSync('pb-goldens-');
  addTearDown(() => dir.deleteSync(recursive: true));
  return dir;
}

Map<String, Object?> run() => {
  'source_sha': 'a' * 40,
  'ref': 'goldens-example',
  'run_id': '46064367481',
  'run_attempt': '1',
  'flutter': '3.47.5',
};

Map<String, Object?> manifestOf(Map<String, Uint8List> files) => {
  ...run(),
  'goldens': [
    for (final e in files.entries)
      {
        'file': e.key,
        'state': 'A2',
        'test': 'add sheet A2 ${e.key}',
        'sha256': sha256.convert(e.value).toString(),
        'bytes': e.value.length,
        'width': inspectPng(e.value).width,
        'height': inspectPng(e.value).height,
      },
  ],
};

/// A goldens folder holding [files] and [manifest] (none when null).
Directory folder(Map<String, Uint8List> files, Map<String, Object?>? manifest) {
  final dir = tempDir();
  for (final e in files.entries) {
    File('${dir.path}/${e.key}').writeAsBytesSync(e.value);
  }
  if (manifest != null) {
    File('${dir.path}/$manifestName').writeAsStringSync(jsonEncode(manifest));
  }
  return dir;
}

const light = 'add-sheet_spent-full_light_320x2.png';
const dark = 'add-sheet_spent-full_dark_320x2.png';

/// The rule for test files: matchesGoldenFile only inside expectGolden, and
/// a file that calls expectGolden is tagged golden and loads the app's fonts.
/// [files] maps a path (with /) to its text.
List<String> goldenRuleProblems(Map<String, String> files) {
  const helper = 'test/helpers/goldens.dart';
  const direct =
      'matches'
      'GoldenFile(';
  // expectGolden, or a wrapper named like it (expectLayoutGolden).
  final golden = RegExp(r'\bexpect[A-Za-z]*Golden\(');
  final problems = <String>[];
  for (final e in files.entries) {
    if (e.key == helper) continue;
    if (e.value.contains(direct)) {
      problems.add('${e.key}: calls $direct directly, not expectGolden');
    }
    // The tag and the fonts are for test files; a helper may wrap it.
    if (!e.key.endsWith('_test.dart') || !golden.hasMatch(e.value)) continue;
    if (!e.value.contains("@Tags(['golden'])")) {
      problems.add("${e.key}: calls expectGolden without @Tags(['golden'])");
    }
    // Called, or passed as in setUpAll(loadAppFonts).
    if (!RegExp(r'\bloadAppFonts\b').hasMatch(e.value)) {
      problems.add('${e.key}: calls expectGolden without loadAppFonts()');
    }
  }
  return problems;
}

String report(List<({int id, String name, List<String> lines})> tests) => [
  jsonEncode({'type': 'start', 'protocolVersion': '0.1.1', 'time': 0}),
  for (final t in tests) ...[
    jsonEncode({
      'type': 'testStart',
      'test': {'id': t.id, 'name': t.name, 'suiteID': 0},
      'time': 1,
    }),
    for (final l in t.lines)
      jsonEncode({
        'type': 'print',
        'testID': t.id,
        'messageType': 'print',
        'message': l,
        'time': 2,
      }),
  ],
].join('\n');

String line(String file, [String state = 'A2']) =>
    '$goldenMarker${jsonEncode({'file': file, 'state': state})}';

void main() {
  test('test/goldens is exactly its manifest, both ways', () {
    expect(checkGoldens(Directory(goldensDir)), isEmpty);
  });

  test('every golden goes through expectGolden, tagged, with real fonts', () {
    final files = {
      for (final f in Directory('test').listSync(recursive: true))
        if (f is File && f.path.endsWith('.dart'))
          f.path.replaceAll('\\', '/'): f.readAsStringSync(),
    }..remove('test/goldens_manifest_test.dart');
    expect(files.keys, contains('test/helpers/goldens.dart'));
    expect(goldenRuleProblems(files), isEmpty);
    expect(
      File('dart_test.yaml').readAsStringSync(),
      contains('\ntags:\n  golden: {}\n'),
    );
  });

  test('the rule sees a direct call, a missing tag and missing fonts', () {
    const direct =
        'matches'
        'GoldenFile(';
    expect(
      goldenRuleProblems({
        'test/helpers/goldens.dart': 'await expectLater(f, $direct key));',
        'test/a_test.dart': 'expectLater(f, $direct"a.png"));',
        'test/b_test.dart':
            "@Tags(['golden'])\nloadAppFonts();\nexpectGolden(t,",
        'test/c_test.dart': 'loadAppFonts();\nexpectGolden(t,',
        'test/d_test.dart': "@Tags(['golden'])\nexpectGolden(t,",
        'test/e_test.dart': 'loadAppFonts();\nexpectLayoutGolden(t,',
        'test/layout/layout_matrix.dart': '=> expectGolden(t, f,',
        'test/f_test.dart': '// expectedGoldenCount, not a call',
        'test/g_test.dart':
            "@Tags(['golden'])\nsetUpAll(loadAppFonts);\nexpectLayoutGolden(t,",
        'test/h_test.dart':
            "@Tags(['golden'])\nloadAppFontsLater();\nexpectGolden(t,",
      }),
      [
        'test/a_test.dart: calls $direct directly, not expectGolden',
        "test/c_test.dart: calls expectGolden without @Tags(['golden'])",
        'test/d_test.dart: calls expectGolden without loadAppFonts()',
        "test/e_test.dart: calls expectGolden without @Tags(['golden'])",
        'test/h_test.dart: calls expectGolden without loadAppFonts()',
      ],
    );
  });

  group('golden names', () {
    test('built by the rule', () {
      expect(
        goldenName(
          screen: 'add-sheet',
          state: 'spent-full',
          brightness: Brightness.dark,
          width: 320,
          textScale: 2,
        ),
        dark,
      );
      for (final name in [
        'timeline_empty_light_320x2.png',
        'pig_delighted_dark_200x1.png',
        'onboarding-o1_currency_light_360x1.png',
      ]) {
        expect(goldenNamePattern.hasMatch(name), isTrue, reason: name);
      }
    });

    test('a field that breaks the rule is refused', () {
      for (final (screen, state, width, scale) in [
        ('Add-sheet', 'full', 320, 2),
        ('add_sheet', 'full', 320, 2),
        ('add--sheet', 'full', 320, 2),
        ('-add', 'full', 320, 2),
        ('add', 'full ', 320, 2),
        ('add', '', 320, 2),
        ('add', 'full', 0, 2),
        ('add', 'full', 12345, 2),
        ('add', 'full', 320, 0),
        ('add', 'full', 320, 10),
      ]) {
        expect(
          () => goldenName(
            screen: screen,
            state: state,
            brightness: Brightness.light,
            width: width,
            textScale: scale,
          ),
          throwsArgumentError,
          reason: '$screen $state $width $scale',
        );
      }
    });

    test('state ids as in the lists', () {
      for (final id in ['A2', 'C22a', 'S11', 'E2']) {
        expect(stateIdPattern.hasMatch(id), isTrue, reason: id);
      }
      for (final id in ['a2', 'A', '2A', 'A2-b', 'A2 ', '']) {
        expect(stateIdPattern.hasMatch(id), isFalse, reason: id);
      }
    });

    test('the key reaches test/goldens from the test file', () {
      final root = Uri.parse('file:///work/app/');
      expect(
        goldenKey(
          dark,
          testDir: Uri.parse('file:///work/app/test/'),
          packageRoot: root,
        ),
        '../test/goldens/$dark',
      );
      expect(
        goldenKey(
          dark,
          testDir: Uri.parse('file:///work/app/test/features/summary/'),
          packageRoot: root,
        ),
        '../../../test/goldens/$dark',
      );
      expect(
        () => goldenKey(
          dark,
          testDir: Uri.parse('file:///elsewhere/test/'),
          packageRoot: root,
        ),
        throwsStateError,
      );
    });
  });

  group('the PNG check', () {
    test("Flutter's 8-bit RGBA PNG passes, with its size", () {
      final info = inspectPng(png(width: 960, height: 1800));
      expect(info.problem, isNull);
      expect((info.width, info.height), (960, 1800));
    });

    test('anything else is refused', () {
      expect(
        inspectPng(png(signature: false)).problem,
        'not a PNG (no signature)',
      );
      expect(
        inspectPng(png(colourType: 2)).problem,
        'not 8-bit RGBA (bit depth 8, colour type 2)',
      );
      expect(
        inspectPng(png(bitDepth: 16)).problem,
        'not 8-bit RGBA (bit depth 16, colour type 6)',
      );
      expect(inspectPng(png(width: 0)).problem, 'an empty image');
      expect(inspectPng(png(iend: false)).problem, isNotNull);
      expect(inspectPng(Uint8List(10)).problem, 'too short for a PNG');
      expect(
        inspectPng(
          Uint8List.fromList([
            ...png().take(12),
            200,
            201,
            202,
            203,
            ...List.filled(40, 0),
          ]),
        ).problem,
        'no IHDR chunk first',
      );
    });
  });

  group('checkGoldens', () {
    final files = {light: png(), dark: png(fill: 9)};

    test('agrees when the folder is what the run wrote', () {
      expect(checkGoldens(folder(files, manifestOf(files))), isEmpty);
    });

    test('no folder yet: nothing to check', () {
      expect(checkGoldens(Directory('${tempDir().path}/none')), isEmpty);
    });

    test('a PNG the manifest does not list', () {
      final dir = folder({
        ...files,
        'pig_happy_light_200x1.png': png(),
      }, manifestOf(files));
      expect(checkGoldens(dir), [
        'pig_happy_light_200x1.png: in $goldensDir but not in $manifestName',
      ]);
    });

    test('a listed PNG that is not there', () {
      final dir = folder({light: files[light]!}, manifestOf(files));
      expect(checkGoldens(dir), [
        '$dark: listed in $manifestName but not in $goldensDir',
      ]);
    });

    test('a PNG changed after the run (same size, other bytes)', () {
      final dir = folder({
        light: files[light]!,
        dark: png(fill: 7),
      }, manifestOf(files));
      expect(checkGoldens(dir), [
        '$dark: its sha256 is not the one in $manifestName',
      ]);
    });

    test('a pasted image: another kind, or another size', () {
      final pasted = {light: files[light]!, dark: png(colourType: 2)};
      expect(checkGoldens(folder(pasted, manifestOf(files))), [
        '$dark: not 8-bit RGBA (bit depth 8, colour type 2)',
      ]);
      final bigger = {light: files[light]!, dark: png(width: 961, fill: 9)};
      final manifest = manifestOf(bigger);
      ((manifest['goldens'] as List)[1] as Map)['sha256'] = sha256
          .convert(bigger[dark]!)
          .toString();
      ((manifest['goldens'] as List)[1] as Map)['width'] = 960;
      expect(checkGoldens(folder(bigger, manifest)), [
        '$dark: its dimensions are not the ones in $manifestName',
      ]);
    });

    test('only PNGs and manifest.json: no other file, no folder', () {
      final dir = folder(files, manifestOf(files));
      File('${dir.path}/notes.txt').writeAsStringSync('x');
      Directory('${dir.path}/failures').createSync();
      expect(checkGoldens(dir).toSet(), {
        'notes.txt: only PNGs and $manifestName belong in $goldensDir',
        'failures: only files belong in $goldensDir',
      });
    });

    test('PNGs without a manifest', () {
      expect(checkGoldens(folder(files, null)), ['$manifestName is missing']);
    });

    test('the manifest names the run that rendered them', () {
      final manifest = manifestOf(files)
        ..remove('source_sha')
        ..['run_id'] = 'latest'
        ..['flutter'] = 'stable'
        ..remove('ref');
      expect(checkGoldens(folder(files, manifest)), [
        '$manifestName: "source_sha" is missing or malformed',
        '$manifestName: "run_id" is missing or malformed',
        '$manifestName: "flutter" is missing or malformed',
        '$manifestName: "ref" is missing',
      ]);
    });

    test('a name, state or test that breaks the rule; a file listed twice', () {
      final odd = {'AddSheet_full_dark_320x2.png': png()};
      expect(checkGoldens(folder(odd, manifestOf(odd))), [
        '$manifestName: "AddSheet_full_dark_320x2.png" is not <screen>_<state>_<light|dark>_<width>x<scale>.png',
        'AddSheet_full_dark_320x2.png: in $goldensDir but not in $manifestName',
      ]);
      final manifest = manifestOf(files);
      final entries = manifest['goldens'] as List;
      (entries[0] as Map)['state'] = 'spent-full';
      (entries[1] as Map)['test'] = ' ';
      entries.add(entries[0]);
      expect(checkGoldens(folder(files, manifest)), [
        '$light: "state" is not a state id such as A2',
        '$dark: "test" is missing',
        '$manifestName: $light is listed twice',
      ]);
    });
  });

  group('the run (goldens.yaml)', () {
    final since = DateTime.utc(2026, 11, 27, 20);
    final after = since.add(const Duration(minutes: 1));

    /// A package root whose test/ holds [pngs] (path under test/ → written
    /// after the start or not).
    Directory rootWith(Map<String, bool> pngs) {
      final root = tempDir();
      for (final e in pngs.entries) {
        final f = File('${root.path}/test/${e.key}')
          ..createSync(recursive: true);
        f.writeAsBytesSync(png(fill: e.key.length));
        f.setLastModifiedSync(
          e.value ? after : since.subtract(const Duration(days: 1)),
        );
      }
      return root;
    }

    final twoTests = report([
      (id: 3, name: 'add sheet A2 spent-full light', lines: [line(light)]),
      (
        id: 4,
        name: 'add sheet A2 spent-full dark',
        lines: ['other output', line(dark)],
      ),
    ]);

    test('writes what expectGolden rendered and a manifest that passes', () {
      final root = rootWith({
        'goldens/$light': true,
        'goldens/$dark': true,
        'goldens/old_gone_light_320x1.png': false,
      });
      final out = Directory('${tempDir().path}/out');
      final problems = writeGoldens(
        root: root,
        report: twoTests,
        since: since,
        out: out,
        run: {
          'sha': 'b' * 40,
          'ref': 'feat/summary',
          'run-id': '46064367481',
          'run-attempt': '2',
          'flutter': '3.47.5',
        },
      );
      expect(problems, isEmpty);
      expect(
        out
            .listSync()
            .map((f) => f.path.replaceAll('\\', '/').split('/').last)
            .toSet(),
        {light, dark, manifestName},
      );
      final manifest = jsonDecode(
        File('${out.path}/$manifestName').readAsStringSync(),
      ) as Map;
      expect(manifest['source_sha'], 'b' * 40);
      expect(manifest['ref'], 'feat/summary');
      expect(manifest['run_id'], '46064367481');
      expect(manifest['run_attempt'], '2');
      expect(manifest['flutter'], '3.47.5');
      final goldens = (manifest['goldens'] as List).cast<Map>();
      expect([for (final g in goldens) g['file']], [dark, light]);
      expect(
        [for (final g in goldens) g['test']],
        ['add sheet A2 spent-full dark', 'add sheet A2 spent-full light'],
      );
      expect([for (final g in goldens) g['state']], ['A2', 'A2']);
      expect(checkGoldens(out), isEmpty);
    });

    test('a PNG written outside expectGolden fails the run', () {
      final root = rootWith({
        'goldens/$light': true,
        'goldens/$dark': true,
        'features/goldens/direct_call_light_320x1.png': true,
      });
      final out = Directory('${tempDir().path}/out');
      expect(
        writeGoldens(
          root: root,
          report: twoTests,
          since: since,
          out: out,
          run: {},
        ),
        [
          'test/features/goldens/direct_call_light_320x1.png: written in this run, but not by expectGolden',
        ],
      );
      expect(out.existsSync(), isFalse);
    });

    test('a golden reported but not written in this run fails', () {
      final root = rootWith({'goldens/$light': true, 'goldens/$dark': false});
      expect(
        writeGoldens(
          root: root,
          report: twoTests,
          since: since,
          out: Directory('${tempDir().path}/out'),
          run: {},
        ),
        ['$dark: reported but not written in this run'],
      );
    });

    test('no golden rendered, or one rendered twice, fails', () {
      final root = rootWith({'goldens/$light': true});
      final out = Directory('${tempDir().path}/out');
      expect(
        writeGoldens(
          root: root,
          report: report([]),
          since: since,
          out: out,
          run: {},
        ),
        ['no golden was rendered: is a test file tagged golden?'],
      );
      final twice = report([
        (id: 1, name: 'a', lines: [line(light)]),
        (id: 2, name: 'b', lines: [line(light)]),
      ]);
      expect(
        writeGoldens(
          root: root,
          report: twice,
          since: since,
          out: out,
          run: {},
        ),
        ['$light was rendered twice'],
      );
    });

    test('the manifest is built from the report alone', () {
      expect(reportedGoldens(twoTests), [
        (file: light, state: 'A2', test: 'add sheet A2 spent-full light'),
        (file: dark, state: 'A2', test: 'add sheet A2 spent-full dark'),
      ]);
      expect(
        () => reportedGoldens(
          report([
            (id: 1, name: 'a', lines: ['${goldenMarker}nope']),
          ]),
        ),
        throwsFormatException,
      );
    });
  });
}
