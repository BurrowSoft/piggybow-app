#!/usr/bin/env bash
# Quick amounts (#57) on the CI emulator, staging debug, zone UTC: flow 75
# (the chips, a tap that saves nothing, other categories, Saved, editing),
# then flow 75b at font scale 2.0 (the chips wrapping), for a look.
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

if mf flows/pb1/75_quick_amounts.yaml; then
  row QA-1 PASS "flow 75: Food's chips 80, 45, 125 (once each, at most 3, 'Use \$80.00'); a tap fills the amount, caret at the end, saves nothing; Add saves it; Transport's own chip; none for Groceries, Saved, editing"
else
  row QA-1 FAIL "flow 75"
fi

A shell settings put system font_scale 2.0; sleep 2
echo "$(stamp) font_scale $(A shell settings get system font_scale | tr -d '\r')"
if mf flows/pb1/75b_quick_amounts_large_text.yaml; then
  row QA-2 PASS "flow 75b: the three chips at font scale 2.0 (shot 75-food-chips-x2)"
else
  row QA-2 FAIL "flow 75b (font scale 2.0)"
fi
A shell settings put system font_scale 1.0; sleep 2

# Asked by PB UX & PM (not #57's own row): the lock screen's status bar on a
# head with #36, as it appears and 2 s and 5 s after it settles
if mf flows/pb1/78_lock_statusbar.yaml; then
  sleep 2; snap 78-lock-2s
  sleep 3; snap 78-lock-5s
  echo "$(stamp) status-bar appearance: $(A shell dumpsys window | tr -d '\r' | grep -m3 -iE 'appearance|LIGHT_STATUS' | tr -s ' ' | tr '\n' ' ')"
  row LS-1 INFO "lock screen shots 78-lock-0s, 78-lock-2s, 78-lock-5s (LOOK: all four status icons dark on the light page)"
else
  row LS-1 FAIL "flow 78 (the lock screen after a cold start)"
fi
