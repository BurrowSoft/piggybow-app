#!/usr/bin/env bash
# One staging debug run on master for four scripts, each unchanged, as a child:
#   group-e.sh     group E's repeats (RE-1..3)
#   group-risk.sh  the captain's riskiest checks (RK-1, RK-2, RK-3, RK-5)
#   pr57.sh        quick amounts (QA-1, QA-2): C+F's QA-1 re-run
#   group-f.sh     money in another currency (CU-1): C+F's CU-1 re-run
# group-e and group-risk move the device clock by root themselves and put
# auto_time back; pr57 and group-f run at 12:00 UTC today, as group-cf.sh
# sets them (root: zone UTC, the clock, the app stopped).
. "$(dirname "$0")/lib.sh"
guard_emulator
[ "$KIND" = debug ] || { echo "$(stamp) STOP: dispatch with kind=debug (kind is $KIND)"; exit 7; }
RESULTS=()
child(){ # child <script>: one script's rows, its exit kept
  local s=$1 rc=0
  echo "$(stamp) ===== $s ====="
  bash "$HERE/$s.sh" || rc=$?
  RESULTS+=("$s=$rc")
  echo "$(stamp) ===== $s: exit $rc ====="
}
noon(){ # the device at 12:00 UTC today, zone UTC, the app stopped (group-cf.sh's set)
  local d
  A root >/dev/null 2>&1 || { sleep 3; A wait-for-device; A root >/dev/null 2>&1; }
  sleep 3; A wait-for-device
  A shell settings put global auto_time 0
  A shell settings put global auto_time_zone 0
  A shell setprop persist.sys.timezone UTC
  d=$(date -u +%Y-%m-%d)
  A shell date -u "${d:5:2}${d:8:2}1200${d:0:4}.00" >/dev/null
  echo "$(stamp) device clock: $(A shell date -u | tr -d '\r') | zone $(A shell getprop persist.sys.timezone | tr -d '\r')"
  A shell am force-stop "$APP_ID"
}
finish(){
  A shell settings put global auto_time 1 >/dev/null 2>&1
  A shell settings put global auto_time_zone 1 >/dev/null 2>&1
  echo "$(stamp) E + RISK + QA-1 + CU-1: ${RESULTS[*]}"
  for r in "${RESULTS[@]}"; do [ "${r#*=}" = 0 ] || exit 1; done
}
trap finish EXIT
child group-e
child group-risk
noon
child pr57
noon
child group-f
