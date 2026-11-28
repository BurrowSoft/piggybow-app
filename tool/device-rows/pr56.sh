#!/usr/bin/env bash
# Add an entry again today (#56) on the CI emulator, staging debug, zone UTC:
# flow 76 (a long-press and the edit sheet's menu offer it; the copy is
# today's with no feeling; Undo removes only the copy; a no-goal save stays
# no-goal; a reached goal's save isn't offered).
. "$(dirname "$0")/lib.sh"
guard_emulator

cleanup(){
  echo "$(stamp) END: $PASSES pass, $FAILS fail"
  rows_exit
}
trap cleanup EXIT

install_verify || exit $?

if mf flows/pb1/76_add_again.yaml; then
  row AA-1 PASS "flow 76: long-press and the edit menu offer it; the copy today, no feeling; Undo removes only it; no-goal save stays no-goal; a reached goal's save not offered"
else
  row AA-1 FAIL "flow 76"
fi
