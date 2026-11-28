#!/usr/bin/env bash
# One plus-rows run on master (Plus built in, off) for two scripts, each
# unchanged, as a child:
#   fb1-night.sh   F-B1's fix (#96): NB-1 Home turns at 04:00, NB-2 a cold
#                  start at 05:00 and the euro sheet, NB-3 "+ New goal"
#   group-a-x2.sh  PA-3, the paywall at font scale 2.0 (last: it changes the
#                  font scale, and puts it back)
. "$(dirname "$0")/lib.sh"
guard_emulator
[ "$KIND" = plus-rows ] || { echo "$(stamp) STOP: dispatch with kind=plus-rows (kind is $KIND)"; exit 7; }
RESULTS=()
child(){ # child <script>: one script's rows, its exit kept
  local s=$1 rc=0
  echo "$(stamp) ===== $s ====="
  bash "$HERE/$s.sh" || rc=$?
  RESULTS+=("$s=$rc")
  echo "$(stamp) ===== $s: exit $rc ====="
}
finish(){
  echo "$(stamp) F-B1 + PA-3: ${RESULTS[*]}"
  for r in "${RESULTS[@]}"; do [ "${r#*=}" = 0 ] || exit 1; done
}
trap finish EXIT
child fb1-night
child group-a-x2
