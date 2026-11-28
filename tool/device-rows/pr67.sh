#!/usr/bin/env bash
# The monthly letter (#67) on the CI emulator, staging debug, run with zone
# UTC and fake_now=2026-12-02T05:00:00Z (Wednesday 2 December): 85a (none
# without November entries; November's letter: saves, worth it, days; Me's
# switch), 85b at font scale 2.0 (a look), 85c ("Thanks!" for the month).
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

if mf flows/pb1/85a_monthly_letter.yaml; then
  row ML-1 PASS "flow 85a: no letter without November entries; 'Your November': You saved \$100.00, Food & drinks most worth it, 3 days, no goal line; Me's switch hides and brings it back"
else
  row ML-1 FAIL "flow 85a"
fi

A shell settings put system font_scale 2.0; sleep 2
if mf flows/pb1/85b_letter_large_text.yaml; then
  row ML-2 PASS "flow 85b: the letter at font scale 2.0 (shots 85-letter-x2, -end)"
else
  row ML-2 FAIL "flow 85b (font scale 2.0)"
fi
A shell settings put system font_scale 1.0; sleep 2

if mf flows/pb1/85c_letter_thanks.yaml; then
  row ML-3 PASS "flow 85c: Thanks! puts it away for the month, also after a relaunch"
else
  row ML-3 FAIL "flow 85c"
fi
