#!/usr/bin/env bash
# The reminder's notification with the app's berry accent (#48) on the CI
# emulator, staging debug, zone UTC: a reminder set ~4 minutes ahead through
# Me (flow 48), then the status bar and the shade shot in light mode, then the
# same notification's shade in night mode. The row checks the colour the
# notification carries (dumpsys); the shots are for the look (the header's
# circle and app name in berry, not the system's teal).
#   N1  the reminder posted
#   N2  its colour is the berry, #A8456A
. "$(dirname "$0")/lib.sh"
guard_emulator

COLOUR=0xffa8456a   # never WANT: lib.sh reads WANT as the APK sha256

cleanup(){
  A shell cmd uimode night no >/dev/null 2>&1
  A shell cmd statusbar collapse >/dev/null 2>&1
  echo "$(stamp) END: $PASSES pass, $FAILS fail (the shots decide the look)"
  rows_exit
}
trap cleanup EXIT

install_verify || exit $?
A shell svc power stayon true
A shell input keyevent KEYCODE_WAKEUP
A shell cmd uimode night no; sleep 2

now=$(A shell date -u +%s | tr -d '\r'); at=$((now + 240))
H24=$(date -u -d "@$at" +%-H); MM=$(date -u -d "@$at" +%M)
if [ "$H24" -ge 12 ]; then AMPM=PM; else AMPM=AM; fi
H12=$(( H24 % 12 )); [ "$H12" = 0 ] && H12=12
echo "$(stamp) reminder-soon at $(date -u -d "@$at" +%H:%M) UTC ($H12:$MM $AMPM)"
if ! mf flows/pb1/48_reminder_soon.yaml -e HH="$H12" -e MM="$MM" -e AMPM="$AMPM"; then
  row N1 FAIL "flow 48 (the reminder set and its Time row checked) did not finish"
  exit 1
fi

got=""
for i in $(seq 1 72); do
  A shell dumpsys notification --noredact | tr -d '\r' > "$T/notif.txt"
  if grep -q "pkg=$P" "$T/notif.txt"; then got=1; break; fi
  sleep 5
done
if [ -z "$got" ]; then
  row N1 FAIL "no notification from $P within 6 minutes of a reminder set for $H12:$MM $AMPM"
  exit 1
fi
row N1 PASS "posted by $(date -u +%H:%M:%S) UTC"

# The colour the notification carries: the lines of its record after pkg=
colours=$(awk -v p="pkg=$P" 'index($0,p){on=1;n=0} on{n++; if ($0 ~ /color=/) print; if (n>60) on=0}' "$T/notif.txt" | grep -oE 'color=0x[0-9a-fA-F]+' | sort -u | tr '\n' ' ')
echo "$(stamp) notification colour(s): ${colours:-none found}"
if echo "$colours" | grep -qi "color=$COLOUR"; then
  row N2 PASS "the notification's colour is $COLOUR (berry #A8456A)"
else
  row N2 FAIL "the notification's colour is '${colours:-none}', not $COLOUR"
fi

snap n-status-bar-light
A shell cmd statusbar expand-notifications; sleep 2; snap n-shade-light
A shell cmd statusbar collapse; sleep 1
A shell cmd uimode night yes; sleep 4
A shell cmd statusbar expand-notifications; sleep 2; snap n-shade-dark
A shell cmd statusbar collapse
row N3 INFO "shots n-status-bar-light, n-shade-light, n-shade-dark (LOOK: the small icon's circle and the app name in berry, the eared silhouette)"
