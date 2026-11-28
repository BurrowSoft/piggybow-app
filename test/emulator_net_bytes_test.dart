import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// tool/emulator/net_bytes.sh, run against a fake adb: one uid's bytes from
/// netstats; zero when the uid has no entries at all (an app that never
/// touched the network); a loud stop when the app isn't installed, so "no
/// lines" never passes for "zero bytes".
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

  Future<ProcessResult> run(String sample, {bool installed = true}) {
    final file = File('${dir.path}/sample.txt')..writeAsStringSync(sample);
    return Process.run(
      'bash',
      ['tool/emulator/net_bytes.sh', 'emulator-5554', 'com.burrowsoft.piggybow', '${dir.path}/out.txt'],
      environment: {
        'PATH': '${dir.path}:${Platform.environment['PATH']}',
        'SAMPLE': file.path,
        if (installed) 'HAS_APP': '1',
      },
    );
  }

  test("one uid's own lines and bytes; another app's and tagged entries left out", () async {
    final r = await run(withUid);
    expect(r.exitCode, 0, reason: '${r.stdout}${r.stderr}');
    expect(r.stdout, 'uid 10146: rx 1250 tx 320\n');
    final out = File('${dir.path}/out.txt').readAsStringSync();
    expect(out, contains(' uid=10146 '));
    expect(out, isNot(contains('uid=10147')));
    expect(out, isNot(contains('tag=0xffffff01')));
  }, skip: bash ? false : 'needs bash');

  test('a uid with no netstats entries at all: zero bytes, and exit 0', () async {
    final r = await run(withoutUid);
    expect(r.exitCode, 0, reason: '${r.stdout}${r.stderr}');
    expect(r.stdout, 'uid 10146: rx 0 tx 0\n');
    expect(File('${dir.path}/out.txt').readAsStringSync(), isEmpty);
  }, skip: bash ? false : 'needs bash');

  test('no such package: a loud stop, never zero bytes', () async {
    final r = await run(withUid, installed: false);
    expect(r.exitCode, 8, reason: '${r.stdout}${r.stderr}');
    expect(r.stdout, contains('STOP: no uid for com.burrowsoft.piggybow'));
    expect(r.stdout, isNot(contains('rx ')));
    expect(File('${dir.path}/out.txt').existsSync(), isFalse);
  }, skip: bash ? false : 'needs bash');
}
