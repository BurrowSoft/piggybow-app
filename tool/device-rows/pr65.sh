#!/usr/bin/env bash
# The lock screen's status bar (#65) on the CI emulator, staging debug, zone
# UTC, in light then night mode:
#   LB1 a cold start with the lock on: quick shots from the start (the splash),
#       the lock as it appears (flow 80b), and 3 s later
#   LB2 unlock, background, come back: the cover or lock as it shows, and 3 s
#       later (flow 80c)
# Each time the window's status-bar appearance is logged from dumpsys. The
# verdict is the look: light, all four status icons dark; night, all white.
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

for mode in light dark; do
  if [ "$mode" = dark ]; then A shell cmd uimode night yes; else A shell cmd uimode night no; fi
  sleep 3
  echo "$(stamp) uimode: $(A shell cmd uimode night | tr -d '\r')"
  if ! MF_NAME="80a-$mode" mf flows/pb1/80a_lock_on.yaml; then
    row "LB1-$mode" FAIL "flow 80a (the lock turned on) did not finish"
    continue
  fi
  # LB1: a cold start, quick shots from the first frames
  A shell am force-stop "$P"; sleep 2
  A shell am start -n "$ACT" >/dev/null 2>&1
  for i in 1 2 3; do snap "65-$mode-start-$i"; sleep 0.3; done
  if MF_NAME="80b-$mode" mf flows/pb1/80b_lock_after_cold_start.yaml -e MODE="$mode"; then
    appearance "lock (cold, $mode)"
    sleep 3; snap "65-$mode-lock-cold-3s"
    appearance "lock (cold +3 s, $mode)"
    row "LB1-$mode" INFO "shots 65-$mode-start-1..3, 80-lock-cold-$mode, 65-$mode-lock-cold-3s (LOOK: $mode: all four status icons $( [ "$mode" = light ] && echo dark || echo white ))"
  else
    row "LB1-$mode" FAIL "flow 80b: no lock screen after the cold start"
    continue
  fi
  # LB2: unlock, background, come back
  if MF_NAME="80c-$mode" mf flows/pb1/80c_lock_after_resume.yaml -e MODE="$mode"; then
    appearance "lock (resume, $mode)"
    sleep 3; snap "65-$mode-lock-resume-3s"
    row "LB2-$mode" INFO "shots 80-lock-resume-$mode, 65-$mode-lock-resume-3s (LOOK: as LB1)"
  else
    row "LB2-$mode" FAIL "flow 80c: no lock or cover after the resume"
  fi
done
