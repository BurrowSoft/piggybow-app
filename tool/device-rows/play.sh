#!/usr/bin/env bash
# The Play phone screenshots on the CI emulator (decision 34): six flows on the
# STORE1 / STORE2 fixtures (staging builds only) and a fresh O1, at 1080 x 1920
# (9:16) and 420 dpi with Android's demo-mode status bar. The PNGs are then
# rewritten as 8-bit RGB with no alpha and no text chunks, and checked at
# 1080 x 1920 (the head's tool/play_png.dart). The verdict is the tester's look
# at all six, then PB UX & PM's; the upload is the owner's.
# Run by tool/emulator/run.sh with rows=play (it exports APK, HEAD_SHA, OUT,
# SERIAL, APP_ID, KIND and FLOWS). The helpers come from the head's checkout.
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
  echo "$(stamp) END: $PASSES pass, $FAILS fail (the six shots decide)"
  rows_exit
}
trap cleanup EXIT

install_verify || exit $?
# 9:16 for the store (the helper's own size is 2:1): set here, reset in the trap
A shell wm size "${W}x${H}"; A shell wm density "$DPI"
echo "$(stamp) display: $(A shell wm size | tr -d '\r' | tr '\n' ' ') / $(A shell wm density | tr -d '\r' | tr '\n' ' ')"
ps demo on

for f in 60_play_home 61_play_add 62_play_summary 63_play_goal_reached 64_play_timeline 65_play_welcome; do
  if mf "flows/play/$f.yaml"; then row "P-${f:0:2}" PASS "flow $f"; else row "P-${f:0:2}" FAIL "flow $f"; fi
done

# The six PNGs, by name, into one folder; then RGB + the checks at 1080 x 1920.
find "$OUT/maestro" -type f -name 'play-0*.png' -exec cp {} "$SHOTS/" \;
n=$(find "$SHOTS" -maxdepth 1 -name 'play-0*.png' | wc -l)
if [ "$n" = 7 ]; then row P-files PASS "7 PNGs (shot 2 in two candidates): $(cd "$SHOTS" && ls play-0*.png | tr '\n' ' ')"; else row P-files FAIL "$n PNGs (expected 7: six shots, shot 2 in two candidates)"; fi
if (cd "$APPDIR" && dart run tool/play_png.dart "$SHOTS" "$W" "$H"); then
  row P-rgb PASS "every PNG 8-bit RGB, no alpha, no text chunks, ${W} x ${H}, < 8 MB"
else
  row P-rgb FAIL "play_png.dart refused a file (see the log above)"
fi
ls -l "$SHOTS"
