#!/usr/bin/env bash
# Home's turns (#62) on the CI emulator, staging debug, zone UTC, the real
# clock moved by root (the app's FAKE_NOW clock is frozen and never turns):
#   TU-1 Home left open across midnight: Today's idea moves to the new day's
#        on the timer alone (no launch, no tap)
#   TU-2 in the background while the clock jumps days ahead, then brought back
#        without a restart (same process): the new day's idea (onResume)
#   TU-3 06:00 and 22:00: nothing on Home changes with the hour on this head
#        (the night pig is #53's), so they are left to the unit tests
# Today's idea is tip[(dayOfYear - 1) mod 20]; the script computes the expected
# one for each date and the flows assert it.
. "$(dirname "$0")/lib.sh"
guard_emulator

TIPS=(
  "Before a non-essential buy, wait a day."
  "Pick one subscription to check this week."
  "Pay yourself first: put a little aside"
  "Round up your spends and save the difference."
  "Bring a snack from home once this week."
  "Make a list before you shop, and stick to it."
  "Try a no-spend day."
  "Cook one more meal at home this week"
  "Unsubscribe from one shop's emails."
  "Before you buy, ask: will I use this"
  "Compare the price per unit, not per pack."
  "Borrow before you buy: books, tools, a tent."
  "Sell or give away one thing you no longer use."
  "Treats are good! Plan them, then enjoy them fully."
  "Look back at your week on Sunday."
  "Keep your coins in a jar."
  "Walk or cycle one short trip this week"
  "Look for something free to do this weekend."
  "Write down why you're saving."
  "Give your savings goal a name you love."
)
tip_re(){ # tip_re <YYYY-MM-DD>: the day's tip (its start), as a regex
  local doy; doy=$(date -u -d "$1" +%-j)
  printf '%s' "${TIPS[$(( (doy - 1) % 20 ))]}" | sed 's/[.?()!*+^$|]/\\&/g'   # the tips use no other regex characters
}
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
  row TU-0 FAIL "no root on this image: the device clock can't be moved"; exit 1
fi
A shell settings put global auto_time 0
install_verify || exit $?

D=$(A shell date -u +%Y-%m-%d | tr -d '\r')
D1=$(date -u -d "$D + 1 day" +%Y-%m-%d)
D4=$(date -u -d "$D + 4 days" +%Y-%m-%d)

# TU-1: open Home at about 23:57, then leave it across midnight
setclock "$D" 23:56:30
if MF_NAME=83a mf flows/pb1/83a_turn_open_home.yaml -e TIP="$(tip_re "$D")" \
   && MF_NAME=83b mf flows/pb1/83b_turn_wait_midnight.yaml -e TIP="$(tip_re "$D1")"; then
  row TU-1 PASS "Home open from before midnight ($D, '$(tip_re "$D" | tr -d '\\')') to after it ($D1, '$(tip_re "$D1" | tr -d '\\')'), with no launch or tap: the timer read it again"
else
  row TU-1 FAIL "Today's idea didn't move to $D1's across midnight (shots 83-before-midnight / the flow's own)"
fi

# TU-2: background, the clock three days on, back without a restart
pid1=$(A shell pidof "$P" | tr -d '\r')
A shell input keyevent KEYCODE_HOME; sleep 2
setclock "$D4" 12:00:00
if MF_NAME=83c mf flows/pb1/83c_turn_resume.yaml -e TIP="$(tip_re "$D4")"; then
  pid2=$(A shell pidof "$P" | tr -d '\r')
  if [ -n "$pid1" ] && [ "$pid1" = "$pid2" ]; then
    row TU-2 PASS "back from the background on $D4 (same process $pid1): '$(tip_re "$D4" | tr -d '\\')'"
  else
    row TU-2 FAIL "the idea was $D4's, but the process changed ($pid1 -> $pid2): a restart, not a resume"
  fi
else
  row TU-2 FAIL "Today's idea wasn't $D4's after coming back"
fi

row TU-3 INFO "06:00 and 22:00: no Home content changes with the hour on this head (the night pig is #53's); the turn times are in test/home_turns_test.dart"
