#!/usr/bin/env bash
# A goal's target date and pace (#60) on the CI emulator, staging debug, run
# with zone UTC and fake_now=2026-11-28T05:00:00Z (Saturday 28 November):
# flow 79a (the form's date, the target line, the pace line, Edit keeps it),
# 79b at font scale 2.0 (a look), 79c (no line when reached or over 52 weeks).
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

if mf flows/pb1/79a_goal_target_pace.yaml; then
  row TD-1 PASS "flow 79a: no date row in O3; today not pickable; x removes the date; 'Target: Nov 30, 2026' with no saves; 'About 12 weeks to go at this pace' after a 225 save; Edit keeps the date"
else
  row TD-1 FAIL "flow 79a"
fi

A shell settings put system font_scale 2.0; sleep 2
if mf flows/pb1/79b_goal_pace_large_text.yaml; then
  row TD-2 PASS "flow 79b: the pace line and the form's date at font scale 2.0 (shots 79-pace-line-x2, 79-form-date-x2)"
else
  row TD-2 FAIL "flow 79b (font scale 2.0)"
fi
A shell settings put system font_scale 1.0; sleep 2

if mf flows/pb1/79c_goal_pace_none.yaml; then
  row TD-3 PASS "flow 79c: no line once reached; no line for a pace over 52 weeks"
else
  row TD-3 FAIL "flow 79c"
fi
