#!/usr/bin/env bash
# Group A's paywall at large text alone (PA-3, flow 87c), kind=plus-rows,
# zone UTC: for a re-run of that one row without the rest of group-a.sh.
. "$(dirname "$0")/lib.sh"
guard_emulator

cleanup(){
  A shell settings put system font_scale 1.0 >/dev/null 2>&1
  echo "$(stamp) END: $PASSES pass, $FAILS fail"
  rows_exit
}
trap cleanup EXIT

install_verify || exit $?
A shell settings put system font_scale 2.0; sleep 2
if mf flows/pb1/87c_plus_paywall_large_text.yaml; then
  row PA-3 PASS "flow 87c: the paywall at font scale 2.0 (shots 87-paywall-x2, -plan-x2, -end-x2)"
else
  row PA-3 FAIL "flow 87c (font scale 2.0)"
fi
A shell settings put system font_scale 1.0
