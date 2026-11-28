#!/usr/bin/env bash
# The sleepy pig at night (#53) on the CI emulator, staging debug, run with
# zone=Asia/Bangkok and fake_now=2026-11-28T16:00:00Z (the app's clock frozen
# at 23:00 there unless a fixture brings its own):
#   NP1  C14 (00:00) shows the night pig and line; C3 (12:00) as by day (flow 73)
#   NP2  a fresh Home at 23:00, a save's reaction kept across a tab switch, the
#        night line back after hiding and reopening (flow 74), light then dark
. "$(dirname "$0")/lib.sh"
guard_emulator

cleanup(){
  A shell cmd uimode night no >/dev/null 2>&1
  echo "$(stamp) END: $PASSES pass, $FAILS fail"
  rows_exit
}
trap cleanup EXIT

install_verify || exit $?
echo "$(stamp) zone $(A shell getprop persist.sys.timezone | tr -d '\r'); device date $(A shell date | tr -d '\r')"

A shell cmd uimode night no; sleep 2
if mf flows/pb1/73_night_pig_fixtures.yaml; then
  row NP1 PASS "flow 73: C14 sleepy + the night line; C3 happy + its day line (shots home-C14, home-C3)"
else
  row NP1 FAIL "flow 73"
fi

for mode in light dark; do
  if [ "$mode" = dark ]; then A shell cmd uimode night yes; else A shell cmd uimode night no; fi
  sleep 3
  if MF_NAME="74-$mode" mf flows/pb1/74_night_save.yaml -e MODE="$mode"; then
    row "NP2-$mode" PASS "flow 74 ($mode): night line at 23:00; a save's reaction across a tab switch; the night line after hide + reopen"
  else
    row "NP2-$mode" FAIL "flow 74 ($mode)"
  fi
done
