#!/usr/bin/env bash
# The lock screen's status bar (#65), the Reviewer's two extra rows: the phone
# in one mode and Piggybow's own theme in the other (Me -> theme), cold start
# with the lock on, then a resume, as in pr65.sh. Evidence for a follow-up:
# the native window follows the phone, the app its own theme.
#   LB3 phone dark,  Piggybow Light
#   LB4 phone light, Piggybow Dark
. "$(dirname "$0")/lib.sh"
guard_emulator

ACT="$P/com.burrowsoft.piggybow.MainActivity"

cleanup(){
  A shell cmd uimode night no >/dev/null 2>&1
  echo "$(stamp) END: $PASSES pass, $FAILS fail (the shots decide)"
  rows_exit
}
trap cleanup EXIT

appearance(){ # appearance <label>
  echo "$(stamp) $1 appearance: $(A shell dumpsys window | tr -d '\r' | grep -m4 -iE 'appearance|LIGHT_STATUS' | tr -s ' ' | tr '\n' ' ')"
}

install_verify || exit $?
A shell svc power stayon true
A shell input keyevent KEYCODE_WAKEUP

for combo in "LB3 dark light" "LB4 light dark"; do
  set -- $combo; id=$1; phone=$2; theme=$3; tag="phone-$phone-app-$theme"
  if [ "$phone" = dark ]; then A shell cmd uimode night yes; else A shell cmd uimode night no; fi
  sleep 3
  echo "$(stamp) $id: uimode $(A shell cmd uimode night | tr -d '\r'), Piggybow theme $theme"
  if ! MF_NAME="80d-$tag" mf flows/pb1/80d_lock_on_theme.yaml -e THEME="$theme"; then
    row "$id" FAIL "flow 80d (theme $theme + the lock) did not finish"
    continue
  fi
  A shell am force-stop "$P"; sleep 2
  A shell am start -n "$ACT" >/dev/null 2>&1
  for i in 1 2 3; do snap "65b-$tag-start-$i"; sleep 0.3; done
  if MF_NAME="80b-$tag" mf flows/pb1/80b_lock_after_cold_start.yaml -e MODE="$tag"; then
    appearance "lock (cold, $tag)"
    sleep 3; snap "65b-$tag-lock-cold-3s"
  else
    row "$id" FAIL "flow 80b: no lock screen after the cold start ($tag)"
    continue
  fi
  if MF_NAME="80c-$tag" mf flows/pb1/80c_lock_after_resume.yaml -e MODE="$tag"; then
    appearance "lock (resume, $tag)"
    sleep 3; snap "65b-$tag-lock-resume-3s"
    row "$id" INFO "phone $phone, Piggybow $theme: shots 65b-$tag-start-1..3, 80-lock-cold-$tag, 65b-$tag-lock-cold-3s, 80-lock-resume-$tag, 65b-$tag-lock-resume-3s (LOOK: icons readable on the page's own colour)"
  else
    row "$id" FAIL "flow 80c: no lock or cover after the resume ($tag)"
  fi
done
