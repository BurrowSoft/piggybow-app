import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// tool/emulator/net_control.sh, net_bytes.sh's positive control, against a
/// fake adb whose "device" reaches the runner the way the emulator does (its
/// 10.0.2.2 is the runner's 127.0.0.1): the listener's one-off token comes
/// back, the shell's uid is read from the device (0 under adb root), a fetch
/// that doesn't arrive stops the run, and the listener and its folder are
/// gone afterwards.
void main() {
  final tools = (Platform.isLinux || Platform.isMacOS) && _runs('python3') && _runs('curl');
  late Directory dir;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('net-control');
    // Only what net_control.sh asks, of the named emulator only.
    File('${dir.path}/adb').writeAsStringSync(r'''#!/usr/bin/env bash
[ "$1" = -s ] && [ "$2" = emulator-5554 ] && [ "$3" = shell ] || { echo "fake adb: unexpected $*" >&2; exit 2; }
shift 3
cmd="$*"
case "$cmd" in
  "id -u") echo "${SHELL_UID:-2000}" ;;
  "printf 'GET /control.txt HTTP/1.0\r\n\r\n' | nc -w 3 10.0.2.2 "*)
    [ -z "${OFFLINE:-}" ] || exit 1
    curl -s -i "http://127.0.0.1:${cmd##* }/control.txt" ;;
  *) echo "fake adb: unexpected shell $cmd" >&2; exit 2 ;;
esac
''');
    // A caller, as plus_probe.sh is one.
    File('${dir.path}/caller.sh').writeAsStringSync(r'''set -Eeuo pipefail
A() { adb -s emulator-5554 "$@"; }
. "$NET_CONTROL"
trap control_stop EXIT
control_start
echo "dir $CONTROL_DIR"
control_fetch before
echo "measured uid $CONTROL_UID"
''');
    if (tools) Process.runSync('chmod', ['+x', '${dir.path}/adb']);
  });
  tearDown(() => dir.deleteSync(recursive: true));

  Future<(ProcessResult, int)> run({String? shellUid, bool offline = false}) async {
    final free = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = free.port;
    await free.close();
    final r = await Process.run(
      'bash',
      ['${dir.path}/caller.sh'],
      environment: {
        'PATH': '${dir.path}:${Platform.environment['PATH']}',
        'NET_CONTROL': File('tool/emulator/net_control.sh').absolute.path,
        'CONTROL_PORT': '$port',
        'SHELL_UID': ?shellUid,
        if (offline) 'OFFLINE': '1',
      },
    );
    return (r, port);
  }

  Future<bool> listening(int port) async {
    try {
      final s = await Socket.connect('127.0.0.1', port, timeout: const Duration(milliseconds: 300));
      s.destroy();
      return true;
    } on SocketException {
      return false;
    }
  }

  // After the caller ends: its folder deleted, its listener stopped.
  Future<void> cleanedUp(ProcessResult r, int port) async {
    final folder = RegExp(r'^dir (.+)$', multiLine: true).firstMatch('${r.stdout}')?.group(1);
    expect(folder, isNotNull, reason: '${r.stdout}${r.stderr}');
    expect(Directory(folder!).existsSync(), isFalse);
    for (var i = 0; i < 20 && await listening(port); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    expect(await listening(port), isFalse, reason: 'the listener outlived its caller');
  }

  test("the shell's fetch arrives: its uid, and nothing left running", () async {
    final (r, port) = await run();
    expect(r.exitCode, 0, reason: '${r.stdout}${r.stderr}');
    expect(r.stdout, contains('control before: uid 2000 fetched the token from the runner\n'));
    expect(r.stdout, contains('measured uid 2000\n'));
    await cleanedUp(r, port);
  }, skip: tools ? false : 'needs bash, python3 and curl');

  test('under adb root the shell is uid 0, and that uid is the one measured', () async {
    final (r, port) = await run(shellUid: '0');
    expect(r.exitCode, 0, reason: '${r.stdout}${r.stderr}');
    expect(r.stdout, contains('control before: uid 0 fetched the token from the runner\n'));
    expect(r.stdout, contains('measured uid 0\n'));
    await cleanedUp(r, port);
  }, skip: tools ? false : 'needs bash, python3 and curl');

  test("a fetch that doesn't arrive: a loud stop", () async {
    final (r, port) = await run(offline: true);
    expect(r.exitCode, 8, reason: '${r.stdout}${r.stderr}');
    expect(r.stdout, contains("STOP: control before: the device's fetch from the runner didn't arrive"));
    expect(r.stdout, isNot(contains('measured uid')));
    await cleanedUp(r, port);
  }, skip: tools ? false : 'needs bash, python3 and curl');

  test('an unreadable shell uid: a loud stop', () async {
    final (r, port) = await run(shellUid: 'nobody');
    expect(r.exitCode, 8, reason: '${r.stdout}${r.stderr}');
    expect(r.stdout, contains("STOP: control before: the device's shell uid can't be read (nobody)"));
    await cleanedUp(r, port);
  }, skip: tools ? false : 'needs bash, python3 and curl');
}

bool _runs(String exe) {
  try {
    return Process.runSync(exe, ['--version']).exitCode == 0;
  } on ProcessException {
    return false;
  }
}
