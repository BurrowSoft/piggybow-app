#!/usr/bin/env bash
# The 6c prod-release smoke (decision 64) on Sunday's candidate: the store's
# flavour in release mode with R8 and a throwaway signing key
# (kind=prod-release), the real clock, zone UTC. A row per check and per flow;
# the screenshots (onboarding, Home, the lock, the reminder, the celebration)
# are for PB UX & PM's look.
. "$(dirname "$0")/lib.sh"
guard_emulator

COLOUR=0xffa8456a   # never WANT: lib.sh reads WANT as the APK sha256

cleanup(){
  A shell cmd statusbar collapse >/dev/null 2>&1
  echo "$(stamp) END: $PASSES pass, $FAILS fail"
  rows_exit
}
trap cleanup EXIT

install_verify || exit $?
A shell svc power stayon true
A shell input keyevent KEYCODE_WAKEUP

# The installed package: the store's id, not debuggable, no network permission
A shell dumpsys package "$P" | tr -d '\r' > "$T/pkg.txt"
if [ "$P" = com.burrowsoft.piggybow ]; then row 6C-pkg PASS "package $P, $(grep -m1 -oE 'versionName=[^ ]+' "$T/pkg.txt")"; else row 6C-pkg FAIL "package $P, not com.burrowsoft.piggybow"; fi
if grep -q DEBUGGABLE "$T/pkg.txt"; then row 6C-debug FAIL "the package is DEBUGGABLE"; else row 6C-debug PASS "not debuggable"; fi
net=$(grep -A60 "requested permissions" "$T/pkg.txt" | grep -cE "android\.permission\.(INTERNET|ACCESS_NETWORK_STATE)")
if [ "$net" = 0 ]; then row 6C-net PASS "no INTERNET, no ACCESS_NETWORK_STATE requested"; else row 6C-net FAIL "$net network permission(s) requested"; fi

for f in 00_smoke_launch 10_journal_loop 11_add_save_no_goal 13_double_tap_add 14_timeline_filters 30_onboarding_paths 21_goal_reached_once 42_lock_pin; do
  if mf "flows/pb1/$f.yaml"; then row "6C-${f%%_*}" PASS "flow $f"; else row "6C-${f%%_*}" FAIL "flow $f"; fi
done

# The reminder: set ~4 minutes ahead through Me (flow 48), then the shade
now=$(A shell date -u +%s | tr -d '\r'); at=$((now + 240))
H24=$(date -u -d "@$at" +%-H); MM=$(date -u -d "@$at" +%M)
if [ "$H24" -ge 12 ]; then AMPM=PM; else AMPM=AM; fi
H12=$(( H24 % 12 )); [ "$H12" = 0 ] && H12=12
echo "$(stamp) reminder-soon at $(date -u -d "@$at" +%H:%M) UTC ($H12:$MM $AMPM)"
if mf flows/pb1/48_reminder_soon.yaml -e HH="$H12" -e MM="$MM" -e AMPM="$AMPM"; then
  got=""
  for i in $(seq 1 72); do
    A shell dumpsys notification --noredact | tr -d '\r' > "$T/notif.txt"
    if grep -q "pkg=$P" "$T/notif.txt"; then got=1; break; fi
    sleep 5
  done
  if [ -z "$got" ]; then
    row 6C-48 FAIL "no notification from $P within 6 minutes of a reminder set for $H12:$MM $AMPM"
  else
    colours=$(awk -v p="pkg=$P" 'index($0,p){on=1;n=0} on{n++; if ($0 ~ /color=/) print; if (n>60) on=0}' "$T/notif.txt" | grep -oE 'color=0x[0-9a-fA-F]+' | sort -u | tr '\n' ' ')
    snap 6c-status-bar
    A shell cmd statusbar expand-notifications; sleep 2; snap 6c-shade
    A shell cmd statusbar collapse
    if echo "$colours" | grep -qi "color=$COLOUR"; then
      row 6C-48 PASS "the reminder posted by $(date -u +%H:%M:%S) UTC, colour $COLOUR; shots 6c-status-bar, 6c-shade"
    else
      row 6C-48 FAIL "the reminder posted, but its colour is '${colours:-none}', not $COLOUR"
    fi
  fi
else
  row 6C-48 FAIL "flow 48 (the reminder set and its Time row checked) did not finish"
fi
