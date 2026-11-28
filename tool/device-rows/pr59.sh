#!/usr/bin/env bash
# Days noted this week (#59) on the CI emulator, staging debug, run with
# zone=Asia/Bangkok and fake_now=2026-11-25T05:00:00Z (Wednesday 12:00 there):
# flow 77 (no line for one day; 2 days, 3 with a save; last week not counted),
# then flow 77b at font scale 2.0 for a look.
. "$(dirname "$0")/lib.sh"
guard_emulator

cleanup(){
  A shell settings put system font_scale 1.0 >/dev/null 2>&1
  echo "$(stamp) END: $PASSES pass, $FAILS fail"
  rows_exit
}
trap cleanup EXIT

install_verify || exit $?
echo "$(stamp) zone $(A shell getprop persist.sys.timezone | tr -d '\r')"
A shell settings put system font_scale 1.0

if mf flows/pb1/77_days_noted.yaml; then
  row DN-1 PASS "flow 77: one day no line; Monday added: 2 days; a Tuesday save: 3; last Sunday: still 3"
else
  row DN-1 FAIL "flow 77"
fi

A shell settings put system font_scale 2.0; sleep 2
echo "$(stamp) font_scale $(A shell settings get system font_scale | tr -d '\r')"
if mf flows/pb1/77b_days_noted_large_text.yaml; then
  row DN-2 PASS "flow 77b: the line at font scale 2.0 (shot 77-noted-x2)"
else
  row DN-2 FAIL "flow 77b (font scale 2.0)"
fi
A shell settings put system font_scale 1.0
