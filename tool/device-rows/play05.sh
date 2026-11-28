#!/usr/bin/env bash
# Play shot 5 again (Timeline, Today and Yesterday only), as in play.sh: the
# STORE1 fixture on a staging build, 1080 x 1920 (9:16) at 420 dpi, Android's
# demo-mode status bar; flow 64 deletes the three older entries through the
# app first. The PNG is then rewritten as 8-bit RGB with no alpha and no text
# chunks and checked at 1080 x 1920 (the head's tool/play_png.dart).
# Run by tool/emulator/run.sh with rows=play05.
. "$(dirname "$0")/lib.sh"
guard_emulator

W=1080; H=1920; DPI=420
APPDIR="${GITHUB_WORKSPACE:?}/app"
PS="$APPDIR/tool/emulator/play_shots.sh"
[ -f "$PS" ] || { echo "STOP: no tool/emulator/play_shots.sh at the head ($PS)"; exit 2; }
[ -f "$APPDIR/tool/play_png.dart" ] || { echo "STOP: no tool/play_png.dart at the head"; exit 2; }
ps(){ SERIAL="$SERIAL" bash "$PS" "$@"; }
SHOTS="$OUT/play"
mkdir -p "$SHOTS"

cleanup(){
  ps demo off >/dev/null 2>&1
  A shell wm size reset >/dev/null 2>&1
  A shell wm density reset >/dev/null 2>&1
  echo "$(stamp) display: $(A shell wm size | tr -d '\r' | tr '\n' ' ')"
  echo "$(stamp) END: $PASSES pass, $FAILS fail (the shot decides)"
  rows_exit
}
trap cleanup EXIT

install_verify || exit $?
A shell wm size "${W}x${H}"; A shell wm density "$DPI"
echo "$(stamp) display: $(A shell wm size | tr -d '\r' | tr '\n' ' ') / $(A shell wm density | tr -d '\r' | tr '\n' ' ')"
ps demo on

if mf flows/play/64_play_timeline.yaml; then row P-64 PASS "flow 64_play_timeline (three older entries deleted, two days left)"; else row P-64 FAIL "flow 64_play_timeline"; fi

find "$OUT/maestro" -type f -name 'play-05-timeline.png' -exec cp {} "$SHOTS/" \;
n=$(find "$SHOTS" -maxdepth 1 -name 'play-0*.png' | wc -l)
if [ "$n" = 1 ]; then row P-files PASS "1 PNG: play-05-timeline.png"; else row P-files FAIL "$n PNGs (expected 1)"; fi
if (cd "$APPDIR" && dart run tool/play_png.dart "$SHOTS" "$W" "$H"); then
  row P-rgb PASS "8-bit RGB, no alpha, no text chunks, ${W} x ${H}, < 8 MB"
else
  row P-rgb FAIL "play_png.dart refused the file (see the log above)"
fi
ls -l "$SHOTS"
