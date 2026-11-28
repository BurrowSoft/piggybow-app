#!/usr/bin/env bash
# Timeline search (#66) on the CI emulator, staging debug, zone UTC: flow 84a
# (notes, categories, a Thai note, the search key, no match, Back), then 84b
# at font scale 2.0 (the hint wrapping) for a look.
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

if mf flows/pb1/84a_timeline_search.yaml; then
  row TS-1 PASS "flow 84a: 'coffee' finds its note only; the search key keeps the results; 'transport' finds by category; a Thai note by its first word; 'zzz' says Nothing matches that; Back closes the search and stays on Timeline"
else
  row TS-1 FAIL "flow 84a"
fi

A shell settings put system font_scale 2.0; sleep 2
if mf flows/pb1/84b_search_large_text.yaml; then
  row TS-2 PASS "flow 84b: the empty field's hint at font scale 2.0 (shot 84-hint-x2)"
else
  row TS-2 FAIL "flow 84b (font scale 2.0)"
fi
A shell settings put system font_scale 1.0
