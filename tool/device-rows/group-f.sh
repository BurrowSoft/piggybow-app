#!/usr/bin/env bash
# Group F (money in another currency: #74, #76), retroactively on master
# (decision 86), staging debug, zone UTC, the real clock, home currency USD
# (the emulator's en-US):
#   CU-1 flow 89a: a ฿300 spend at 1 THB = 0.028 → "That's $8.40 at this
#        rate."; flipped (1 USD = 35.71) the same; Summary counts $8.40;
#        Timeline shows ฿300; the next THB spend starts from 0.028
# The money maths (rounding, every total at home, the CSV's columns) are the
# unit tests' and the contract's.
. "$(dirname "$0")/lib.sh"
guard_emulator

cleanup(){
  echo "$(stamp) END: $PASSES pass, $FAILS fail"
  rows_exit
}
trap cleanup EXIT

install_verify || exit $?

if mf flows/pb1/89a_trip.yaml; then
  row CU-1 PASS "flow 89a: ฿300 at 1 THB = 0.028 → \$8.40; flipped 1 USD = 35.71 → \$8.40; Summary \$8.40; Timeline ฿300; the last rate comes back"
else
  row CU-1 FAIL "flow 89a"
fi
