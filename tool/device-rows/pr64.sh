#!/usr/bin/env bash
# How did yesterday feel? (#64) on the CI emulator, staging debug, run with
# zone UTC and fake_now=2026-11-28T05:00:00Z (yesterday = Friday 27):
# 82a (three rows at most; answers set feelings), 82b at font scale 2.0 (a
# look), 82c (Me's switch; "Not now" for the day, also after a relaunch).
. "$(dirname "$0")/lib.sh"
guard_emulator

cleanup(){
  A shell settings put system font_scale 1.0 >/dev/null 2>&1
  echo "$(stamp) END: $PASSES pass, $FAILS fail"
  rows_exit
}
trap cleanup EXIT

install_verify || exit $?
A shell settings put system font_scale 1.0

if mf flows/pb1/82a_yesterday_feel.yaml; then
  row YF-1 PASS "flow 82a: four of yesterday's spends, three rows at most; answers set the feelings (Timeline shows them); the fourth comes in; one left"
else
  row YF-1 FAIL "flow 82a"
fi

A shell settings put system font_scale 2.0; sleep 2
if mf flows/pb1/82b_yesterday_large_text.yaml; then
  row YF-2 PASS "flow 82b: the card at font scale 2.0 (shot 82-card-x2)"
else
  row YF-2 FAIL "flow 82b (font scale 2.0)"
fi
A shell settings put system font_scale 1.0; sleep 2

if mf flows/pb1/82c_yesterday_off_later.yaml; then
  row YF-3 PASS "flow 82c: Me's switch hides and brings back the card; Not now hides it for the day, also after a relaunch"
else
  row YF-3 FAIL "flow 82c"
fi
