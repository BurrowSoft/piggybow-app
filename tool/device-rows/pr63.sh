#!/usr/bin/env bash
# Gentle comparisons on Summary (#63) on the CI emulator, staging debug, run
# with zone=Asia/Bangkok and fake_now=2026-11-27T05:00:00Z (Friday 12:00
# there): flow 81 (this week so far, the previous week, a new category, Month,
# saves), then flow 81b at font scale 2.0 for a look.
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

if mf flows/pb1/81_gentle_compare.yaml; then
  row GC-1 PASS "flow 81: so far - Food same (last Saturday not counted), Transport more, Fun less, Groceries none, Shopping not mentioned; previous week - Transport same, new ones none; Month none; a save ignored"
else
  row GC-1 FAIL "flow 81"
fi

A shell settings put system font_scale 2.0; sleep 2
if mf flows/pb1/81b_gentle_compare_large_text.yaml; then
  row GC-2 PASS "flow 81b: the lines at font scale 2.0 (shot 81-week-so-far-x2)"
else
  row GC-2 FAIL "flow 81b (font scale 2.0)"
fi
A shell settings put system font_scale 1.0
