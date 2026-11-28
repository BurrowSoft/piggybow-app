#!/usr/bin/env bash
# F-B1's fix (#96): night is 22:00 to 03:59 on the phone's clock, and Home
# turns at 04:00 while it's open. Staging debug, no fake_now, zone UTC; the
# device clock set by root (the group-b.sh method).
#   NB-1 flow 96a: Home open from 03:56: the sleepy pig's night line before
#        04:00, then the day's pig at 04:00 with no tap
#   NB-2 flow 96b: a cold start at 05:00: the day's pig (F-B1 saw the night
#        line there); the Add sheet in euros has no "= €12.34" echo
#   NB-3 flow 96c, Plus kinds only (plus-owned, plus-rows): "+ New goal" under the goal
#        card (looked at in the shot); builds without Plus have no such button
# Dispatch with a Plus kind (fb1-pa3.sh uses plus-rows) so NB-3 runs; on
# debug it's an INFO row.
. "$(dirname "$0")/lib.sh"
guard_emulator

A root >/dev/null 2>&1 || { sleep 3; A wait-for-device; A root >/dev/null 2>&1; }
sleep 3; A wait-for-device
if [ "$(A shell id -u | tr -d '\r')" != 0 ]; then
  echo "$(stamp) STOP: no root on this image: the device clock can't be moved"; exit 1
fi
A shell settings put global auto_time 0
A shell settings put global auto_time_zone 0
A shell setprop persist.sys.timezone UTC
[ "$(A shell getprop persist.sys.timezone | tr -d '\r')" = UTC ] || { echo "$(stamp) STOP: the zone isn't UTC"; exit 7; }

setclock(){ # setclock <YYYY-MM-DD> <HH:MM:SS>, in UTC
  local d=$1 t=$2
  A shell date -u "${d:5:2}${d:8:2}${t:0:2}${t:3:2}${d:0:4}.${t:6:2}" >/dev/null
  echo "$(stamp) device clock: $(A shell date -u | tr -d '\r')"
}
cleanup(){
  A shell settings put global auto_time 1 >/dev/null 2>&1
  A shell settings put global auto_time_zone 1 >/dev/null 2>&1
  echo "$(stamp) END: $PASSES pass, $FAILS fail"
  rows_exit
}
trap cleanup EXIT

install_verify || exit $?
D=2026-11-28
setclock "$D" 03:56:00
A shell am force-stop "$APP_ID"
if mf flows/pb1/96a_night_turn.yaml; then
  row NB-1 PASS "flow 96a: Home open from 03:56: the night line before 04:00, the day's pig at 04:00 with no tap (turn seen by $(A shell date -u +%H:%M:%S | tr -d '\r') UTC)"
else
  row NB-1 FAIL "flow 96a (device clock now $(A shell date -u +%H:%M:%S | tr -d '\r') UTC)"
fi

setclock "$D" 05:00:00
A shell am force-stop "$APP_ID"
if mf flows/pb1/96b_morning_cold.yaml; then
  row NB-2 PASS "flow 96b: a cold start at 05:00 shows the day's pig; the Add sheet in euros has no '= €12.34' echo"
else
  row NB-2 FAIL "flow 96b"
fi

# "+ New goal" exists only in builds with Plus (a second goal is Plus's)
case "$KIND" in
  plus-owned|plus-rows)
    if mf flows/pb1/96c_new_goal_button.yaml; then
      row NB-3 PASS "flow 96c ($KIND): '+ New goal' shows under the goal card (the shot looked at for its place)"
    else
      row NB-3 FAIL "flow 96c ($KIND)"
    fi ;;
  *) row NB-3 INFO "flow 96c not run: kind $KIND has no Plus, so no '+ New goal' (dispatch with plus-owned)" ;;
esac
