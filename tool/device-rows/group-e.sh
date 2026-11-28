#!/usr/bin/env bash
# Group E (repeating entries: #70, #73, #77), retroactively on master
# (decision 86), staging debug, zone UTC, the real clock moved by root (a
# frozen FAKE_NOW clock would never reach the next repeat):
#   RE-1 flow 88a: a $12 Food spend with Repeat every week; Me lists it
#   RE-2 the app stopped, the clock 8 days ahead; flow 88b: a cold start adds
#        the week's spend, Home says so until OK, Timeline marks it
#   RE-3 flow 88c: the amount changed (from the next one), then stopped; the
#        list is empty and the added entries stay
# The repeat's own rules (catch-up counts, month ends, the pig and the
# reminder ignoring added entries) are the unit tests' and the contract's.
. "$(dirname "$0")/lib.sh"
guard_emulator

setclock(){ # setclock <YYYY-MM-DD> <HH:MM:SS>, UTC (the zone is UTC)
  local d=$1 t=$2
  A shell date "${d:5:2}${d:8:2}${t:0:2}${t:3:2}${d:0:4}.${t:6:2}" >/dev/null
  echo "$(stamp) device clock: $(A shell date -u | tr -d '\r')"
}

cleanup(){
  A shell settings put global auto_time 1 >/dev/null 2>&1
  echo "$(stamp) END: $PASSES pass, $FAILS fail"
  rows_exit
}
trap cleanup EXIT

# Root, to move the device clock (google_apis images allow it)
A root >/dev/null 2>&1; sleep 3; A wait-for-device
if [ "$(A shell id -u | tr -d '\r')" != 0 ]; then
  row RE-0 FAIL "no root on this image: the device clock can't be moved"; exit 1
fi
A shell settings put global auto_time 0
install_verify || exit $?

# Start at noon today (UTC), so +8 days stays clear of midnight.
D0=$(date -u +%Y-%m-%d)
setclock "$D0" 12:00:00

if mf flows/pb1/88a_repeat_add.yaml; then
  row RE-1 PASS "flow 88a: \$12 Food with Repeat every week; Me → Repeating entries lists it"
else
  row RE-1 FAIL "flow 88a"; exit 1
fi

A shell am force-stop "$APP_ID"
D8=$(date -u -d "$D0 + 8 days" +%Y-%m-%d)
setclock "$D8" 12:00:00
if mf flows/pb1/88b_repeat_catch_up.yaml; then
  row RE-2 PASS "flow 88b: 8 days later a cold start adds the week's \$12 spend; 'Added from your repeats' until OK; Timeline: 'Added by your repeat'"
else
  row RE-2 FAIL "flow 88b"
fi

if mf flows/pb1/88c_repeat_change_stop.yaml; then
  row RE-3 PASS "flow 88c: \$15 from the next one; stopped; 'None yet'; the added entries stay"
else
  row RE-3 FAIL "flow 88c"
fi
