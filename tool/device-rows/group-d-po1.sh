#!/usr/bin/env bash
# One plus-owned run on master for three scripts, each unchanged, as a child:
#   group-d.sh       the home-screen widget (WD-1; WD-2 with the lock on)
#   group-a-owned.sh PO-1's re-run with the fixed flow 90a
#   fb1-night.sh     NB-1's re-run (96a hides and reopens after the spend:
#                    the reaction line had hidden the night one); last, as it
#                    moves the clock by root and puts it back
. "$(dirname "$0")/lib.sh"
guard_emulator
[ "$KIND" = plus-owned ] || { echo "$(stamp) STOP: dispatch with kind=plus-owned (kind is $KIND)"; exit 7; }
RESULTS=()
child(){ # child <script>: one script's rows, its exit kept
  local s=$1 rc=0
  echo "$(stamp) ===== $s ====="
  bash "$HERE/$s.sh" || rc=$?
  RESULTS+=("$s=$rc")
  echo "$(stamp) ===== $s: exit $rc ====="
}
finish(){
  echo "$(stamp) GROUP D + PO-1 + F-B1: ${RESULTS[*]}"
  for r in "${RESULTS[@]}"; do [ "${r#*=}" = 0 ] || exit 1; done
}
trap finish EXIT
child group-d
child group-a-owned
child fb1-night
