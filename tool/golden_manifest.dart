// The golden baselines (decision 44): the PNGs in test/goldens/ and the
// manifest beside them.
//
// Goldens are rendered only on CI, by .github/workflows/goldens.yaml, never
// on a PC. That run calls
//   dart run tool/golden_manifest.dart write --report <json> --since <file>
//     --out <dir> --sha <sha> --ref <ref> --run-id <id> --run-attempt <n>
//     --flutter <version>
// which reads the run's JSON test report (each golden's line printed by
// expectGolden in test/helpers/goldens.dart, tied to its test), and writes
// the PNGs and manifest.json to <dir>: exactly what test/goldens/ should
// then hold. test/goldens_manifest_test.dart runs checkGoldens on every PR,
// so the committed PNGs are the ones the manifest names, byte for byte.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// Where the committed baselines live, relative to the package root.
const goldensDir = 'test/goldens';

/// The manifest's file name inside [goldensDir].
const manifestName = 'manifest.json';

/// The start of the line expectGolden prints while goldens are rendered.
const goldenMarker = 'piggybow-golden ';

const _field = r'[a-z0-9]+(?:-[a-z0-9]+)*';

/// `<screen>_<state>_<light|dark>_<width>x<scale>.png`: kebab-case fields,
/// the width in dp, the text scale.
final goldenNamePattern = RegExp(
  '^($_field)_($_field)_(light|dark)_([1-9][0-9]{1,3})x([1-9])\\.png\$',
);

/// The state's id in PB Mobile Tester's lists, such as A2, C22a or S11.
final stateIdPattern = RegExp(r'^[A-Z]{1,2}[0-9]{1,3}[a-z]?$');

/// The run that rendered the goldens, as the manifest records it.
final _shaPattern = RegExp(r'^[0-9a-f]{40}$');
final _digitsPattern = RegExp(r'^[0-9]{1,20}$');
final _versionPattern = RegExp(r'^[0-9]+\.[0-9]+\.[0-9]+$');
final _sha256Pattern = RegExp(r'^[0-9a-f]{64}$');

const _pngSignature = [137, 80, 78, 71, 13, 10, 26, 10];
const _iend = [0, 0, 0, 0, 73, 69, 78, 68, 174, 66, 96, 130];

/// A PNG's size, or why it isn't a PNG as Flutter's encoder writes one: the
/// signature, IHDR first with 8-bit RGBA and no interlace, IEND last.
({String? problem, int width, int height}) inspectPng(Uint8List bytes) {
  ({String? problem, int width, int height}) bad(String why) =>
      (problem: why, width: 0, height: 0);
  if (bytes.length < 8 + 25 + 12) return bad('too short for a PNG');
  for (var i = 0; i < 8; i++) {
    if (bytes[i] != _pngSignature[i]) return bad('not a PNG (no signature)');
  }
  final data = ByteData.sublistView(bytes);
  if (data.getUint32(8) != 13 ||
      String.fromCharCodes(bytes.sublist(12, 16)) != 'IHDR') {
    return bad('no IHDR chunk first');
  }
  final width = data.getUint32(16);
  final height = data.getUint32(20);
  if (width == 0 || height == 0) return bad('an empty image');
  final bitDepth = bytes[24];
  final colourType = bytes[25];
  if (bitDepth != 8 || colourType != 6) {
    return bad('not 8-bit RGBA (bit depth $bitDepth, colour type $colourType)');
  }
  if (bytes[28] != 0) return bad('interlaced');
  final end = bytes.sublist(bytes.length - 12);
  for (var i = 0; i < 12; i++) {
    if (end[i] != _iend[i]) return bad('no IEND chunk last');
  }
  return (problem: null, width: width, height: height);
}

String _sha256(List<int> bytes) => sha256.convert(bytes).toString();

String _base(String path) => path.replaceAll('\\', '/').split('/').last;

