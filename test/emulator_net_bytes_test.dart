import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// tool/emulator/net_bytes.sh, run against a fake adb: one uid's bytes from
/// netstats; zero when the uid has no entries at all (an app that never
/// touched the network); a loud stop when the app isn't installed, when the
/// dump is empty, or when the control uid (one the caller has just made
/// talk) shows no bytes, so a reading that couldn't see traffic never passes
/// for "zero bytes".
void main() {
  final bash = Platform.isLinux || Platform.isMacOS;
  late Directory dir;

  // netstats' layout: our uid (10146) with two buckets, another app's, and
  // one of ours under a tag (counted inside the tag 0x0 total already).
  const withUid = r'''
UID stats:
  Pending bytes: 0
  History since boot:
  ident=[{type=WIFI, ratType=COMBINED, networkId="AndroidWifi", metered=false, defaultNetwork=true}] uid=10146 set=DEFAULT tag=0x0
    NetworkStatsHistory: bucketDuration=7200
      st=1764316800 rb=1200 rp=10 tb=300 tp=4 op=0
      st=1764324000 rb=50 rp=1 tb=20 tp=1 op=0
  ident=[{type=WIFI, ratType=COMBINED, networkId="AndroidWifi", metered=false, defaultNetwork=true}] uid=10147 set=DEFAULT tag=0x0
    NetworkStatsHistory: bucketDuration=7200
      st=1764316800 rb=99999 rp=10 tb=88888 tp=4 op=0
UID tag stats:
  ident=[{type=WIFI}] uid=10146 set=DEFAULT tag=0xffffff01
    NetworkStatsHistory: bucketDuration=7200
      st=1764316800 rb=777 rp=1 tb=777 tp=1 op=0
''';

  // The same, with the shell's control fetch (uid 2000) in it.
  const withControl = '''
${withUid}UID stats, again:
  ident=[{type=WIFI, ratType=COMBINED, networkId="AndroidWifi", metered=false, defaultNetwork=true}] uid=2000 set=DEFAULT tag=0x0
    NetworkStatsHistory: bucketDuration=7200
      st=1764316800 rb=600 rp=5 tb=80 tp=3 op=0
''';

  // An app that never touched the network: no entry for its uid at all.
  const withoutUid = r'''
UID stats:
  Pending bytes: 0
  History since boot:
  ident=[{type=WIFI, ratType=COMBINED, networkId="AndroidWifi", metered=false, defaultNetwork=true}] uid=10147 set=DEFAULT tag=0x0
    NetworkStatsHistory: bucketDuration=7200
      st=1764316800 rb=99999 rp=10 tb=88888 tp=4 op=0
''';

  setUp(() {
    dir = Directory.systemTemp.createTempSync('net-bytes');
    // A fake adb that answers only what net_bytes.sh asks, for the named
    // emulator only: anything else fails the test.
    File('${dir.path}/adb').writeAsStringSync(r'''#!/usr/bin/env bash
[ "$1" = -s ] && [ "$2" = emulator-5554 ] && [ "$3" = shell ] || { echo "fake adb: unexpected $*" >&2; exit 2; }
shift 3
case "$*" in
  "cmd package list packages -U com.burrowsoft.piggybow")
    if [ -n "${HAS_APP:-}" ]; then echo "package:com.burrowsoft.piggybow uid:10146"; fi ;;
  "dumpsys netstats --poll") echo "Forced poll" ;;
  "dumpsys netstats detail") cat "$SAMPLE" ;;
  *) echo "fake adb: unexpected shell $*" >&2; exit 2 ;;
esac
''');
    if (bash) Process.runSync('chmod', ['+x', '${dir.path}/adb']);
  });
  tearDown(() => dir.deleteSync(recursive: true));

  Future<ProcessResult> run(String sample, {bool installed = true, String? control}) {
    final file = File('${dir.path}/sample.txt')..writeAsStringSync(sample);
    return Process.run(
      'bash',
      [
        'tool/emulator/net_bytes.sh',
        'emulator-5554',
        'com.burrowsoft.piggybow',
        '${dir.path}/out.txt',
        ?control,
      ],
      environment: {
        'PATH': '${dir.path}:${Platform.environment['PATH']}',
        'SAMPLE': file.path,
        if (installed) 'HAS_APP': '1',
      },
    );
  }

  // The app's own line is the only one that starts with "uid ".
  final appLine = RegExp(r'^uid ', multiLine: true);
  File out() => File('${dir.path}/out.txt');

  test("one uid's own lines and bytes; another app's and tagged entries left out", () async {
    final r = await run(withUid);
    expect(r.exitCode, 0, reason: '${r.stdout}${r.stderr}');
    expect(r.stdout, 'netstats entries: 3\nuid 10146: rx 1250 tx 320\n');
    final lines = out().readAsStringSync();
    expect(lines, contains(' uid=10146 '));
    expect(lines, isNot(contains('uid=10147')));
    expect(lines, isNot(contains('tag=0xffffff01')));
  }, skip: bash ? false : 'needs bash');

  test('a uid with no netstats entries at all: zero bytes, and exit 0', () async {
    final r = await run(withoutUid);
    expect(r.exitCode, 0, reason: '${r.stdout}${r.stderr}');
    expect(r.stdout, 'netstats entries: 1\nuid 10146: rx 0 tx 0\n');
    expect(out().readAsStringSync(), isEmpty);
  }, skip: bash ? false : 'needs bash');

  test('no such package: a loud stop, never zero bytes', () async {
    final r = await run(withUid, installed: false);
    expect(r.exitCode, 8, reason: '${r.stdout}${r.stderr}');
    expect(r.stdout, contains('STOP: no uid for com.burrowsoft.piggybow'));
    expect(r.stdout, isNot(contains('rx ')));
    expect(out().existsSync(), isFalse);
  }, skip: bash ? false : 'needs bash');

  test('an empty dump: a loud stop, never zero bytes', () async {
    final r = await run('');
    expect(r.exitCode, 8, reason: '${r.stdout}${r.stderr}');
    expect(r.stdout, 'netstats entries: 0\nSTOP: netstats printed no entries\n');
    expect(r.stdout, isNot(contains('rx ')));
    expect(out().existsSync(), isFalse);
  }, skip: bash ? false : 'needs bash');

  test("the control uid's bytes, then the app's, and only the app's lines kept", () async {
    final r = await run(withControl, control: '2000');
    expect(r.exitCode, 0, reason: '${r.stdout}${r.stderr}');
    expect(r.stdout, 'netstats entries: 4\ncontrol uid 2000: rx 600 tx 80\nuid 10146: rx 1250 tx 320\n');
    expect(appLine.allMatches(r.stdout as String), hasLength(1));
    expect(out().readAsStringSync(), isNot(contains('uid=2000')));
  }, skip: bash ? false : 'needs bash');

  test('a silent control uid: a loud stop, and no app line', () async {
    final r = await run(withUid, control: '2000');
    expect(r.exitCode, 8, reason: '${r.stdout}${r.stderr}');
    expect(
      r.stdout,
      'netstats entries: 3\ncontrol uid 2000: rx 0 tx 0\nSTOP: the control uid 2000 shows no bytes\n',
    );
    expect(appLine.hasMatch(r.stdout as String), isFalse);
    expect(out().existsSync(), isFalse);
  }, skip: bash ? false : 'needs bash');
}
