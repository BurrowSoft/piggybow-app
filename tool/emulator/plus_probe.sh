#!/usr/bin/env bash
# The Plus probe (decision 79), on the CI emulator only: run.sh calls it for
# kind plus-probe. Does the app stay up once Play Billing starts, with the
# store build's permissions (INTERNET for pig tips, no ACCESS_NETWORK_STATE)? Play
# Billing's logging library schedules its uploads with JobScheduler and a
# network constraint, which Android 14 may refuse without
# ACCESS_NETWORK_STATE (a SecurityException), and it uploads from the app's
# own process. The probe installs the app, starts it (Plus starts Play
# Billing at launch), waits, then says whether the app is still up, what was
# logged, and how many bytes the app's own uid received and sent meanwhile
# (net_bytes.sh: data, not a pass or fail).
#
# env: APK (a staging profile build with PLUS_ENABLED and the release
#      manifest overlay), APP_DIR (the app's checkout), OUT (the evidence
#      folder), SERIAL, APP_ID; PROBE_WAIT (seconds, default 120).
# Exit: 0 the app stayed up; 1 it crashed or died; 3 inconclusive (Play
# Billing never showed up in the log); 7 the build or the image isn't the
# one to probe; 8 a set-up step failed; 9 reading the result failed.
set -Eeuo pipefail
for v in APK APP_DIR OUT SERIAL APP_ID; do
  [ -n "${!v:-}" ] || { echo "STOP: $v is not set"; exit 8; }
done
WAIT=${PROBE_WAIT:-120}
A() { adb -s "$SERIAL" "$@"; }
# A failed set-up command (an install, a pull, adb itself) is never read as
# "the app died".
trap 'echo "STOP: a set-up step failed (line $LINENO)"; exit 8' ERR

# The APK built in this job, installed, and the installed copy checked byte
# for byte against it.
built=$(sha256sum < "$APK" | cut -c1-64)
A uninstall "$APP_ID" >/dev/null 2>&1 || true
A install "$APK" | tail -1
path=$(A shell pm path "$APP_ID" | tr -d '\r' | sed -n '1s/^package://p')
A pull "$path" "$RUNNER_TEMP/installed.apk" >/dev/null
installed=$(sha256sum < "$RUNNER_TEMP/installed.apk" | cut -c1-64)
rm -f "$RUNNER_TEMP/installed.apk"
if [ "$installed" != "$built" ]; then
  echo "STOP: the installed APK ($installed) isn't the one built ($built)"; exit 8
fi
echo "installed = built ($installed)"

# What's under test: exactly the store build's permissions
# (android/expected-permissions.txt, the release list), the app's own
# permission named for this package. Read whole, then searched.
pkg=$(A shell dumpsys package "$APP_ID" | tr -d '\r')
awk '/requested permissions:/ { on = 1; next }
     on && /:/ { exit }
     on && NF { sub(/,$/, "", $1); print $1 }' <<< "$pkg" | sort -u > "$OUT/permissions.txt"
sed "s/^com\.burrowsoft\.piggybow\./$APP_ID./" "$APP_DIR/android/expected-permissions.txt" \
  | sort -u > "$RUNNER_TEMP/expected.txt"
echo "== $APP_ID: requested permissions"; cat "$OUT/permissions.txt"
if ! diff -u "$RUNNER_TEMP/expected.txt" "$OUT/permissions.txt"; then
  echo "STOP: the permissions aren't the store build's"; exit 7
fi
# Play Billing talks to the Play Store app: this image must have it.
store=$(A shell pm path com.android.vending | tr -d '\r' || true)
if [ -z "$store" ]; then echo "STOP: no Play Store app on this image"; exit 7; fi

# The app's own network use before it starts, for the bytes Play Billing sends.
NET="$(dirname "$0")/net_bytes.sh"
net_before=$(bash "$NET" "$SERIAL" "$APP_ID" "$OUT/probe-netstats-before.txt")
echo "before: $net_before"

A logcat -c
A shell monkey -p "$APP_ID" -c android.intent.category.LAUNCHER 1 > /dev/null
echo "started $APP_ID; watching for $WAIT s"
sleep "$WAIT"

trap 'echo "STOP: reading the result failed (line $LINENO)"; exit 9' ERR
pid=$(A shell pidof "$APP_ID" | tr -d '\r' || true)
A logcat -d -v threadtime > "$RUNNER_TEMP/logcat.txt"
# The evidence is only the lines about the app, Play Billing and its logging
# library, never the whole log.
grep -E "$APP_ID|BillingClient|BillingLogger|TRuntime|JobInfoScheduler|SecurityException|FATAL EXCEPTION|ACCESS_NETWORK_STATE" \
  "$RUNNER_TEMP/logcat.txt" > "$OUT/probe-logcat.txt" || true
crashes=$(grep -A3 'FATAL EXCEPTION' "$RUNNER_TEMP/logcat.txt" | grep -cF "Process: $APP_ID" || true)
rm -f "$RUNNER_TEMP/logcat.txt"
jobs=$(A shell dumpsys jobscheduler | tr -d '\r')
grep -A6 -F "$APP_ID" <<< "$jobs" > "$OUT/probe-jobs.txt" || echo "no job of $APP_ID" > "$OUT/probe-jobs.txt"
net_after=$(bash "$NET" "$SERIAL" "$APP_ID" "$OUT/probe-netstats-after.txt")

security=$(grep -c 'SecurityException' "$OUT/probe-logcat.txt" || true)
billing=$(grep -cE 'BillingClient|BillingLogger' "$OUT/probe-logcat.txt" || true)
echo "app up: ${pid:-no} | crashes: $crashes | SecurityException lines: $security | Play Billing lines: $billing"
echo "== $APP_ID's jobs"; cat "$OUT/probe-jobs.txt"
echo "== $APP_ID's network: before $net_before | after $net_after"
if [ -z "$pid" ] || [ "$crashes" != 0 ]; then
  echo "PROBE: the app did not stay up"; exit 1
fi
if [ "$billing" = 0 ]; then
  echo "PROBE: inconclusive, Play Billing never showed up in the log"; exit 3
fi
echo "PROBE: the app stayed up with Play Billing started"