/// Every way [dir] differs from what goldens.yaml writes: only PNGs named by
/// the rule and manifest.json; each PNG listed with its sha256, size and
/// dimensions, and each listed PNG there. An empty list when they agree, and
/// when [dir] doesn't exist (no goldens yet).
List<String> checkGoldens(Directory dir) {
  if (!dir.existsSync()) return [];
  final problems = <String>[];
  final pngs = <String, File>{};
  File? manifest;
  for (final entity in dir.listSync(followLinks: false)) {
    final name = _base(entity.path);
    if (entity is! File) {
      problems.add('$name: only files belong in $goldensDir');
    } else if (name == manifestName) {
      manifest = entity;
    } else if (!name.endsWith('.png')) {
      problems.add('$name: only PNGs and $manifestName belong in $goldensDir');
    } else {
      pngs[name] = entity;
    }
  }
  if (manifest == null) {
    if (pngs.isNotEmpty) problems.add('$manifestName is missing');
    return problems;
  }
  Object? json;
  try {
    json = jsonDecode(manifest.readAsStringSync());
  } on FormatException catch (e) {
    return [...problems, '$manifestName: not JSON (${e.message})'];
  }
  if (json is! Map<String, dynamic>) {
    return [...problems, '$manifestName: not a JSON object'];
  }
  final Map<String, dynamic> top = json;
  void field(String key, RegExp pattern) {
    final value = top[key];
    if (value is! String || !pattern.hasMatch(value)) {
      problems.add('$manifestName: "$key" is missing or malformed');
    }
  }

  field('source_sha', _shaPattern);
  field('run_id', _digitsPattern);
  field('run_attempt', _digitsPattern);
  field('flutter', _versionPattern);
  final ref = top['ref'];
  if (ref is! String || ref.isEmpty) {
    problems.add('$manifestName: "ref" is missing');
  }
  final goldens = top['goldens'];
  if (goldens is! List) {
    return [...problems, '$manifestName: "goldens" is not a list'];
  }
  final listed = <String>{};
  for (final entry in goldens) {
    if (entry is! Map<String, dynamic>) {
      problems.add('$manifestName: an entry is not an object');
      continue;
    }
    final file = entry['file'];
    if (file is! String || !goldenNamePattern.hasMatch(file)) {
      problems.add(
        '$manifestName: "$file" is not <screen>_<state>_<light|dark>_<width>x<scale>.png',
      );
      continue;
    }
    if (!listed.add(file)) {
      problems.add('$manifestName: $file is listed twice');
      continue;
    }
    final state = entry['state'];
    if (state is! String || !stateIdPattern.hasMatch(state)) {
      problems.add('$file: "state" is not a state id such as A2');
    }
    final test = entry['test'];
    if (test is! String || test.trim().isEmpty) {
      problems.add('$file: "test" is missing');
    }
    final png = pngs[file];
    if (png == null) {
      problems.add('$file: listed in $manifestName but not in $goldensDir');
      continue;
    }
    final bytes = png.readAsBytesSync();
    final info = inspectPng(bytes);
    if (info.problem != null) {
      problems.add('$file: ${info.problem}');
      continue;
    }
    final hash = entry['sha256'];
    if (hash is! String || !_sha256Pattern.hasMatch(hash)) {
      problems.add('$file: "sha256" is missing or malformed');
    } else if (hash != _sha256(bytes)) {
      problems.add('$file: its sha256 is not the one in $manifestName');
    }
    if (entry['bytes'] != bytes.length) {
      problems.add('$file: its size is not the one in $manifestName');
    }
    if (entry['width'] != info.width || entry['height'] != info.height) {
      problems.add('$file: its dimensions are not the ones in $manifestName');
    }
  }
  for (final name in pngs.keys) {
    if (!listed.contains(name)) {
      problems.add('$name: in $goldensDir but not in $manifestName');
    }
  }
  return problems;
}

/// One golden as expectGolden reported it during the run.
typedef ReportedGolden = ({String file, String state, String test});

/// The goldens a JSON test report (`--file-reporter json:`) says were
/// rendered: each expectGolden line, with the full name of its test.
/// Throws a FormatException on a malformed golden line or a name used twice.
List<ReportedGolden> reportedGoldens(String report) {
  final tests = <int, String>{};
  final found = <ReportedGolden>[];
  final seen = <String>{};
  for (final line in const LineSplitter().convert(report)) {
    if (line.trim().isEmpty) continue;
    final Object? event;
    try {
      event = jsonDecode(line);
    } on FormatException {
      continue;
    }
    if (event is! Map<String, dynamic>) continue;
    if (event['type'] == 'testStart') {
      final test = event['test'];
      if (test is Map<String, dynamic> && test['id'] is int) {
        tests[test['id'] as int] = '${test['name']}';
      }
    }
    if (event['type'] != 'print') continue;
    final message = event['message'];
    if (message is! String || !message.startsWith(goldenMarker)) continue;
    final Object? body;
    try {
      body = jsonDecode(message.substring(goldenMarker.length));
    } on FormatException {
      throw FormatException('a malformed golden line: $message');
    }
    final file = body is Map ? body['file'] : null;
    final state = body is Map ? body['state'] : null;
    final test = tests[event['testID']];
    if (file is! String || state is! String || test == null) {
      throw FormatException(
        'a golden line without its file, state or test: $message',
      );
    }
    if (!seen.add(file)) {
      throw FormatException('$file was rendered twice');
    }
    found.add((file: file, state: state, test: test));
  }
  return found;
}

