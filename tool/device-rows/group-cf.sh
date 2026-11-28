#!/usr/bin/env bash
# Groups C (#57, #56, #61, #60, #63, #66) and F (#74, #76), retroactively on
# master (decision 86), in ONE emulator run: a staging debug build with NO
# fake_now; before each PR's rows, root sets the device's zone and clock to
# the moment they were written for, and that PR's own script runs unchanged.
#   pr57, pr56, pr61, pr66   UTC, 2026-11-28 12:00
#   pr60                     UTC, 2026-11-28 05:00 (Saturday 28)
#   pr63                     Asia/Bangkok, 2026-11-27 05:00 UTC (Friday noon)
#   group-f                  UTC, 2026-11-28 12:00 (the trip row)
# Every set starts from a fresh launch; none runs across a day's turn.
. "$(dirname "$0")/lib.sh"
guard_emulator

A root >/dev/null 2>&1 || { sleep 3; A wait-for-device; A root >/dev/null 2>&1; }
sleep 3; A wait-for-device
if [ "$(A shell id -u | tr -d '\r')" != 0 ]; then
  echo "$(stamp) STOP: no root on this image: the device clock can't be moved"; exit 1
fi
A shell settings put global auto_time 0
A shell settings put global auto_time_zone 0

setzone(){
  A shell setprop persist.sys.timezone "$1"
  local now; now=$(A shell getprop persist.sys.timezone | tr -d '\r')
  [ "$now" = "$1" ] || { echo "$(stamp) STOP: the zone is '$now', not '$1'"; exit 7; }
}
setclock(){ # setclock <YYYY-MM-DD> <HH:MM:SS>, in UTC
  local d=$1 t=$2
  A shell date -u "${d:5:2}${d:8:2}${t:0:2}${t:3:2}${d:0:4}.${t:6:2}" >/dev/null
  echo "$(stamp) device clock: $(A shell date -u | tr -d '\r') | zone $(A shell getprop persist.sys.timezone | tr -d '\r')"
}

RESULTS=()
set_of(){ # set_of <script> <zone> <date> <time>
  local s=$1 zone=$2 d=$3 t=$4 rc=0
  echo "$(stamp) ===== $s: zone $zone, clock $d $t UTC ====="
  setzone "$zone"; setclock "$d" "$t"
  A shell am force-stop "$APP_ID"
  bash "$HERE/$s.sh" || rc=$?
  RESULTS+=("$s=$rc")
  echo "$(stamp) ===== $s: exit $rc ====="
}

finish(){
  A shell settings put global auto_time 1 >/dev/null 2>&1
  A shell settings put global auto_time_zone 1 >/dev/null 2>&1
  echo "$(stamp) GROUPS C+F: ${RESULTS[*]}"
  for r in "${RESULTS[@]}"; do [ "${r#*=}" = 0 ] || exit 1; done
}
trap finish EXIT

set_of pr57    UTC          2026-11-28 12:00:00
set_of pr56    UTC          2026-11-28 12:00:00
set_of pr61    UTC          2026-11-28 12:00:00
set_of pr60    UTC          2026-11-28 05:00:00
set_of pr63    Asia/Bangkok 2026-11-27 05:00:00
set_of pr66    UTC          2026-11-28 12:00:00
set_of group-f UTC          2026-11-28 12:00:00
