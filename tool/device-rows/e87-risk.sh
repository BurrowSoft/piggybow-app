#!/usr/bin/env bash
# One staging debug run on master for two scripts, each unchanged, as a child:
#   group-e87.sh   group E's repeats (RE-1..3) and #87's backup rows (BK-1..7)
#   group-risk.sh  the captain's riskiest checks (RK-1, RK-2, RK-3, RK-5)
# Each moves the device clock by root itself and puts auto_time back.
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
finish(){
  echo "$(stamp) E87 + RISK: ${RESULTS[*]}"
  for r in "${RESULTS[@]}"; do [ "${r#*=}" = 0 ] || exit 1; done
}
trap finish EXIT
child group-e87
child group-risk
