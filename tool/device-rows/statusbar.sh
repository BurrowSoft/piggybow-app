#!/usr/bin/env bash
# Status-bar shots on the CI emulator: the top of O1 and of the goal
# celebration, in light and in night mode, for PB UX & PM's look. The rows
# record that the shots were taken; the verdict is the look at them.
# Run by tool/emulator/run.sh with rows=statusbar (it exports APK, HEAD_SHA,
# OUT, SERIAL, APP_ID, KIND and FLOWS).
. "$(dirname "$0")/lib.sh"
guard_emulator

cleanup(){
  A shell cmd uimode night no >/dev/null 2>&1
  echo "$(stamp) END: $PASSES pass, $FAILS fail (the shots decide)"
}
trap cleanup EXIT

install_verify || exit $?

for mode in light dark; do
  if [ "$mode" = dark ]; then A shell cmd uimode night yes; else A shell cmd uimode night no; fi
  sleep 3
  echo "$(stamp) uimode: $(A shell cmd uimode night | tr -d '\r')"
  if MF_NAME="50-$mode" mf flows/pb1/50_status_bar_shots.yaml -e MODE="$mode"; then
    row "SB-$mode" PASS "shots 50-o1-$mode and 50-celebration-$mode taken (LOOK: see-through bar, icon colour)"
  else
    row "SB-$mode" FAIL "flow 50 in $mode mode"
  fi
done
