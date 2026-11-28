#!/usr/bin/env bash
# Take money out of savings (#61) on the CI emulator, staging debug, zone UTC,
# the real clock: flow 86a (refused when more than saved; $50 taken out on the
# goal, Timeline and Summary; deleted from the goal), then 86b at font scale
# 2.0 (the sheet's refusal wrapping) for a look.
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

if mf flows/pb1/86a_take_out.yaml; then
  row TO-1 PASS "flow 86a: no Take out before savings; \$300 of \$200 refused; \$50 taken out: the goal's row, Timeline 'Taken out of Bike', Summary 'Taken out \$50.00'; deleted from the goal: row and Summary line gone"
else
  row TO-1 FAIL "flow 86a"
fi

A shell settings put system font_scale 2.0; sleep 2
if mf flows/pb1/86b_take_out_large_text.yaml; then
  row TO-2 PASS "flow 86b: the refusal at font scale 2.0 (shot 86-too-much-x2)"
else
  row TO-2 FAIL "flow 86b (font scale 2.0)"
fi
A shell settings put system font_scale 1.0
