#!/usr/bin/env bash
# The CI emulator step (.github/workflows/emulator.yaml); never run on a PC.
# It checks the device is an emulator, sets the time zone and gesture
# navigation, logs the device's facts, then runs either the tester's device
# rows (tool/device-rows/$ROWS.sh at flows_ref) or the Maestro flows tagged
# $TAGS. Every adb call names the device. No env value or secret is printed.
#
# env: APK (built in the same job from HEAD_SHA), HEAD_SHA, FLOWS_DIR (the
#      flows_ref checkout), FLOWS_REF, TAGS, KIND, ROWS, ZONE, OUT (the
#      evidence folder); SERIAL (default emulator-5554), APP_ID (default the
#      staging package). Rows scripts also get FLOWS_SHA.
set -euo pipefail
: "${APK:?}" "${HEAD_SHA:?}" "${FLOWS_DIR:?}" "${FLOWS_REF:?}" "${TAGS:?}" "${KIND:?}" "${ZONE:?}" "${OUT:?}"
ROWS=${ROWS:-}
SERIAL=${SERIAL:-emulator-5554}
APP_ID=${APP_ID:-com.burrowsoft.piggybow.staging}
A() { adb -s "$SERIAL" "$@"; }
prop() { A shell getprop "$1" | tr -d '\r'; }
mkdir -p "$OUT"
exec > >(tee "$OUT/emulator.log") 2>&1

# An emulator only: a real phone attached by mistake is refused.
case "$SERIAL" in
  emulator-*) ;;
  *) echo "REFUSING: '$SERIAL' is not an emulator serial"; exit 9 ;;
esac
if [ "$(prop ro.kernel.qemu)" != 1 ] && [ "$(prop ro.boot.qemu)" != 1 ]; then
  echo "REFUSING: $SERIAL does not report an emulator"; exit 9
fi

# The time zone, before the app ever starts (UTC by default, for the
# fixtures). google_apis images allow adb root; the result is checked.
if [ "$(prop persist.sys.timezone)" != "$ZONE" ]; then
  A root >/dev/null
  A wait-for-device
  A shell setprop persist.sys.timezone "$ZONE"
fi
if [ "$(prop persist.sys.timezone)" != "$ZONE" ]; then
  echo "STOP: the zone is '$(prop persist.sys.timezone)', not '$ZONE'"; exit 7
fi

# Gesture navigation, as on most phones today.
A shell cmd overlay enable com.android.internal.systemui.navbar.gestural
sleep 2
# Read whole, then searched: grep -q in a pipe can end adb early (SIGPIPE),
# which pipefail would report as a failure.
overlays=$(A shell cmd overlay list | tr -d '\r')
if ! grep -qF '[x] com.android.internal.systemui.navbar.gestural' <<< "$overlays"; then
  echo "STOP: gesture navigation didn't turn on"; exit 7
fi

# English (US), the emulator's default; checked, never assumed.
locale=$(prop persist.sys.locale)
[ -n "$locale" ] || locale=$(prop ro.product.locale)
if [ "$locale" != en-US ]; then echo "STOP: the locale is '$locale', not en-US"; exit 7; fi

echo "emulator $SERIAL: Android $(prop ro.build.version.release) (API $(prop ro.build.version.sdk)), $(A shell wm size | tr -d '\r'), $(A shell wm density | tr -d '\r')"
echo "zone $ZONE ($(A shell date | tr -d '\r')) | locale $locale | gesture navigation on"
# Both commits a row rests on: the app built, and the flows run.
FLOWS_SHA=$(git -C "$FLOWS_DIR" rev-parse HEAD)
echo "head $HEAD_SHA | flows $FLOWS_REF = $FLOWS_SHA | kind $KIND | APK sha256 $(sha256sum < "$APK" | cut -c1-64) (built in this job)"

export APK HEAD_SHA FLOWS_SHA OUT SERIAL APP_ID KIND
export FLOWS="$FLOWS_DIR/.maestro"

# The tester's device rows: the script installs and checks the APK itself.
if [ -n "$ROWS" ]; then
  rows="$FLOWS_DIR/tool/device-rows/$ROWS.sh"
  [ -f "$rows" ] || { echo "STOP: no tool/device-rows/$ROWS.sh at flows_ref"; exit 2; }
  bash "$rows"
  exit
fi

# The Maestro flows: the APK installed, and the installed copy checked byte
# for byte against the one built.
[ -d "$FLOWS" ] || { echo "STOP: no .maestro/ at flows_ref"; exit 2; }
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
maestro --device "$SERIAL" test -e APP_ID="$APP_ID" --include-tags "$TAGS" \
  --test-output-dir "$OUT/maestro" --format junit --output "$OUT/maestro-junit.xml" \
  "$FLOWS"
