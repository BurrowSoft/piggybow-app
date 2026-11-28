#!/usr/bin/env bash
# Group E (repeats: #70, #73, #77) and the backup file (#87), retroactively on
# master (decision 86), in ONE emulator run, staging debug, no fake_now, zone
# UTC: group-e.sh moves the device clock itself (root) and puts it back;
# pr87.sh doesn't depend on the clock. Each runs unchanged, as a child.
. "$(dirname "$0")/lib.sh"
guard_emulator

RESULTS=()
run(){ local s=$1 rc=0
  echo "$(stamp) ===== $s ====="
  A shell am force-stop "$APP_ID"
  bash "$HERE/$s.sh" || rc=$?
  RESULTS+=("$s=$rc"); echo "$(stamp) ===== $s: exit $rc ====="
}
finish(){
  echo "$(stamp) GROUP E + #87: ${RESULTS[*]}"
  for r in "${RESULTS[@]}"; do [ "${r#*=}" = 0 ] || exit 1; done
}
trap finish EXIT

run group-e
run pr87
