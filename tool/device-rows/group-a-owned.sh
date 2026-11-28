#!/usr/bin/env bash
# Group A with Plus on (decision 86, retroactively on master), kind=plus-owned
# (PLUS_ROWS_OWNED: the rows' store reports one active yearly purchase, with
# nothing bought), zone UTC, the real clock:
#   PO-1 flow 90a: Me says Plus is on; the paywall thanks you with Manage
#        subscription; a second goal needs no paywall; your own category in
#        Me and in Add; Delete everything says Plus keeps running
. "$(dirname "$0")/lib.sh"
guard_emulator

cleanup(){
  echo "$(stamp) END: $PASSES pass, $FAILS fail"
  rows_exit
}
trap cleanup EXIT

install_verify || exit $?

if mf flows/pb1/90a_plus_on.yaml; then
  row PO-1 PASS "flow 90a: Me 'On. Thanks for your support!' + Manage subscription; the paywall 'You have Piggybow Plus', no plans; a second goal opens the goal form; 'Coffee runs' in Categories and in Add; Delete everything: Plus keeps running (cancelled)"
else
  row PO-1 FAIL "flow 90a"
fi
