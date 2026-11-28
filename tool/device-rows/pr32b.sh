#!/usr/bin/env bash
# PR 5a, the two rows to repeat after pr32.sh's first run (staging debug, UTC):
#   R2  flow 41: Don't allow -> "Notifications are off" + Open settings, then
#       back to the app by the system's Back (fixed: a relaunch showed the
#       settings page again, since it opens in the app's own task)
#   RS  (optional) a reminder a few minutes from now through Me's time picker:
#       posted, a shade shot, and a tap opens the Add sheet (flow 48's launch
#       now clears as its own step, with a retry)
. "$(dirname "$0")/lib.sh"
guard_emulator

cleanup(){
  A shell cmd statusbar collapse >/dev/null 2>&1
  echo "$(stamp) END: $PASSES pass, $FAILS fail (the log and the screenshots decide)"
}
trap cleanup EXIT

install_verify || exit $?
echo "$(stamp) device time: $(A shell date -u '+%Y-%m-%d %H:%M:%S UTC' | tr -d '\r'), zone $(A shell getprop persist.sys.timezone | tr -d '\r')"

if mf flows/pb1/41_reminder_offer_deny.yaml; then row R2 PASS "flow 41"; else row R2 FAIL "flow 41"; fi

# RS (optional): a reminder ~3 minutes from now, posted, shot, tapped
now=$(A shell date -u +%s | tr -d '\r'); at=$((now + 180))
H24=$(date -u -d "@$at" +%-H); MM=$(date -u -d "@$at" +%M)
if [ "$H24" -ge 12 ]; then AMPM=PM; else AMPM=AM; fi
H12=$(( H24 % 12 )); [ "$H12" = 0 ] && H12=12
echo "$(stamp) reminder-soon at $(date -u -d "@$at" +%H:%M) UTC ($H12:$MM $AMPM)"
if mf flows/pb1/48_reminder_soon.yaml -e HH="$H12" -e MM="$MM" -e AMPM="$AMPM"; then
  got=""
  for i in $(seq 1 60); do   # up to 5 minutes (an inexact alarm may run a little late)
    A shell dumpsys notification --noredact | tr -d '\r' > "$T/notif.txt"
    if grep -q "pkg=$P" "$T/notif.txt"; then got=1; break; fi
    sleep 5
  done
  if [ -z "$got" ]; then
    row RS FAIL "no notification from $P within 5 minutes of $(date -u -d "@$at" +%H:%M) UTC"
  else
    title=$(grep -A60 "pkg=$P" "$T/notif.txt" | grep -m1 -oE 'android\.title=String \(.*\)' | sed -E 's/.*\((.*)\)/\1/')
    text=$(grep -A60 "pkg=$P" "$T/notif.txt" | grep -m1 -oE 'android\.text=String \(.*\)' | sed -E 's/.*\((.*)\)/\1/')
    row RS PASS "posted at $(A shell date -u +%H:%M:%S | tr -d '\r') UTC: title '$title', body '$text'"
    A shell cmd statusbar expand-notifications; sleep 2; snap rs-shade
    if mf flows/pb1/49_reminder_tap_opens_add.yaml; then row RS-tap PASS "flow 49: the tap opened the Add sheet"; else row RS-tap FAIL "flow 49"; fi
    A shell cmd statusbar collapse >/dev/null 2>&1
  fi
else
  row RS INFO "flow 48 (setting the time through the picker) did not finish: no shade shot this run"
fi
