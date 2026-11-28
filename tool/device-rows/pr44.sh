#!/usr/bin/env bash
# The ears (#44) on the CI emulator, staging debug, zone UTC: shots for
# PB UX & PM's look. The rows record that each shot was taken and what the
# device said; the verdict is the look.
#   E1  the launcher icon in the app drawer, then with themed icons on
#       (Android 13+; switched through the launcher's own settings provider,
#       best effort: the row says if the switch didn't take)
#   E2  the splash at a cold start, light and dark (several quick shots, since
#       the splash shows only until the first frame)
#   E3  the reminder notification's small icon: a reminder set ~3 minutes
#       ahead through Me, then the shade opened and shot
#   E4  Home's pig after a fresh install
. "$(dirname "$0")/lib.sh"
guard_emulator

ACT="$P/com.burrowsoft.piggybow.MainActivity"
LAUNCHERS="com.google.android.apps.nexuslauncher com.android.launcher3"

themed(){ # themed true|false: the launcher's "themed icons" setting
  local v=$1 a
  for a in $LAUNCHERS; do
    A shell content update --uri "content://$a.grid_control/icon_themed" --bind boolean_value:b:"$v" >/dev/null 2>&1
  done
}

cleanup(){
  themed false
  A shell cmd uimode night no >/dev/null 2>&1
  A shell cmd statusbar collapse >/dev/null 2>&1
  echo "$(stamp) END: $PASSES pass, $FAILS fail (the shots decide)"
  rows_exit
}
trap cleanup EXIT

install_verify || exit $?
A shell svc power stayon true
A shell input keyevent KEYCODE_WAKEUP

# E4 Home's pig (also the app's first start, so the splash rows below are cold starts of a set-up app)
if mf flows/pb1/70_ears_home.yaml; then row E4 PASS "flow 70: shot 70-home-pig"; else row E4 FAIL "flow 70"; fi

# E2 The splash, light then dark: force-stop, start, quick shots
splash(){ # splash <light|dark>
  local mode=$1 i
  A shell am force-stop "$P"; sleep 2
  A shell am start -n "$ACT" >/dev/null 2>&1
  for i in 1 2 3 4; do snap "e2-splash-$mode-$i"; sleep 0.3; done
  sleep 3; A shell input keyevent KEYCODE_HOME
}
A shell cmd uimode night no; sleep 2; splash light
A shell cmd uimode night yes; sleep 3; splash dark
A shell cmd uimode night no; sleep 2
row E2 INFO "splash shots e2-splash-light-1..4 and e2-splash-dark-1..4 (LOOK: the eared pig inside the circle, not clipped)"

# E1 The launcher icon: the app drawer, plain then themed
A shell input keyevent KEYCODE_HOME; sleep 2
A shell input swipe 540 2000 540 600 300; sleep 3; snap e1-drawer-plain
A shell input keyevent KEYCODE_HOME; sleep 1
themed true; sleep 3
A shell input keyevent KEYCODE_HOME; sleep 2
A shell input swipe 540 2000 540 600 300; sleep 3; snap e1-drawer-themed
A shell input keyevent KEYCODE_HOME
themed false
row E1 INFO "launcher shots e1-drawer-plain and e1-drawer-themed (LOOK: 'Piggybow Staging', the eared pig not clipped; if the two look alike, the themed switch didn't take)"

# E3 The reminder notification's small icon
now=$(A shell date -u +%s | tr -d '\r'); at=$((now + 180))
H24=$(date -u -d "@$at" +%-H); MM=$(date -u -d "@$at" +%M)
if [ "$H24" -ge 12 ]; then AMPM=PM; else AMPM=AM; fi
H12=$(( H24 % 12 )); [ "$H12" = 0 ] && H12=12
echo "$(stamp) reminder-soon at $(date -u -d "@$at" +%H:%M) UTC ($H12:$MM $AMPM)"
if mf flows/pb1/48_reminder_soon.yaml -e HH="$H12" -e MM="$MM" -e AMPM="$AMPM"; then
  got=""
  for i in $(seq 1 60); do
    A shell dumpsys notification --noredact | tr -d '\r' > "$T/notif.txt"
    if grep -q "pkg=$P" "$T/notif.txt"; then got=1; break; fi
    sleep 5
  done
  if [ -z "$got" ]; then
    row E3 FAIL "no notification from $P within 5 minutes"
  else
    snap e3-status-bar
    A shell cmd statusbar expand-notifications; sleep 2; snap e3-shade
    A shell cmd statusbar collapse
    row E3 PASS "posted; shots e3-status-bar and e3-shade (LOOK: the small icon is the eared silhouette)"
  fi
else
  row E3 FAIL "flow 48 (setting the reminder a few minutes ahead) did not finish"
fi
