#!/usr/bin/env bash
# The Plus probe (decision 79), on the CI emulator only: run.sh calls it for
# kind plus-probe. Does the app stay up once Play Billing starts, without
# ACCESS_NETWORK_STATE, as the store build will be? Play Billing's logging
# library schedules its uploads with JobScheduler and a network constraint,
# which Android 14 may refuse without that permission (a SecurityException).
# The probe installs the app, starts it (Plus starts Play Billing at launch),
# waits, then says whether the app is still up and what was logged.
#
# env: APK (a staging profile build with PLUS_ENABLED, its manifest without
#      ACCESS_NETWORK_STATE), OUT (the evidence folder), SERIAL, APP_ID;
#      PROBE_WAIT (seconds, default 120).
# Exit: 0 the app stayed up; 1 it crashed or died; 3 inconclusive (Play
# Billing never showed up in the log); 7 or 8 the setup is wrong.
set -euo pipefail
: "${APK:?}" "${OUT:?}" "${SERIAL:?}" "${APP_ID:?}"
WAIT=${PROBE_WAIT:-120}
A() { adb -s "$SERIAL" "$@"; }

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

# What's under test: BILLING asked for, ACCESS_NETWORK_STATE not. Read whole,
# then searched (grep -q in a pipe can end adb early).
pkg=$(A shell dumpsys package "$APP_ID" | tr -d '\r')
grep -A30 "requested permissions" <<< "$pkg" > "$OUT/permissions.txt" \
  || echo "no requested permissions" > "$OUT/permissions.txt"
echo "== $APP_ID: requested permissions"; cat "$OUT/permissions.txt"
if grep -qF 'android.permission.ACCESS_NETWORK_STATE' "$OUT/permissions.txt"; then
  echo "STOP: the build asks for ACCESS_NETWORK_STATE; the probe needs it removed"; exit 7
fi
if ! grep -qF 'com.android.vending.BILLING' "$OUT/permissions.txt"; then
  echo "STOP: the build doesn't ask for BILLING"; exit 7
fi
# Play Billing talks to the Play Store app: this image must have it.
store=$(A shell pm path com.android.vending | tr -d '\r')
if [ -z "$store" ]; then echo "STOP: no Play Store app on this image"; exit 7; fi

A logcat -c
A shell monkey -p "$APP_ID" -c android.intent.category.LAUNCHER 1 > /dev/null
echo "started $APP_ID; watching for $WAIT s"
sleep "$WAIT"

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

security=$(grep -c 'SecurityException' "$OUT/probe-logcat.txt" || true)
billing=$(grep -cE 'BillingClient|BillingLogger' "$OUT/probe-logcat.txt" || true)
echo "app up: ${pid:-no} | crashes: $crashes | SecurityException lines: $security | Play Billing lines: $billing"
echo "== $APP_ID's jobs"; cat "$OUT/probe-jobs.txt"
if [ -z "$pid" ] || [ "$crashes" != 0 ]; then
  echo "PROBE: the app did not stay up"; exit 1
fi
if [ "$billing" = 0 ]; then
  echo "PROBE: inconclusive, Play Billing never showed up in the log"; exit 3
fi
echo "PROBE: the app stayed up with Play Billing started"
