#!/usr/bin/env bash
# Group B (#62, #55, #53, #59, #64, #67), retroactively on master (decision
# 86), in ONE emulator run: a staging debug build with NO fake_now (the app
# reads the real clock), and before each PR's rows the device's zone and clock
# are set by root to the moment those rows were written for (what fake_now
# used to freeze). Each PR's own script then runs unchanged, as a child.
#   pr55  UTC, 2026-11-28 12:00 (no clock dependence)
#   pr59  Asia/Bangkok, 2026-11-25 05:00 UTC (Wednesday 12:00 there)
#   pr53  Asia/Bangkok, 2026-11-28 16:00 UTC (23:00 there: the night pig)
#   pr64  UTC, 2026-11-28 05:00 (yesterday = Friday 27)
#   pr67  UTC, 2026-12-02 05:00 (a month's first week: the letter)
#   pr62  UTC, its own root clock moves (last: it puts auto_time back)
# The clock runs during each set (a few minutes, never across a day's turn);
# every set's flows start from a fresh launch.
. "$(dirname "$0")/lib.sh"
guard_emulator

A root >/dev/null 2>&1 || { sleep 3; A wait-for-device; A root >/dev/null 2>&1; }
sleep 3; A wait-for-device
if [ "$(A shell id -u | tr -d '\r')" != 0 ]; then
  echo "$(stamp) STOP: no root on this image: the device clock can't be moved"; exit 1
fi
A shell settings put global auto_time 0
A shell settings put global auto_time_zone 0

setzone(){ # setzone <tz>: the zone the app reads at its next start
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
set_of(){ # set_of <script> <zone> <date> <time|-> : one PR's rows, as a child
  local s=$1 zone=$2 d=$3 t=$4 rc=0
  echo "$(stamp) ===== $s: zone $zone, clock ${d} ${t} UTC ====="
  setzone "$zone"
  [ "$t" = - ] || setclock "$d" "$t"
  A shell am force-stop "$APP_ID"
  bash "$HERE/$s.sh" || rc=$?
  RESULTS+=("$s=$rc")
  echo "$(stamp) ===== $s: exit $rc ====="
}

finish(){
  A shell settings put global auto_time 1 >/dev/null 2>&1
  A shell settings put global auto_time_zone 1 >/dev/null 2>&1
  echo "$(stamp) GROUP B: ${RESULTS[*]}"
  for r in "${RESULTS[@]}"; do [ "${r#*=}" = 0 ] || exit 1; done
}
trap finish EXIT

set_of pr55 UTC          2026-11-28 12:00:00
set_of pr59 Asia/Bangkok 2026-11-25 05:00:00
set_of pr53 Asia/Bangkok 2026-11-28 16:00:00
set_of pr64 UTC          2026-11-28 05:00:00
set_of pr67 UTC          2026-12-02 05:00:00
set_of pr62 UTC          -          -
