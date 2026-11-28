import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// tool/emulator/play_shots.sh, the store screenshots' device helpers
/// (decision 34): CI emulator only, every adb call naming the device, the
/// status bar cleaned and the display at Play's 2:1, both always put back.
void main() {
  final script = File('tool/emulator/play_shots.sh').readAsStringSync();
  final lines = script.split('\n');

  test('every adb call names the device, and only an emulator', () {
    final adb = [
      for (final l in lines)
        if (RegExp(r'\badb\b').hasMatch(l) && !l.trimLeft().startsWith('#')) l,
    ];
    expect(adb, [r'A() { adb -s "$SERIAL" "$@"; }']);
    expect(script, contains('emulator-*) ;;'));
    expect(script, contains("is not an emulator serial"));
    expect(script, contains(r'SERIAL=${SERIAL:-emulator-5554}'));
  });

  test("the display: 1080 x 2160 at 420 dpi, Play's 2:1 at most", () {
    expect(script, contains('wm size 1080x2160'));
    expect(script, contains('wm density 420'));
    expect(script, contains('wm size reset'));
    expect(script, contains('wm density reset'));
  });

  test('demo mode: the clock at 12:00, full battery and Wi-Fi, no icons', () {
    for (final part in [
      'sysui_demo_allowed 1',
      'demo enter',
      'demo clock -e hhmm 1200',
      'demo battery -e level 100 -e plugged false',
      'demo network -e wifi show -e level 4 -e fully true',
      'demo network -e mobile hide',
      'demo notifications -e visible false',
      'demo status -e alarm hide -e bluetooth hide -e location hide '
          '-e volume hide -e mute hide',
      'demo exit',
      'sysui_demo_allowed 0',
    ]) {
      expect(script, contains(part), reason: part);
    }
  });

  test('around: set up, then always put back, even when the command fails', () {
    final around = script.substring(script.indexOf('  around)'));
    final trap = around.indexOf("trap 'demo_off; display_reset' EXIT");
    expect(trap, greaterThan(0));
    expect(trap, lessThan(around.indexOf('display_on')));
    expect(script, startsWith('#!/usr/bin/env bash'));
    expect(script, contains('set -euo pipefail'));
  });

  test('rgb: every PNG through tool/play_png.dart at 1080 x 2160', () {
    expect(script, contains('dart run tool/play_png.dart "\$dir" 1080 2160'));
  });
}
