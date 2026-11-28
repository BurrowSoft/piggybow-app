#!/usr/bin/env bash
# Group A + A′ (the Plus line and themes), retroactively on master (decision
# 86), kind=plus-rows, zone UTC, the real clock. Plus stays off: the fake
# store never owns anything, so the Plus-on states stay on the widget tests and
# goldens until the rows-only grant lands.
#   PA-1 flow 87a: the paywall, Start and Restore buy nothing, Back
#   PA-2 flow 87b: the gates (second goal, own category, Plus theme) and the
#        free hiding of a built-in category
#   PA-3 flow 87c: the paywall at font scale 2.0, for a look
#   PA-4 the smoke and the journal still pass in a build with Plus enabled
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

if mf flows/pb1/87a_plus_paywall.yaml; then
  row PA-1 PASS "flow 87a: Me's Plus row opens the paywall; 'stays free', three benefits, the yearly plan with its free week; Start and Restore buy nothing (no plus-on; 'No Plus subscription was found'); Back closes it"
else
  row PA-1 FAIL "flow 87a"
fi

if mf flows/pb1/87b_plus_gates.yaml; then
  row PA-2 PASS "flow 87b: a second goal, Add category and the Plum theme each open the paywall and change nothing; hiding Transport is free (gone from Add, shown again)"
else
  row PA-2 FAIL "flow 87b"
fi

A shell settings put system font_scale 2.0; sleep 2
if mf flows/pb1/87c_plus_paywall_large_text.yaml; then
  row PA-3 PASS "flow 87c: the paywall at font scale 2.0 (shots 87-paywall-x2, -plan-x2, -end-x2)"
else
  row PA-3 FAIL "flow 87c (font scale 2.0)"
fi
A shell settings put system font_scale 1.0

if mf flows/pb1/00_smoke_launch.yaml && mf flows/pb1/10_journal_loop.yaml; then
  row PA-4 PASS "flows 00 and 10 in a build with Plus enabled"
else
  row PA-4 FAIL "flows 00/10 with Plus enabled"
fi
