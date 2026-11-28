#!/usr/bin/env bash
# The store screenshots' device helpers (decision 34), for the tester's Play
# rows on the CI emulator; never run on a PC. Every adb call names the
# device, and only an emulator is accepted.
#
#   play_shots.sh display          1080 x 2160 at 420 dpi (Play's 2:1 limit)
#   play_shots.sh display reset
#   play_shots.sh demo on|off      a clean status bar: 12:00, full battery
#                                  and Wi-Fi, no mobile, no notifications,
#                                  no alarm, bluetooth, location, volume or
#                                  mute icons
#   play_shots.sh around CMD...    display + demo on, runs CMD, then always
#                                  demo off + display reset (EXIT trap)
#   play_shots.sh rgb DIR          every PNG in DIR as 8-bit RGB with no
#                                  alpha and no text chunks, 1080 x 2160,
#                                  under 8 MB (tool/play_png.dart); fails
#                                  loudly on any file that isn't
#
# env: SERIAL (default emulator-5554).
set -euo pipefail
SERIAL=${SERIAL:-emulator-5554}
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../.." && pwd)
A() { adb -s "$SERIAL" "$@"; }
case "$SERIAL" in
  emulator-*) ;;
  *) echo "REFUSING: '$SERIAL' is not an emulator serial"; exit 9 ;;
esac

display_on() {
  A shell wm size 1080x2160
  A shell wm density 420
  A shell wm size
  A shell wm density
}

display_reset() {
  A shell wm size reset || true
  A shell wm density reset || true
}

demo() { A shell am broadcast -a com.android.systemui.demo -e command "$@" > /dev/null; }

demo_on() {
  A shell settings put global sysui_demo_allowed 1
  demo enter
  demo clock -e hhmm 1200
  demo battery -e level 100 -e plugged false
  demo network -e wifi show -e level 4 -e fully true
  demo network -e mobile hide
  demo notifications -e visible false
  demo status -e alarm hide -e bluetooth hide -e location hide -e volume hide -e mute hide
  echo "demo mode on"
}

demo_off() {
  demo exit || true
  A shell settings put global sysui_demo_allowed 0 || true
  echo "demo mode off"
}

case "${1:-}" in
  display)
    if [[ "${2:-}" == reset ]]; then display_reset; else display_on; fi
    ;;
  demo)
    case "${2:-}" in
      on) demo_on ;;
      off) demo_off ;;
      *) echo "usage: play_shots.sh demo on|off"; exit 2 ;;
    esac
    ;;
  around)
    shift
    [[ $# -gt 0 ]] || { echo "usage: play_shots.sh around CMD..."; exit 2; }
    trap 'demo_off; display_reset' EXIT
    display_on
    demo_on
    "$@"
    ;;
  rgb)
    [[ -n "${2:-}" ]] || { echo "usage: play_shots.sh rgb DIR"; exit 2; }
    dir=$(cd "$2" && pwd)
    (cd "$ROOT" && dart run tool/play_png.dart "$dir" 1080 2160)
    ;;
  *)
    echo "usage: play_shots.sh display [reset] | demo on|off | around CMD... | rgb DIR"
    exit 2
    ;;
esac