/// Writes the run's goldens and manifest to [out], from the package at
/// [root]: every PNG expectGolden rendered (written after [since]), and
/// nothing else. Returns the problems; nothing is written when there are any.
List<String> writeGoldens({
  required Directory root,
  required String report,
  required DateTime since,
  required Directory out,
  required Map<String, String> run,
}) {
  final List<ReportedGolden> reported;
  try {
    reported = reportedGoldens(report);
  } on FormatException catch (e) {
    return [e.message];
  }
  if (reported.isEmpty) {
    return ['no golden was rendered: is a test file tagged golden?'];
  }
  final problems = <String>[];
  final names = {for (final g in reported) g.file};
  for (final g in reported) {
    if (!goldenNamePattern.hasMatch(g.file)) {
      problems.add(
        '${g.file}: not <screen>_<state>_<light|dark>_<width>x<scale>.png',
      );
    }
    final png = File('${root.path}/$goldensDir/${g.file}');
    if (!png.existsSync() || !png.lastModifiedSync().isAfter(since)) {
      problems.add('${g.file}: reported but not written in this run');
    }
  }
  // A PNG this run wrote anywhere else came from a matchesGoldenFile call
  // that skipped expectGolden.
  final rootPath = root.path.replaceAll('\\', '/');
  final test = Directory('${root.path}/test');
  if (test.existsSync()) {
    for (final f in test.listSync(recursive: true, followLinks: false)) {
      if (f is! File || !f.path.endsWith('.png')) continue;
      if (!f.lastModifiedSync().isAfter(since)) continue;
      final path = f.path.replaceAll('\\', '/');
      final name = _base(path);
      if (path != '$rootPath/$goldensDir/$name' || !names.contains(name)) {
        problems.add(
          '${path.substring(rootPath.length + 1)}: written in this run, '
          'but not by expectGolden',
        );
      }
    }
  }
  if (problems.isNotEmpty) return problems;

  out.createSync(recursive: true);
  if (out.listSync().isNotEmpty) return ['${out.path} is not empty'];
  final entries = <Map<String, Object>>[];
  for (final g in [...reported]..sort((a, b) => a.file.compareTo(b.file))) {
    final bytes = File('${root.path}/$goldensDir/${g.file}').readAsBytesSync();
    final info = inspectPng(bytes);
    if (info.problem != null) return ['${g.file}: ${info.problem}'];
    File('${out.path}/${g.file}').writeAsBytesSync(bytes, flush: true);
    entries.add({
      'file': g.file,
      'state': g.state,
      'test': g.test,
      'sha256': _sha256(bytes),
      'bytes': bytes.length,
      'width': info.width,
      'height': info.height,
    });
  }
  final manifest = {
    'source_sha': run['sha'],
    'ref': run['ref'],
    'run_id': run['run-id'],
    'run_attempt': run['run-attempt'],
    'flutter': run['flutter'],
    'goldens': entries,
  };
  File('${out.path}/$manifestName').writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(manifest)}\n',
    flush: true,
  );
  // What was written passes the same check the committed folder must pass.
  return checkGoldens(out);
}

const _writeArgs = [
  'report',
  'since',
  'out',
  'sha',
  'ref',
  'run-id',
  'run-attempt',
  'flutter',
];

void main(List<String> args) {
  if (args.isEmpty || args.first != 'write' || args.length.isEven) {
    stderr.writeln(
      'usage: dart run tool/golden_manifest.dart write '
      '${_writeArgs.map((a) => '--$a <value>').join(' ')}',
    );
    exit(2);
  }
  final values = <String, String>{};
  for (var i = 1; i < args.length; i += 2) {
    final key = args[i].startsWith('--') ? args[i].substring(2) : '';
    if (!_writeArgs.contains(key)) {
      stderr.writeln('unknown argument ${args[i]}');
      exit(2);
    }
    values[key] = args[i + 1];
  }
  final missing = _writeArgs.where((a) => !values.containsKey(a)).toList();
  if (missing.isNotEmpty) {
    stderr.writeln('missing: ${missing.map((a) => '--$a').join(' ')}');
    exit(2);
  }
  final out = Directory(values['out']!);
  final problems = writeGoldens(
    root: Directory.current,
    report: File(values['report']!).readAsStringSync(),
    since: File(values['since']!).lastModifiedSync(),
    out: out,
    run: values,
  );
  if (problems.isNotEmpty) {
    for (final p in problems) {
      stderr.writeln('::error::$p');
    }
    exit(1);
  }
  final manifest =
      jsonDecode(File('${out.path}/$manifestName').readAsStringSync()) as Map;
  final goldens = manifest['goldens'] as List;
  stdout.writeln('### Goldens: ${goldens.length} PNGs from ${values['sha']}');
  stdout.writeln();
  stdout.writeln('| File | State | Test | sha256 |');
  stdout.writeln('|---|---|---|---|');
  for (final g in goldens.cast<Map>()) {
    final test = '${g['test']}'.replaceAll('|', r'\|');
    stdout.writeln(
      '| ${g['file']} | ${g['state']} | $test | ${'${g['sha256']}'.substring(0, 12)} |',
    );
  }
}
