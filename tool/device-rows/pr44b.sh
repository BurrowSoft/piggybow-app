#!/usr/bin/env bash
# The ears (#44), second pass on the CI emulator: the two rows the first pass
# left open. The splash (E2) and Home's pig (E4) were shot there.
#   E1t the launcher icon with themed icons on. The shell can't flip the
#       launcher's setting (its provider is guarded), so flow 71 turns it on in
#       Wallpaper and style. The drawer is shot before and after; the provider's
#       answer is logged, not hidden.
#   E3  the reminder notification's small icon. Flow 48 now selects each time
#       field before typing, and checks the Time row it set.
. "$(dirname "$0")/lib.sh"
guard_emulator

LAUNCHERS="com.google.android.apps.nexuslauncher com.android.launcher3"

cleanup(){
  A shell cmd statusbar collapse >/dev/null 2>&1
  echo "$(stamp) END: $PASSES pass, $FAILS fail (the shots decide)"
  rows_exit
}
trap cleanup EXIT

install_verify || exit $?
A shell svc power stayon true
A shell input keyevent KEYCODE_WAKEUP

drawer(){ # drawer <shot>: the app drawer from the home screen
  A shell input keyevent KEYCODE_HOME; sleep 2
  A shell input swipe 540 2000 540 600 300; sleep 3; snap "$1"
  A shell input keyevent KEYCODE_HOME; sleep 1
}

# E1t The launcher icon, themed
echo "$(stamp) home activity: $(A shell cmd package resolve-activity --brief -a android.intent.action.MAIN -c android.intent.category.HOME 2>&1 | tr -d '\r' | tail -1)"
for a in $LAUNCHERS; do
  echo "$(stamp) $a icon_themed query: $(A shell content query --uri "content://$a.grid_control/icon_themed" 2>&1 | tr -d '\r' | head -2 | tr '\n' ' ')"
done
drawer e1-drawer-plain
if mf flows/pb1/71_themed_icons_on.yaml; then
  sleep 3
  for a in $LAUNCHERS; do
    echo "$(stamp) $a icon_themed after flow 71: $(A shell content query --uri "content://$a.grid_control/icon_themed" 2>&1 | tr -d '\r' | head -2 | tr '\n' ' ')"
  done
  drawer e1-drawer-themed
  row E1t INFO "themed icons switched on in Wallpaper and style (shot 71-themed-icons-on); drawer shots e1-drawer-plain and e1-drawer-themed (LOOK: the eared silhouette, not clipped; if the two look alike, the switch didn't take)"
else
  row E1t INFO "flow 71 could not switch themed icons on (see its screenshot); no themed shot"
fi

# E3 The reminder notification's small icon: about 4 minutes ahead (flow 48
# takes about a minute), then up to 6 minutes for the notification
now=$(A shell date -u +%s | tr -d '\r'); at=$((now + 240))
H24=$(date -u -d "@$at" +%-H); MM=$(date -u -d "@$at" +%M)
if [ "$H24" -ge 12 ]; then AMPM=PM; else AMPM=AM; fi
H12=$(( H24 % 12 )); [ "$H12" = 0 ] && H12=12
echo "$(stamp) reminder-soon at $(date -u -d "@$at" +%H:%M) UTC ($H12:$MM $AMPM)"
if mf flows/pb1/48_reminder_soon.yaml -e HH="$H12" -e MM="$MM" -e AMPM="$AMPM"; then
  echo "$(stamp) alarms for $P: $(A shell dumpsys alarm 2>/dev/null | tr -d '\r' | grep -c "$P") lines"
  got=""
  for i in $(seq 1 72); do
    A shell dumpsys notification --noredact | tr -d '\r' > "$T/notif.txt"
    if grep -q "pkg=$P" "$T/notif.txt"; then got=1; break; fi
    sleep 5
  done
  if [ -z "$got" ]; then
    row E3 FAIL "no notification from $P within 6 minutes of a reminder set for $H12:$MM $AMPM"
  else
    echo "$(stamp) notification seen"
    snap e3-status-bar
    A shell cmd statusbar expand-notifications; sleep 2; snap e3-shade
    A shell cmd statusbar collapse
    row E3 PASS "posted; shots e3-status-bar and e3-shade (LOOK: the small icon is the eared silhouette)"
  fi
else
  row E3 FAIL "flow 48 (the reminder set and its Time row checked) did not finish"
fi
